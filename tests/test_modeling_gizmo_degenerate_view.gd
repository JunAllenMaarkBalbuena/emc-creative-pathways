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
## Scope: this covers the DEGENERATE BASIS and the ROTATE DIRECTION, which were
## two separate defects (the second is section 5g of the audit). It is not a test
## of angular trackball tracking: the tangent is still a first-order projection
## onto a fixed screen direction, so a sufficiently large single-event drag can
## outrun it and turn a fraction of the drag backwards. Measured envelope ~7% at
## 20px; the tolerance below is set from that, and an actual inversion is -100%.
## Replacing the model with true `atan2` ring tracking would remove the
## first-order error but changes rotate feel at every angle — a separate decision,
## not made here.

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
	await _test_rotate_never_reverses(cube, cam)
	await _test_object_actually_rotates_at_every_view_axis(cube, cam)
	await _test_object_actually_moves_at_every_view_axis(cube, cam)
	await _test_object_actually_scales_at_every_view_axis(cube, cam)

	if _fail == 0:
		print("PASS: handles stay draggable at every view angle")
	_finish()

## The rotate direction must never invert. From a second play report: *"in
## certain angle or at the focus in positive x y z the rotation is reverse in
## negative it rotates fine"*.
##
## Stated as an invariant rather than a sign convention, so it cannot be
## satisfied by guessing the convention backwards: the material point the cursor
## grabbed must FOLLOW the cursor. Invert the rotation and it moves AGAINST the
## drag instead.
##
## The point is the one the game's OWN raycast struck (`gizmo.pick()` in ROTATE
## mode), and it is rotated analytically by whatever phi the production basis
## produces. Two reasons that is the right reference:
##
##   - it is what the user actually grabbed. An earlier version of this test
##     placed the point at an arbitrary angle t on the idealised centreline ring,
##     which is WRONG when the ring is edge-on: both halves project to the same
##     pixels, so the user necessarily grabs whichever half is in front. Grading
##     against an arbitrary half fails a correct implementation. That mistake
##     reported 157 spurious failures on correct code.
##   - it shares no code with the tangent computation under test.
##
## Tolerance. `phi = drag . perp * 0.004`, so a 20px drag is ~0.08rad, and the
## tangent is only the FIRST-order term. The point does not travel along the
## tangent but along the exact chord of the projected ellipse, which on a
## foreshortened ring sits a few percent behind it — the deviation grows with phi
## and with how flat the projection is. Measured worst case across 1728
## view/handle/angle/drag combinations: 7% of the drag.
##
## So 10% is the measured envelope plus headroom, and is still nowhere near
## hiding the defect being tested: an inverted rotation moves the grabbed point
## -100% of the drag (measured -100 to -5293px on the old code, i.e. many times
## the drag length). The two regimes do not overlap.
const RING_DRAG_PX := 20.0
const RING_REVERSE_TOL := 0.10

func _test_rotate_never_reverses(cube: MeshInstance3D, cam: Camera3D) -> void:
	var views: Array[Vector3] = [
		# The six ViewOrbitGizmo axis buttons. The +X/+Y/+Z ones are the
		# reported failure: each puts the camera on the POSITIVE side of that
		# axis, so the ring faces the user and used to invert.
		Vector3.UP, Vector3.DOWN, Vector3.RIGHT, Vector3.LEFT,
		Vector3.BACK, Vector3.FORWARD,
		# Plus generic oblique views, for "in certain angle".
		Vector3(0.577, 0.577, 0.577), Vector3(0.3, -0.8, 0.5),
	]
	var handles: Array[Vector3] = [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	var drags: Array[Vector2] = [
		Vector2(RING_DRAG_PX, 0), Vector2(-RING_DRAG_PX, 0),
		Vector2(0, RING_DRAG_PX), Vector2(0, -RING_DRAG_PX),
		Vector2(14, 14), Vector2(-14, 14),
	]

	_lab.gizmo.set_mode(Gizmo3D.Mode.ROTATE)
	await _lab.get_tree().process_frame

	for view: Vector3 in views:
		await _with_view_axis(cube, cam, view)
		for handle: Vector3 in handles:
			# Sweep the cursor right around the ring: the failure is angular, so a
			# few sample points would miss it.
			for k: int in 12:
				var t: float = TAU * float(k) / 12.0
				var n := handle.normalized()
				var seed := Vector3.UP if absf(n.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
				var u := seed.cross(n).normalized()
				var v := n.cross(u).normalized()
				var centre := _lab.gizmo.global_position
				# RING_RADIUS from gizmo_3d.gd: TorusMesh(inner 0.85, outer 1.0)
				# puts the tube centreline at 0.925, scaled by the Handles root.
				var r: float = 0.925 * (_lab.gizmo.get_node("Handles") as Node3D).scale.x
				var screen := cam.unproject_position(
					centre + r * (u * cos(t) + v * sin(t)))

				var pick: Dictionary = _lab.gizmo.pick(screen, cam)
				if not pick.get("picked", false):
					continue  # cursor landed off the ring; nothing to assert
				var hit: Vector3 = pick["position"]
				var before := cam.unproject_position(hit)

				_lab._drag_axis = handle
				_lab._drag_uniform = false
				_lab._compute_drag_screen_basis(screen, hit)

				for d: Vector2 in drags:
					var phi: float = d.dot(_lab._drag_axis_perp) * 0.004
					var after3d := centre + Basis(handle.normalized(), phi) * (hit - centre)
					var follow: float = (cam.unproject_position(after3d) - before).dot(d)
					if follow < -RING_DRAG_PX * RING_REVERSE_TOL:
						_fail += 1
						print("FAIL: rotate is REVERSED - viewing along %s, dragging the %s ring at %.0fdeg by %s moved the grabbed point %.1fpx AGAINST the cursor"
							% [str(view), str(handle), rad_to_deg(t), str(d), follow])

	# Restore whatever tool the other sub-tests expect.
	_lab.gizmo.set_mode(Gizmo3D.Mode.TRANSLATE)

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