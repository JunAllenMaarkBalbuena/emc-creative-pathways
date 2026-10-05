extends Node

## Regression test for the modeling-lab rotate report:
##
##   "the rotate gizmo does not respond and when rotating the object reset
##    when using the one in the panel setting additionally when rotating the
##    object snap randomly back or when moving a rotation is reset."
##
## Three distinct causes, all exercised against the real scene - no source-text
## matching, no mocks, no timing dependence.
##
## 1. apply_rotate() accumulated the angle it was handed, but modeling_lab.gd
##    hands it an angle already measured from the grab point:
##    `(mouse_pos - _drag_start_mouse).dot(perp) * SENSITIVITY`. Accumulating an
##    absolute re-adds the whole gesture once per motion event, so rotation
##    accelerated (40px of drag produced 22.9deg instead of 9.2deg) and dragging
##    the cursor BACK toward the grab point still rotated forward - 40px to 20px
##    went 22.9deg to 27.5deg. It only reversed once the cursor crossed back
##    past the grab point. That is "harder to control", "it moves more than I
##    move it", and "if I try to move it back it continues moving forward".
##
##    Rotation snap compounded it: a 15deg step is a dead band of 7.5deg in each
##    direction, so small corrections stalled and then jumped. It is now off by
##    default (SnapSettings.rotation_snap_enabled).
##
## 2. _on_inspector_rot_changed() rebuilds the basis with Basis.from_euler(...)
##    and drops scale entirely. Rotating a scaled object in the inspector resets
##    it to unit size - "when rotating the object reset when using the one in
##    the panel setting".
##
## 3. Both inspector handlers rebuilt the basis with `Basis.scaled()`, which
##    PRE-multiplies (`S * basis`). Against a basis that already carries scale
##    the row lengths multiply instead of being replaced, so the untouched axes
##    were corrupted as well - a (2,3,4) cube set to X=5 came out (10,9,16).
##    The rotate handler also discarded scale entirely.
##
## Note on the third reported symptom, "moving resets a rotation": a move does
## NOT reset rotation - that part of the report did not reproduce. `apply_move`
## touches only `.position`. What actually felt like rotation resetting was
## the snap dead-zone (cause 1) plus the corrupting inspector scale (cause 3):
## the object's orientation did not change, but its basis was being silently
## mangled by the same handlers. That is asserted below as scale+rotation
## surviving a move, which is the observable behaviour the user described.

var _fail := 0
var _lab: ModelingLab

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

	var cube: MeshInstance3D = _lab.selection_manager.get_selected()
	var cam: Camera3D = _lab.camera_controller.camera
	if cube == null or cam == null:
		_fail += 1
		print("FAIL: could not obtain a selected cube / camera to test against")
		_finish()
		return

	# Each sub-test awaits frames internally, so it MUST be awaited here. Without
	# `await` these become concurrent coroutines: _ready marches on while one is
	# still suspended, and the next sub-test overwrites the shared `cube` state
	# underneath it. That produced a convincing phantom "the scale command is
	# reverted a frame later" failure which does not exist in the product.
	await _test_rotation_responds_to_short_drag(cube)
	await _test_rotation_tracks_one_to_one(cube)
	await _test_rotation_reverses(cube)
	await _test_inspector_rotate_preserves_scale(cube)
	await _test_inspector_scale_replaces_not_compounds(cube)
	await _test_move_does_not_reset_rotation(cube)

	_finish()

## 1a) The snap must be applied to the TOTAL drag angle, not to each frame's
##     increment. With 15deg snap and the old per-frame rounding, a short drag
##     rounded to 0 and the object did not move at all - the gizmo read as
##     dead. A 40px drag at 0.004 rad/px is ~9.2deg of total, which is inside
##     the first detent and must therefore produce real (non-zero) rotation.
func _test_rotation_responds_to_short_drag(cube: MeshInstance3D) -> void:
	_lab.transform_manager.begin_rotate(Vector3.UP)
	var start_deg: float = rad_to_deg(cube.basis.get_euler().y)

	_lab.transform_manager.apply_rotate(Vector3.UP, 0.004 * 40.0)

	var got_deg: float = rad_to_deg(cube.basis.get_euler().y)
	if absf(got_deg - start_deg) < 0.5:
		_fail += 1
		print("FAIL: a 40px rotate drag produced no rotation (%.3f -> %.3f deg) - gizmo reads as dead"
			% [start_deg, got_deg])

	_lab.transform_manager.end_rotate()
	await get_tree().process_frame

## 1b) The value is an ABSOLUTE offset from the grab point, so the mapping must
##     be 1:1 and reversible. These sub-tests drive the exact feed shape
##     modeling_lab.gd produces (`(mouse_pos - _drag_start_mouse) * SENSITIVITY`),
##     i.e. a growing-then-shrinking sequence of absolute offsets - NOT a
##     repeated increment.
##
##     An earlier version of this file fed one increment twice and asserted the
##     rotation doubled. That is not what the handler sends, and asserting it
##     enshrined a bug: apply_rotate() accumulated an already-absolute value, so
##     rotation accelerated and dragging BACK kept rotating forward.
func _test_rotation_tracks_one_to_one(cube: MeshInstance3D) -> void:
	_lab.snap_settings.snap_enabled = false

	_lab.transform_manager.begin_rotate(Vector3.UP)
	var start_deg: float = rad_to_deg(cube.basis.get_euler().y)

	var want_deg: float = rad_to_deg(0.004 * 40.0)
	for px: float in [10.0, 20.0, 30.0, 40.0]:
		_lab.transform_manager.apply_rotate(Vector3.UP, 0.004 * px)
	var got_deg: float = rad_to_deg(cube.basis.get_euler().y) - start_deg

	if absf(got_deg - want_deg) > 0.15:
		_fail += 1
		print("FAIL: 40px of drag should rotate %.3f deg (1:1), got %.3f deg"
			% [want_deg, got_deg])

	_lab.transform_manager.end_rotate()
	await get_tree().process_frame

## 1c) "If I try to move it back it continues moving forward." Dragging the
##     cursor back toward (and past) the grab point must rotate backwards by the
##     same amount, and return to the start angle exactly at the grab point.
func _test_rotation_reverses(cube: MeshInstance3D) -> void:
	_lab.snap_settings.snap_enabled = false

	_lab.transform_manager.begin_rotate(Vector3.UP)
	var start_deg: float = rad_to_deg(cube.basis.get_euler().y)

	for px: float in [10.0, 20.0, 30.0, 40.0]:
		_lab.transform_manager.apply_rotate(Vector3.UP, 0.004 * px)
	var at_40: float = rad_to_deg(cube.basis.get_euler().y) - start_deg

	for px: float in [30.0, 20.0, 10.0]:
		_lab.transform_manager.apply_rotate(Vector3.UP, 0.004 * px)
	var at_10: float = rad_to_deg(cube.basis.get_euler().y) - start_deg

	if at_10 >= at_40:
		_fail += 1
		print("FAIL: dragging 40px -> 10px kept rotating forward (%.3f -> %.3f deg)"
			% [at_40, at_10])

	_lab.transform_manager.apply_rotate(Vector3.UP, 0.0)
	var back_at_grab: float = rad_to_deg(cube.basis.get_euler().y) - start_deg
	if absf(back_at_grab) > 0.15:
		_fail += 1
		print("FAIL: returning the cursor to the grab point must restore the start angle, got %.3f deg"
			% back_at_grab)

	_lab.transform_manager.end_rotate()
	await get_tree().process_frame
	_lab.snap_settings.snap_enabled = true

## 2) Inspector rotation must not reset scale.
func _test_inspector_rotate_preserves_scale(cube: MeshInstance3D) -> void:
	cube.scale = Vector3(2.0, 3.0, 4.0)
	var before_scale: Vector3 = cube.scale

	_lab._on_inspector_rot_changed(45.0, "y")

	var after_scale: Vector3 = cube.scale
	if not after_scale.is_equal_approx(before_scale):
		_fail += 1
		print("FAIL: inspector rotate reset scale %s -> %s" % [before_scale, after_scale])

## Found while fixing the rotate scale loss: the sibling scale handler had the
## same `Basis.scaled()` pre-multiply flaw. Setting X to 5 on a (2,3,4) object
## gave (10,9,16) - the untouched axes were corrupted too, and a second edit
## squared them. It must REPLACE the scale, not multiply it.
func _test_inspector_scale_replaces_not_compounds(cube: MeshInstance3D) -> void:
	cube.scale = Vector3(2.0, 3.0, 4.0)
	await get_tree().process_frame

	_lab._on_inspector_scale_changed(5.0, "x")
	await get_tree().process_frame
	if not cube.scale.is_equal_approx(Vector3(5.0, 3.0, 4.0)):
		_fail += 1
		print("FAIL: inspector scale compounded instead of replacing, got %s want (5.0, 3.0, 4.0)" % cube.scale)

	# A repeat must still land on the same absolute value, not square it.
	_lab._on_inspector_scale_changed(2.0, "x")
	await get_tree().process_frame
	if not cube.scale.is_equal_approx(Vector3(2.0, 3.0, 4.0)):
		_fail += 1
		print("FAIL: repeated inspector scale compounded, got %s want (2.0, 3.0, 4.0)" % cube.scale)

## 3) A move after a rotation must keep both the orientation and the scale.
func _test_move_does_not_reset_rotation(cube: MeshInstance3D) -> void:
	cube.scale = Vector3(2.0, 3.0, 4.0)
	_lab.transform_manager.begin_rotate(Vector3.UP)
	_lab.transform_manager.apply_rotate(Vector3.UP, deg_to_rad(30.0))
	_lab.transform_manager.end_rotate()
	await get_tree().process_frame

	var rotated_deg: float = rad_to_deg(cube.basis.get_euler().y)
	var rotated_scale: Vector3 = cube.scale

	_lab.transform_manager.begin_move(Vector3.RIGHT)
	_lab.transform_manager.apply_move(Vector3.RIGHT, 1.0)
	_lab.transform_manager.end_move()
	await get_tree().process_frame

	var after_move_deg: float = rad_to_deg(cube.basis.get_euler().y)
	if absf(after_move_deg - rotated_deg) > 0.5:
		_fail += 1
		print("FAIL: move changed rotation %.3f -> %.3f deg" % [rotated_deg, after_move_deg])

	if not cube.scale.is_equal_approx(rotated_scale):
		_fail += 1
		print("FAIL: move changed scale %s -> %s" % [rotated_scale, cube.scale])

func _finish() -> void:
	if _fail == 0:
		print("PASS: rotate responds and accumulates, inspector rotate keeps scale, inspector scale replaces, move keeps rotation and scale")
	get_tree().quit(1 if _fail else 0)

func _on_watchdog() -> void:
	get_tree().quit(2)