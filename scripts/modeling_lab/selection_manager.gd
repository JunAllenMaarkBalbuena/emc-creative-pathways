class_name SelectionManager
extends RefCounted

signal selected_changed(node: MeshInstance3D)

var _object_container: Node3D
var _selected: MeshInstance3D = null
var _selection: Array[MeshInstance3D] = []

func _init(container: Node3D):
	_object_container = container

func select_from_click(screen_pos: Vector2, camera: Camera3D) -> bool:
	# Clicking an already-selected member of a multi-selection must NOT
	# collapse the set — that click starts the body-drag in the caller.
	var hit := pick_object(screen_pos, camera)
	if hit:
		if _selection.size() > 1 and _selection.has(hit):
			return true
		# Single click: if the mesh is inside a group, select all group members.
		var group_parent := get_group_parent(hit)
		if group_parent:
			var members: Array[MeshInstance3D] = []
			_collect_group_members(group_parent, members)
			if members.size() > 1:
				select_multi(members)
				return true
		select(hit)
		return true
	deselect_all()
	return false

func pick_object(screen_pos: Vector2, camera: Camera3D) -> MeshInstance3D:
	var space: PhysicsDirectSpaceState3D = camera.get_world_3d().direct_space_state
	if not space:
		return null
	var from: Vector3 = camera.project_ray_origin(screen_pos)
	var dir: Vector3 = camera.project_ray_normal(screen_pos)
	var params := PhysicsRayQueryParameters3D.new()
	params.from = from
	params.to = from + dir * 1000.0
	params.collision_mask = 1
	params.collide_with_areas = true

	var result: Dictionary = space.intersect_ray(params)
	if result.is_empty():
		return null
	var hit: MeshInstance3D = _resolve_selectable(result.collider)
	if hit and _is_selectable(hit):
		return hit
	return null

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
	if _selected == node and _selection.size() <= 1:
		return
	_clear_stale_selection()
	for n in _selection:
		if is_instance_valid(n):
			_deselect_highlight(n)
	_selected = node
	_selection = [node]
	_select_highlight(_selected)
	selected_changed.emit(_selected)

func select_multi(nodes: Array[MeshInstance3D]):
	_clear_stale_selection()
	var old := _selection
	var fresh: Array[MeshInstance3D] = []
	for n in nodes:
		if is_instance_valid(n) and _is_selectable(n) and not fresh.has(n):
			fresh.append(n)
	if fresh.is_empty():
		deselect_all()
		return
	for n in old:
		if is_instance_valid(n) and not fresh.has(n):
			_deselect_highlight(n)
	for n in fresh:
		_select_highlight(n)
	_selection = fresh
	_selected = fresh[0]
	selected_changed.emit(_selected)

func deselect_all():
	var had_selection := _selected != null or not _selection.is_empty()
	_clear_stale_selection()
	for n in _selection:
		if is_instance_valid(n):
			_deselect_highlight(n)
	_selection = []
	if _selected:
		_deselect_highlight(_selected)
	_selected = null
	# Always notify even if the selected node was already freed: _clear_stale_selection
	# nulls it silently, and without this the gizmo keeps targeting a freed node.
	if had_selection:
		selected_changed.emit(null)

func _clear_stale_selection():
	var i := 0
	while i < _selection.size():
		if not is_instance_valid(_selection[i]):
			_selection.remove_at(i)
		else:
			i += 1
	if not is_instance_valid(_selected):
		_selected = null

func get_selected() -> MeshInstance3D:
	_clear_stale_selection()
	return _selected

func selected_nodes() -> Array[MeshInstance3D]:
	_clear_stale_selection()
	return _selection.duplicate()

func selected_count() -> int:
	return _selection.size()

func is_selected(node: Node) -> bool:
	return node in _selection


## Returns true if the node is inside a group AND every member of that group
## is currently selected (the selection count equals the group size).
## Used to decide whether a double-click should "drill down" from a full group
## selection to a single member (group -> member) for better flexibility.
func is_full_group_selected(node: MeshInstance3D) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	var group := get_group_parent(node)
	if group == null:
		return false
	var members: Array[MeshInstance3D] = []
	_collect_group_members(group, members)
	if members.size() <= 1:
		return false
	if _selection.size() != members.size():
		return false
	for m in members:
		if not _selection.has(m):
			return false
	return true

func get_centroid() -> Vector3:
	var nodes := _selection
	if nodes.is_empty() and _selected:
		nodes = [_selected]
	if nodes.is_empty():
		return Vector3.ZERO
	var acc := Vector3.ZERO
	var count := 0
	for n in nodes:
		if is_instance_valid(n):
			acc += n.global_position
			count += 1
	if count == 0:
		return Vector3.ZERO
	return acc / count

func select_node(node: Node3D):
	if node is MeshInstance3D and is_instance_valid(node):
		select(node)


## Re-point the current selection onto a fresh set of node instance IDs.
## The snapshot undo system rebuilds node instances when a transform/material/
## spawn command applies, so whatever the gizmo/lab cached before is now freed.
## Call this with action.get_last_created_ids() after executing/undoing/redoing
## to keep the selection — and therefore the gizmo — tracking live nodes.
func reselect_from_ids(ids: Array) -> void:
	if ids.is_empty():
		return
	var meshes: Array[MeshInstance3D] = []
	for id in ids:
		var node := instance_from_id(id) as MeshInstance3D
		if node and is_instance_valid(node) and _is_selectable(node) and not meshes.has(node):
			meshes.append(node)
	if meshes.is_empty():
		return
	if _selection.size() == meshes.size():
		var same := true
		for m in meshes:
			if not _selection.has(m):
				same = false
				break
		if same:
			return
	if meshes.size() > 1:
		select_multi(meshes)
	else:
		select(meshes[0])

func _select_highlight(mi: MeshInstance3D):
	if not mi: return
	# The highlight is a separate indicator layer rendered on top of the
	# object's real material via material_overlay. The base material (albedo,
	# alpha/transparency, metallic, roughness) is never touched, so the
	# object's state stays exactly as the wheel/UI configured it.
	var mat := StandardMaterial3D.new()
	mat.set_meta("gizmo_highlight", true)
	var base_albedo := Color(0.5, 0.5, 0.5)
	var base_mat: Material = mi.get_active_material(0)
	if base_mat is StandardMaterial3D:
		base_albedo = (base_mat as StandardMaterial3D).albedo_color
	var tint := base_albedo.lerp(Color(0.72, 0.84, 1.0), 0.35)
	mat.albedo_color = Color(tint.r, tint.g, tint.b, 0.45)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Keep the depth test ENABLED: the overlay must only cover this object's
	# own pixels (never tint through occluders / the grid), and transparent
	# no_depth_test surfaces leave the lit/shadow pass look.
	mi.material_overlay = mat

func _deselect_highlight(mi: MeshInstance3D):
	if mi == null or not is_instance_valid(mi):
		return
	var current: Material = mi.material_overlay
	if current and current.get_meta("gizmo_highlight", false):
		mi.material_overlay = null


func get_group_parent(node: Node) -> Node3D:
	# Walk up from a MeshInstance3D to find a Node3D group parent
	# (a Node3D that is NOT a MeshInstance3D). Stop at _object_container
	# so standalone meshes at the root level are not误treated as a group.
	if node == null:
		return null
	var p: Node = node.get_parent()
	while p and p != _object_container:
		if p is Node3D and not p is MeshInstance3D:
			return p
		p = p.get_parent()
	return null


func _collect_group_members(group: Node, output: Array[MeshInstance3D]):
	for child in group.get_children():
		if child is MeshInstance3D and not child.is_in_group("ghost_guides"):
			output.append(child)
		elif child is Node3D and not child is MeshInstance3D:
			_collect_group_members(child, output)


## Collect every selectable MeshInstance3D in the object container, recursively
## descending through group nodes. The rubber-band box select needs the same
## set as the physics click path sees; without recursing, grouped members are
## invisible to box-select and the group can never be selected that way.
func collect_selectable_meshes() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	_collect_from_node(_object_container, out)
	return out


func _collect_from_node(node: Node, output: Array[MeshInstance3D]):
	for child in node.get_children():
		if child is MeshInstance3D and not child.is_in_group("ghost_guides"):
			output.append(child)
		elif child is Node3D and not child is MeshInstance3D:
			_collect_from_node(child, output)
