extends Node

## Regression test for the play report:
##
##   "bug when using the ViewOrbitGizmo the rotate gizmo stopped working, or
##    when looking straight to the object, and at other moments I can't use any
##    of the gizmos in the object"
##
## ONE root cause, two symptoms.
##
## `modeling_lab.gd::_compute_drag_screen_basis()` derives a handle's screen
## direction by unprojecting the gizmo centre and the centre displaced along the
## handle's world axis. When the axis is PARALLEL TO THE VIEW RAY both points
## project to the same pixel, the delta is (0, 0), and `.normalized()` returns
## (0, 0) — so `_drag_axis_screen` and `_drag_axis_perp` are both zero and every
## `moved.dot(...)` is exactly 0. The handle is grabbed, dragged, and does
## nothing.
##
## Reachable from ordinary play, which is why it read as intermittent: the
## ViewOrbitGizmo axis buttons call `CameraController.set_view_axis()`, which
## aligns the camera to the axis EXACTLY (measured dot product 1.000), and
## hand-orbiting reaches the same alignment. From the default tilted 3/4 view
## the same three axes project to 45-90px and behave normally.
##
## Scope: this covers the DEGENERATE BASIS, which is the reported defect. It is
## not a test of angular trackball tracking. The projected-axis formula has a
## genuine discontinuity within ~15deg of parallel — the direction of a
## foreshortened projection is undefined and flips sign — which no fallback can
## remove. Removing that would mean replacing the formula with true atan2 ring
## tracking, changing rotate feel at every angle. Deliberately not done here.

var _fail := 0
var _lab: ModelingLab

func _ready() -> void:
	var tree := get_tree()
	get_window().size = Vector2i(1280, 720)
	await tree.process_frame
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

	# Each sub-test awaits frames internally, so it MUST be awaited here.
	await _test_basis_is_valid_at_every_view_axis(cube, cam)
	await _test_object_actually_rotates_at_every_view_axis(cube, cam)
	await _test_object_actually_moves_at_every_view_axis(cube, cam)
	await _test_object_actually_scales_at_every_view_axis(cube, cam)

	if _fail == 0:
		print("PASS: handles stay draggable at every view angle")
	_finish()

## Every view the ViewOrbitGizmo can produce, plus the alignments hand-orbiting
## reaches between them.
const VIEWS: Array[Vector3] = [
	Vector3.UP, Vector3.DOWN, Vector3.RIGHT, Vector3.LEFT,
	Vector3.BACK, Vector3.FORWARD,
]

## 1) The reported defect, stated directly: neither basis vector may be zero.
func _test_basis_is_valid_at_every_view_axis(cube: MeshInstance3D, cam: Camera3D) -> void:
	for axis: Vector3 in VIEWS:
		await _with_view_axis(cube, cam, axis)
		for handle: Vector3 in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
			var b := _basis(handle)
			for i in [0, 1]:
				var v: Vector2 = b[i]
				if v.length() < 0.99:
					_fail += 1
					print("FAIL: viewing along %s, the %s handle basis[%d] is %s (length %.4f) - the axis is parallel to the view, so there is no screen direction"
						% [str(axis), str(handle), i, str(v), v.length()])

## 2) End-to-end through TransformManager: the object must end up rotated. The
##     basis being valid is necessary but not sufficient — this is the behaviour
##     the user reported as broken.
func _test_object_actually_rotates_at_every_view_axis(cube: MeshInstance3D, cam: Camera3D) -> void:
	for axis: Vector3 in VIEWS:
		await _with_view_axis(cube, cam, axis)
		for handle: Vector3 in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
			var node := _live()
			var before := node.basis.get_euler()
			var tm := _lab.transform_manager
			tm.begin_rotate(handle)
			var b := _basis(handle)
			tm.apply_rotate(handle, _drag_along(b[1], b[0]).dot(b[1]) * 0.004)
			var after := node.basis.get_euler()
			tm.end_rotate()
			await get_tree().process_frame
			if (after - before).length() < 0.001:
				_fail += 1
				print("FAIL: viewing along %s, dragging the %s rotate handle produced no rotation at all"
					% [str(axis), str(handle)])

## 3) "I can't use ANY of the gizmos" — move reads the same basis.
func _test_object_actually_moves_at_every_view_axis(cube: MeshInstance3D, cam: Camera3D) -> void:
	for axis: Vector3 in VIEWS:
		await _with_view_axis(cube, cam, axis)
		for handle: Vector3 in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
			var node := _live()
			var before := node.position
			var tm := _lab.transform_manager
			tm.begin_move(handle)
			var b := _basis(handle)
			tm.apply_move(handle, _drag_along(b[0], b[1]).dot(b[0]) * 0.02)
			var after := node.position
			tm.end_move()
			await get_tree().process_frame
			if after.distance_to(before) < 0.001:
				_fail += 1
				print("FAIL: viewing along %s, dragging the %s move handle moved the object 0.000 (%.3f px of travel)"
					% [str(axis), str(handle), _drag_along(b[0], b[1]).dot(b[0])])

## 4) Scale reads the same basis via _scale_delta().
func _test_object_actually_scales_at_every_view_axis(cube: MeshInstance3D, cam: Camera3D) -> void:
	for axis: Vector3 in VIEWS:
		await _with_view_axis(cube, cam, axis)
		for handle: Vector3 in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
			var node := _live()
			var before := node.scale
			var b := _basis(handle)
			var grab := _grab_pos(handle)
			var d := _lab._scale_delta(grab + _drag_along(b[0], b[1]), grab, b[0])
			var tm := _lab.transform_manager
			tm.begin_scale(false)
			tm.apply_scale(handle, d, false)
			var after := node.scale
			tm.end_scale()
			await get_tree().process_frame
			if after.distance_to(before) < 0.0001:
				_fail += 1
				print("FAIL: viewing along %s, dragging the %s scale handle produced no change (delta %.4f)"
					% [str(axis), str(handle), d])

# ── helpers ───────────────────────────────────────────────────────

## The drag must be mostly ALONG the axis being exercised. A drag directed
## along the ring's radius is legitimately inert — for a face-on ring the
## cursor is on the radius, not the tangent — and the scale snap needs ~33px
## before it registers at all, so a small radial component would read as "dead"
## for reasons that have nothing to do with the bug.
func _drag_along(axis: Vector2, other: Vector2) -> Vector2:
	return axis * 120.0 + other * 15.0

## end_move/end_scale/end_rotate all push an undo command, and the command
## layer re-points the selection at rebuilt node instances. A `cube` captured in
## _ready is therefore stale from the first sub-test onward — reads against it
## silently compare a detached node. Re-fetch every time.
func _live() -> MeshInstance3D:
	return _lab.selection_manager.get_selected()

## Point the camera down `axis` via the same call the ViewOrbitGizmo uses.
func _with_view_axis(cube: MeshInstance3D, cam: Camera3D, axis: Vector3) -> void:
	_lab.camera_controller.focus_on(cube.global_position)
	_lab.camera_controller.set_view_axis(axis)
	await get_tree().process_frame

## Runs the production `_compute_drag_screen_basis()` for `handle` and returns
## [_drag_axis_screen, _drag_axis_perp].
func _basis(handle: Vector3) -> Array[Vector2]:
	_lab._drag_axis = handle
	_lab._drag_uniform = false
	_lab._compute_drag_screen_basis(_grab_pos(handle))
	return [_lab._drag_axis_screen, _lab._drag_axis_perp]

## A plausible screen-space grab point for `handle`: on the handle itself when
## the axis projects, otherwise out on the ring at 45deg, where a user would
## click.
func _grab_pos(handle: Vector3) -> Vector2:
	var cam := _lab.camera_controller.camera
	var centre := _lab.gizmo.global_position
	var on_axis := cam.unproject_position(centre + handle)
	var projected := on_axis - cam.unproject_position(centre)
	if projected.length() > ModelingLab.AXIS_SCREEN_EPS:
		return on_axis
	var scale: float = (_lab.gizmo.get_node("Handles") as Node3D).scale.x
	var n: Vector3 = handle.normalized()
	var in_plane: Vector3 = (handle.cross(Vector3.UP) if absf(n.dot(Vector3.UP)) < 0.9 else Vector3.UP).normalized()
	var other: Vector3 = n.cross(in_plane).normalized()
	# Round to whole pixels: a hand cannot click a sub-pixel-perfect point.
	return cam.unproject_position(centre + (in_plane + other).normalized() * scale).round()

func _finish() -> void:
	get_tree().quit(1 if _fail > 0 else 0)

func _on_watchdog() -> void:
	print("FAIL: watchdog timeout")
	get_tree().quit(2)