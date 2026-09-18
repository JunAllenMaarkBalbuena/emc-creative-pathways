class_name Gizmo3D
extends Node3D

enum Mode { TRANSLATE, ROTATE, SCALE }

const GIZMO_LAYER := 2
const AXES: Array[Vector3] = [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
const AXIS_COLORS: Array[Color] = [
	Color(1.0, 0.25, 0.25),
	Color(0.25, 1.0, 0.25),
	Color(0.3, 0.5, 1.0),
]

var current_mode: int = Mode.TRANSLATE
var _target: Node3D = null
var _dragging: bool = false
var _drag_axis: Vector3 = Vector3.ZERO

signal transform_began(axis: Vector3)
signal transform_ended

var _handle_root: Node3D

func _ready():
	_handle_root = Node3D.new()
	_handle_root.name = "Handles"
	add_child(_handle_root)
	_build_handles()

func set_target(node: Node3D):
	_target = node
	visible = node != null
	if node:
		global_position = node.global_position

func set_mode(mode: int):
	if current_mode == mode:
		return
	current_mode = mode
	_build_handles()

func get_drag_axis() -> Vector3:
	return _drag_axis

func is_dragging() -> bool:
	return _dragging

func begin_drag(axis: Vector3):
	_dragging = true
	_drag_axis = axis
	transform_began.emit(axis)

func end_drag():
	_dragging = false
	transform_ended.emit()

func pick(screen_pos: Vector2, camera: Camera3D) -> Dictionary:
	if not _target or not camera or not visible:
		return {"picked": false, "axis": Vector3.ZERO, "uniform": false}
	var space := camera.get_world_3d().direct_space_state
	if not space:
		return {"picked": false, "axis": Vector3.ZERO, "uniform": false}
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	var params := PhysicsRayQueryParameters3D.new()
	params.from = from
	params.to = from + dir * 1000.0
	params.collision_mask = GIZMO_LAYER
	params.collide_with_areas = true

	var result: Dictionary = space.intersect_ray(params)
	if result.is_empty():
		return {"picked": false, "axis": Vector3.ZERO, "uniform": false}
	var collider := result.collider as Area3D
	if collider:
		return {
			"picked": true,
			"axis": collider.get_meta("axis", Vector3.ZERO),
			"uniform": collider.get_meta("uniform", false),
		}
	return {"picked": false, "axis": Vector3.ZERO, "uniform": false}

func _build_handles():
	if not _handle_root:
		return
	for child in _handle_root.get_children():
		child.queue_free()
	match current_mode:
		Mode.TRANSLATE:
			_build_translate()
		Mode.ROTATE:
			_build_rotate()
		Mode.SCALE:
			_build_scale()

func _make_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color.r, color.g, color.b, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.45
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	return mat

func _orientation_for_axis(axis: Vector3) -> Basis:
	if axis.is_equal_approx(Vector3.UP):
		return Basis.IDENTITY
	return Basis(Quaternion(Vector3.UP, axis.normalized()))

func _build_translate():
	for i in AXES.size():
		var axis: Vector3 = AXES[i]
		var color: Color = AXIS_COLORS[i]
		var group := Node3D.new()
		group.name = "Arrow_" + str(i)
		group.transform = Transform3D(_orientation_for_axis(axis), Vector3.ZERO)
		_handle_root.add_child(group)

		var shaft_mesh := CylinderMesh.new()
		shaft_mesh.top_radius = 0.04
		shaft_mesh.bottom_radius = 0.04
		shaft_mesh.height = 0.9
		var shaft := MeshInstance3D.new()
		shaft.mesh = shaft_mesh
		shaft.material_override = _make_material(color)
		shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		shaft.position = Vector3(0, 0.55, 0)
		group.add_child(shaft)

		var head_mesh := CylinderMesh.new()
		head_mesh.top_radius = 0.0
		head_mesh.bottom_radius = 0.12
		head_mesh.height = 0.3
		var head := MeshInstance3D.new()
		head.mesh = head_mesh
		head.material_override = _make_material(color)
		head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		head.position = Vector3(0, 1.25, 0)
		group.add_child(head)

		var area := Area3D.new()
		area.name = "Pick_" + str(i)
		area.collision_layer = GIZMO_LAYER
		area.collision_mask = 0
		area.set_meta("axis", axis)
		area.set_meta("uniform", false)
		var cs := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = 0.18
		shape.height = 1.7
		cs.shape = shape
		cs.position = Vector3(0, 0.85, 0)
		area.add_child(cs)
		group.add_child(area)

func _build_rotate():
	for i in AXES.size():
		var axis: Vector3 = AXES[i]
		var color: Color = AXIS_COLORS[i]
		var group := Node3D.new()
		group.name = "Ring_" + str(i)
		group.transform = Transform3D(_orientation_for_axis(axis), Vector3.ZERO)
		_handle_root.add_child(group)

		var torus_mesh := TorusMesh.new()
		torus_mesh.inner_radius = 0.85
		torus_mesh.outer_radius = 1.0
		torus_mesh.rings = 64
		torus_mesh.ring_segments = 8
		var ring := MeshInstance3D.new()
		ring.mesh = torus_mesh
		ring.material_override = _make_material(color)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		group.add_child(ring)

		var area := Area3D.new()
		area.name = "Pick_" + str(i)
		area.collision_layer = GIZMO_LAYER
		area.collision_mask = 0
		area.set_meta("axis", axis)
		area.set_meta("uniform", false)
		var cs := CollisionShape3D.new()
		cs.shape = torus_mesh.create_trimesh_shape()
		area.add_child(cs)
		group.add_child(area)

func _build_scale():
	for i in AXES.size():
		var axis: Vector3 = AXES[i]
		var color: Color = AXIS_COLORS[i]
		var group := Node3D.new()
		group.name = "Cube_" + str(i)
		group.transform = Transform3D(_orientation_for_axis(axis), Vector3.ZERO)
		_handle_root.add_child(group)

		var box_mesh := BoxMesh.new()
		box_mesh.size = Vector3(0.22, 0.22, 0.22)
		var cube := MeshInstance3D.new()
		cube.mesh = box_mesh
		cube.material_override = _make_material(color)
		cube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cube.position = Vector3(0, 1.25, 0)
		group.add_child(cube)

		var area := Area3D.new()
		area.name = "Pick_" + str(i)
		area.collision_layer = GIZMO_LAYER
		area.collision_mask = 0
		area.set_meta("axis", axis)
		area.set_meta("uniform", false)
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.3, 0.3, 0.3)
		cs.shape = shape
		cs.position = Vector3(0, 1.25, 0)
		area.add_child(cs)
		group.add_child(area)

	var center_group := Node3D.new()
	center_group.name = "Cube_Center"
	_handle_root.add_child(center_group)
	var center_mesh := BoxMesh.new()
	center_mesh.size = Vector3(0.26, 0.26, 0.26)
	var center_cube := MeshInstance3D.new()
	center_cube.mesh = center_mesh
	center_cube.material_override = _make_material(Color(1.0, 1.0, 1.0))
	center_cube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	center_group.add_child(center_cube)

	var center_area := Area3D.new()
	center_area.name = "Pick_center"
	center_area.collision_layer = GIZMO_LAYER
	center_area.collision_mask = 0
	center_area.set_meta("axis", Vector3.ZERO)
	center_area.set_meta("uniform", true)
	var center_cs := CollisionShape3D.new()
	var center_shape := BoxShape3D.new()
	center_shape.size = Vector3(0.34, 0.34, 0.34)
	center_cs.shape = center_shape
	center_area.add_child(center_cs)
	center_group.add_child(center_area)

func _process(_delta):
	if _target and visible:
		global_position = _target.global_position
