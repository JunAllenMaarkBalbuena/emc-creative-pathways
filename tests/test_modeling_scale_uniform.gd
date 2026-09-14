extends Node

## Regression test: uniform scale must be able to SHRINK.
## Root cause: the handler computed the uniform scale delta as
## dist(mouse, gizmo-center) - dist(grab-point, gizmo-center). Since the
## grab point IS the center handle (projected over the object center), that
## reference is ~0, so the delta was always >= 0: dragging only ever grew
## the object. The fix makes the delta the signed screen projection of the
## drag from the grab point (same formula the axial handles use).

var _fail := 0

func _ready() -> void:
	var tree := get_tree()
	var lab: ModelingLab = (load("res://scenes/modeling_lab/modeling_lab.tscn") as PackedScene).instantiate()
	add_child(lab)
	tree.create_timer(20.0).timeout.connect(_on_watchdog)
	await tree.process_frame
	await tree.process_frame
	lab._enter_creative_studio()
	await tree.process_frame
	lab._on_spawn_selected(PrimitiveDef.Type.CUBE)
	await tree.process_frame
	lab._on_tool_selected(ModelingLab.Tool.SCALE)

	var cube: MeshInstance3D = lab.selection_manager.get_selected()
	var cam: Camera3D = lab.camera_controller.camera
	var center: Vector2 = cam.unproject_position(cube.global_position)
	var grab_origin: Vector2 = center

	# Grab the uniform (center) handle, then drag LEFT 100px on screen.
	# The scale handler turns that screen motion into a delta; a leftward drag
	# from the center handle must be NEGATIVE so the object shrinks.
	var to_left: Vector2 = center - Vector2(100, 0)
	var delta_left: float = lab._scale_delta(to_left, grab_origin, Vector2.RIGHT)
	lab.transform_manager.begin_scale(true)
	lab.transform_manager.apply_scale(Vector3.ZERO, delta_left, true)
	lab.transform_manager.end_scale()
	await tree.process_frame

	if delta_left >= 0.0:
		_fail += 1
		print("FAIL: leftward uniform drag must give a negative scale delta, got %f" % delta_left)
	if cube.scale.x >= 1.0:
		_fail += 1
		print("FAIL: dragging left from the center handle should shrink the cube, got %s" % cube.scale)

	# Dragging RIGHT must grow relative to the current scale.
	var before_right: float = cube.scale.x
	var delta_right: float = lab._scale_delta(center + Vector2(100, 0), grab_origin, Vector2.RIGHT)
	lab.transform_manager.begin_scale(true)
	lab.transform_manager.apply_scale(Vector3.ZERO, delta_right, true)
	lab.transform_manager.end_scale()
	await tree.process_frame
	if cube.scale.x <= before_right:
		_fail += 1
		print("FAIL: dragging right from the center handle should grow the cube, got %s (was %f)" % [cube.scale, before_right])

	# A sensible drag distance must actually move the scale noticeably
	# (the old 0.0002/pixel sensitivity made scale feel dead).
	if is_equal_approx(cube.scale.x, 1.0):
		_fail += 1
		print("FAIL: a 100px scale drag should visibly change the scale, got %s" % cube.scale)

	if _fail == 0:
		print("PASS: uniform scale shrinks and grows symmetrically from the center handle")
	_quit()

func _on_watchdog():
	get_tree().quit(2)

func _quit():
	get_tree().quit(1 if _fail > 0 else 0)