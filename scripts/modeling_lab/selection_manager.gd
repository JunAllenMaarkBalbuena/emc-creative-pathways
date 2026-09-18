class_name SelectionManager
extends RefCounted

signal selected_changed(node: MeshInstance3D)

var _object_container: Node3D
var _selected: MeshInstance3D = null
var _base_materials: Dictionary = {}

func _init(container: Node3D):
	_object_container = container

func select_from_click(screen_pos: Vector2, camera: Camera3D) -> bool:
	var space: PhysicsDirectSpaceState3D = camera.get_world_3d().direct_space_state
	if not space:
		return false
	var from: Vector3 = camera.project_ray_origin(screen_pos)
	var dir: Vector3 = camera.project_ray_normal(screen_pos)
	var params := PhysicsRayQueryParameters3D.new()
	params.from = from
	params.to = from + dir * 1000.0
	params.collision_mask = 1
	params.collide_with_areas = true

	var result: Dictionary = space.intersect_ray(params)
	if result.is_empty():
		deselect_all()
		return false
	var hit: MeshInstance3D = _resolve_selectable(result.collider)
	if hit and _is_selectable(hit):
		select(hit)
		return true
	deselect_all()
	return false

func _resolve_selectable(collider: Object) -> MeshInstance3D:
	if collider is MeshInstance3D:
		return collider
	if collider is Area3D:
		var area := collider as Area3D
		var parent: Node = area.get_parent()
		if parent is MeshInstance3D:
			return parent
	return null

func _is_selectable(node: Node) -> bool:
	if not node is MeshInstance3D:
		return false
	if node.is_in_group("ghost_guides"):
		return false
	return true

func select(node: MeshInstance3D):
	if not is_instance_valid(node):
		return
	if _selected == node:
		return
	_clear_stale_selection()
	_deselect_highlight(_selected)
	_selected = node
	_select_highlight(_selected)
	selected_changed.emit(_selected)

func deselect_all():
	_clear_stale_selection()
	if _selected:
		_deselect_highlight(_selected)
		_selected = null
		selected_changed.emit(null)

func _clear_stale_selection():
	if not is_instance_valid(_selected):
		_selected = null

func get_selected() -> MeshInstance3D:
	return _selected

func select_node(node: Node3D):
	if node is MeshInstance3D and is_instance_valid(node):
		select(node)

func _select_highlight(mi: MeshInstance3D):
	if not mi: return
	var id := mi.get_instance_id()
	if not _base_materials.has(id):
		_base_materials[id] = mi.get_surface_override_material(0)
	var mat := StandardMaterial3D.new()
	mat.set_meta("gizmo_highlight", true)
	var base_albedo := Color(0.5, 0.5, 0.5)
	var base_mat: Material = _base_materials.get(id)
	if base_mat is StandardMaterial3D:
		base_albedo = (base_mat as StandardMaterial3D).albedo_color
	mat.albedo_color = base_albedo.lerp(Color(0.72, 0.84, 1.0), 0.35)
	# IMPORTANT: do NOT set no_depth_test here. Disabling the depth test on the
	# highlight material removes the selected object from the shadow pass, so
	# its soft drop shadow disappears while selected (and returns on deselect).
	mi.set_surface_override_material(0, mat)

func _deselect_highlight(mi: MeshInstance3D):
	if mi == null or not is_instance_valid(mi):
		return
	var id := mi.get_instance_id()
	var current: Material = mi.get_surface_override_material(0)
	if not current or not current.get_meta("gizmo_highlight", false):
		_base_materials.erase(id)
		return
	var base: Material = _base_materials.get(id)
	mi.set_surface_override_material(0, base)
	_base_materials.erase(id)
