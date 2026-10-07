extends Node

## Regression test for audit item 11: the move gizmo dragged far too fast.
##
## modeling_lab.gd converted the cursor's pixel travel into world units with a
## hardcoded `dist * 0.02` - 0.02 world units per pixel no matter the camera
## distance or fov. At the default view that is roughly twice the real scale,
## and it is wrong at every other zoom: pull back and the object bolts away
## from the cursor, push in and it crawls.
##
## The contract is 1:1 tracking: grabbing a move handle and dragging the cursor
## moves the grabbed point exactly as far, on screen, as the cursor moved - at
## any camera distance. It is asserted in SCREEN space, so it is the observable
## behaviour rather than a re-statement of whatever formula the fix uses.
##
## The cursor is fed through the real handler: `_on_viewport_gui_input` reads
## `%SubViewport.get_mouse_position()`, which is the OS cursor mapped through the
## viewport's screen transform, so a parsed motion event at
## `screen_transform * point` puts the handler's cursor exactly at `point`.

## AXES[0] - the red X handle. The default camera is pitched about X, so the X
## axis stays fully in the view plane and projects to a clean horizontal run.
const AXIS_LOCAL: Vector3 = Vector3.RIGHT
const DRAG_PX := 60.0
const TOLERANCE_PX := 3.0

var _fail := 0
var _lab: ModelingLab
var _sv: SubViewport
var _cont: SubViewportContainer
var _cam: Camera3D
var _cube: MeshInstance3D

func _ready() -> void:
	var tree := get_tree()
	_lab = (load("res://scenes/modeling_lab/modeling_lab.tscn") as PackedScene).instantiate()
	add_child(_lab)
	tree.create_timer(20.0).timeout.connect(_on_watchdog)
	await tree.process_frame
	await tree.process_frame
	_lab._enter_creative_studio()
	await tree.process_frame
	_lab._on_spawn_selected(PrimitiveDef.Type.CUBE)
	await tree.process_frame

	_cube = _lab.selection_manager.get_selected()
	_cam = _lab.camera_controller.camera
	_sv = _lab.get_node_or_null("%SubViewport") as SubViewport
	_cont = _lab.get_node_or_null("%SubViewportContainer") as SubViewportContainer
	if _cube == null or _cam == null or _sv == null or _cont == null:
		_fail += 1
		print("FAIL: could not obtain the cube / camera / viewport to test against")
		_finish()
		return

	# Position snapping would quantise the result and mask the gain entirely.
	_lab.snap_settings.snap_enabled = false

	await _test_move_tracks_cursor_1to1()
	await _test_move_tracks_cursor_when_zoomed_out()

	_finish()

## At the shipped default camera distance a 60px drag must move the object's
## projection 60px. The old 0.02 turned the same 60px into ~1.2 world units,
## which projects back to well over 100px.
func _test_move_tracks_cursor_1to1() -> void:
	var got: float = await _measure_tracking(DRAG_PX)
	if absf(got - DRAG_PX) > TOLERANCE_PX:
		_fail += 1
		print("FAIL: a %.0fpx move drag moved the object %.1fpx on screen, want %.0fpx (1:1)"
			% [DRAG_PX, got, DRAG_PX])

## The whole point of removing the constant: double the camera distance and the
## same cursor travel must still be 1:1. A different hardcoded gain would pass
## the first check and fail here.
func _test_move_tracks_cursor_when_zoomed_out() -> void:
	_lab.camera_controller._distance = 16.0
	_lab.camera_controller._update_camera()
	await get_tree().process_frame
	var got: float = await _measure_tracking(DRAG_PX)
	if absf(got - DRAG_PX) > TOLERANCE_PX:
		_fail += 1
		print("FAIL: at 2x camera distance a %.0fpx move drag moved %.1fpx, want %.0fpx (gain is not depth-aware)"
			% [DRAG_PX, got, DRAG_PX])

## Grabs the X handle, drags the cursor `px` along the axis' screen direction and
## returns how far the object's projection actually travelled along that
## direction.
func _measure_tracking(px: float) -> float:
	# The double-click guard runs before the gizmo-grab branch on every press; a
	# second press inside the 0.3s window would drill down and never arm a drag.
	_lab._last_click_time = 0.0

	var handle: Vector2 = _grab_screen()
	var dir: Vector2 = _axis_screen_dir()
	if not handle.is_finite() or dir.is_zero_approx():
		_fail += 1
		print("FAIL: could not locate the X move handle / its screen direction")
		_finish()
		return 0.0

	await _cursor_to(handle)
	_press(handle)
	if not _lab._dragging:
		_fail += 1
		print("FAIL: the press did not grab the X move handle (pick missed)")
		_finish()
		return 0.0

	var before: Vector2 = _cam.unproject_position(_cube.global_position)
	await _cursor_to(handle + dir * px)
	_motion(handle + dir * px)
	var after: Vector2 = _cam.unproject_position(_cube.global_position)
	_release(handle + dir * px)
	return (after - before).dot(dir)

## A screen point on the X handle shaft, found via the real pick ray so the test
## arms the drag exactly the way a player would.
func _grab_screen() -> Vector2:
	var handles := _lab.gizmo.get_node_or_null("Handles") as Node3D
	if handles == null:
		return Vector2.INF
	var s: float = handles.scale.x
	var axis_world: Vector3 = _lab.gizmo.axis_to_world(AXIS_LOCAL)
	var center: Vector3 = _lab.gizmo.global_position
	for f: float in [0.6, 0.5, 0.7, 0.4, 0.75]:
		var px: Vector2 = _cam.unproject_position(center + axis_world * (s * f))
		var r: Dictionary = _lab.gizmo.pick(px, _cam)
		var hit_axis: Vector3 = r.get("axis", Vector3.ZERO)
		if r.get("picked", false) and hit_axis.is_equal_approx(AXIS_LOCAL):
			return px
	return Vector2.INF

## The screen direction the grabbed axis runs in, straight from the projection -
## not from the lab's own basis, so the assertion stays independent of the fix.
func _axis_screen_dir() -> Vector2:
	var handles := _lab.gizmo.get_node_or_null("Handles") as Node3D
	if handles == null:
		return Vector2.ZERO
	var axis_world: Vector3 = _lab.gizmo.axis_to_world(AXIS_LOCAL)
	var center: Vector2 = _cam.unproject_position(_lab.gizmo.global_position)
	var tip: Vector2 = _cam.unproject_position(
		_lab.gizmo.global_position + axis_world * handles.scale.x)
	return (tip - center).normalized()

## Puts the handler's cursor (SubViewport space) at `sv_pos` by feeding the OS
## cursor through the inverse of the viewport's screen transform.
func _cursor_to(sv_pos: Vector2) -> void:
	var os_pos: Vector2 = _sv.get_screen_transform() * sv_pos
	var m := InputEventMouseMotion.new()
	m.position = os_pos
	m.global_position = os_pos
	Input.parse_input_event(m)
	await get_tree().process_frame

func _press(sv_pos: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = sv_pos
	_cont.emit_signal("gui_input", e)

func _motion(sv_pos: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = sv_pos
	_cont.emit_signal("gui_input", e)

func _release(sv_pos: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = false
	e.position = sv_pos
	_cont.emit_signal("gui_input", e)

func _finish() -> void:
	if _fail == 0:
		print("PASS: the move gizmo tracks the cursor 1:1 at the default and zoomed-out camera distances")
	get_tree().quit(1 if _fail else 0)

func _on_watchdog() -> void:
	get_tree().quit(2)
