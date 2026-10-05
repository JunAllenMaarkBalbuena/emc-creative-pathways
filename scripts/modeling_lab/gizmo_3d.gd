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
var _pivot_active: bool = false
var _pivot: Vector3 = Vector3.ZERO
var _dragging: bool = false
var _drag_axis: Vector3 = Vector3.ZERO
var _camera: Camera3D = null

## Distance at which the handles are built at their native 1.0 scale. The
## gizmo is constant-on-screen: it scales up with camera distance so the
## 0.04-radius shafts never alias below a pixel when you zoom out (previously
## it "slowly disappeared" in the snap/zoom views — the thin cylinders became
## sub-pixel wide and faded away while the grid stayed crisp and read as
## overlapping it).
const NATIVE_DISTANCE := 8.0
const MIN_SCALE := 0.5
const MAX_SCALE := 60.0

signal transform_began(axis: Vector3)
signal transform_ended

var _handle_root: Node3D

func set_camera(camera: Camera3D):
	_camera = camera

# NOTE(regression): the constant-on-screen scaling in _process only activates
# when set_camera() has been called. modeling_lab.gd MUST wire this exactly
# like view_orbit_gizmo.set_camera(camera_controller.camera) — otherwise the
# gizmo stays fixed-world-size and "slowly disappears / overlaps the grid"
# as you zoom out (the thin 0.04-radius shafts go sub-pixel while the grid
# stays crisp and reads as overlapping the gizmo).

func _ready():
	_handle_root = Node3D.new()
	_handle_root.name = "Handles"
	add_child(_handle_root)
	_build_handles()

func set_target(node: Node3D):
	if node != null and not is_instance_valid(node):
		node = null
	_target = node
	_pivot_active = false
	visible = node != null
	if node:
		global_position = node.global_position

## Positions the gizmo at a shared pivot (multi-selection centroid) instead of
## tracking a single target node. Mode must already be set via set_mode() so
## the correct handles are built.
func set_pivot(pos: Vector3):
	_target = null
	_pivot_active = true
	_pivot = pos
	global_position = pos
	visible = true

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
	if not visible or not camera:
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
			# The 3D point the cursor actually struck. Screen position cannot
			# separate the two halves of a rotate ring that is exactly edge-on
			# (they project to the same pixel), so callers that need to know
			# which side was grabbed need this.
			"position": result.position,
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
	# Opacity matters: at low alpha the bright grid lines show through the
	# handle bodies and read as the grid overlapping the gizmo (worst in the
	# orthographic snap views, where the red X arrow sits on the grid's red
	# X axis line). Keep it near-opaque so the handles hold their color.
	mat.albedo_color = Color(color.r, color.g, color.b, 0.9)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.45
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	# UI-level guarantee: gizmo materials sort DEAD-LAST in the transparent
	# pass (render_priority > everything, including any other transparent
	# surface). Combined with no_depth_test + alpha this makes the gizmo draw
	# over *everything* — grid, other handles, any transparent object — at
	# every camera angle, exactly like a UI overlay. The opaque grid can never
	# win a pixel, and no transparent sibling can sort after it either.
	mat.render_priority = 10
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
	# Self-heal: if the targeted node was freed (delete, undo of spawn), drop it
	# and hide instead of tracking a freed instance and resurrecting every frame.
	if _target and not is_instance_valid(_target):
		_target = null
		_pivot_active = false
		visible = false
		return
	if _target and visible:
		global_position = _target.global_position
	elif _pivot_active and visible:
		global_position = _pivot

	# Constant-screen-size: the gizmo used to be a FIXED world-size object
	# (0.04-radius shafts, ~1 unit tall), so it shrank to sub-pixel width as
	# you zoomed out to place/fit whole scenes — the thin shafts aliased, then
	# faded entirely, while the near-infinite grid stayed crisp and read as
	# overlapping the gizmo. Real editors (Blender, Unity, Godot's own outline
	# gizmos) keep the transform gizmo at constant screen size by scaling it
	# with camera distance. Inject the camera distance here and scale the
	# handle root so the projected size of every handle stays constant.
	if _camera and visible:
		var d := _camera.global_position.distance_to(global_position)
		if d > 0.0:
			var s := clampf(
				d / NATIVE_DISTANCE,
				MIN_SCALE,
				MAX_SCALE,
			)
			# Uniform scale so axes keep their exact screen direction — and
			# scale the whole handle tree (shafts + pick collision shapes
			# scale together; the drag axis / uniform flags live in Area meta,
			# so picking and drags keep working at any zoom).
			_handle_root.scale = Vector3.ONE * s
	visible = (_target != null) or _pivot_active
