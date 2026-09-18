extends SceneTree

## Regression test: the modeling camera must orbit freely in all directions
## (full 360-degree sphere), driven by CameraController.orbit_by, which both
## the ViewOrbitGizmo and the middle-mouse drag route through. The previous
## Euler-angle implementation clamped elevation to +/-1.4 rad (~80deg), so the
## camera could never swing over the top/bottom. The quaternion version must:
##   - keep the default view (slightly below the pivot, ~8 units away)
##   - orbit a full horizontal circle without clamping (returns to start)
##   - swing over the pole (elevation beyond +/-1.4 rad) cleanly, no gimbal
##     flip, no NaN, orthonormal basis throughout
##   - set_view_axis() snap to -X/-Y/-Z views and reset_view() restore default

func _initialize() -> void:
	_run()

func _run() -> void:
	var fail := 0
	var cc := CameraController.new()
	root.add_child(cc)
	await process_frame
	var cam: Camera3D = cc.camera
	if cam == null or not is_instance_valid(cam):
		print("FAIL: CameraController has no camera")
		quit(1)
		return

	# --- Default view: slightly below pivot, default distance, looking at pivot
	var fwd := -cam.global_transform.basis.z
	if cam.global_position.distance_to(cc.get_pivot()) > cc.default_distance + 0.01:
		fail += 1
		print("FAIL: default camera distance %.2f != default %.2f" % [cam.global_position.distance_to(cc.get_pivot()), cc.default_distance])
	if not (fwd.y > 0.2 and fwd.z < -0.8):
		fail += 1
		print("FAIL: default view orientation unexpected fwd=%s" % fwd)

	# --- Full horizontal circle returns to the starting view (no yaw clamp)
	for i in 20:
		cc.orbit_by(Vector2(-TAU / cc.orbit_speed / 20.0, 0.0))
	var fwd_circle := -cam.global_transform.basis.z
	if fwd.distance_to(fwd_circle) > 0.005:
		fail += 1
		print("FAIL: 360deg horizontal orbit did not return to start (%.4f)" % fwd.distance_to(fwd_circle))
	if abs(cam.global_position.y - cc.get_pivot().y) > 4.0:
		fail += 1
		print("FAIL: horizontal orbit changed camera elevation; not a pure yaw")

	# --- Vertical sweep must cross BOTH poles, exceeding the old +/-1.4 clamp
	cc.reset_view()
	fwd = -cam.global_transform.basis.z
	# --- One long sweep in a single direction must cross BOTH poles (the camera
	# flips over the top and keeps orbiting), exceeding the old +/-1.4 rad
	# clamp. sin(1.4) = 0.985, so reaching 0.995 proves we surpass the old
	# limit, and reaching -0.995 proves we circled all the way over.
	cc.reset_view()
	fwd = -cam.global_transform.basis.z
	var max_fwd_y := fwd.y
	var min_fwd_y := fwd.y
	var cycles := 0
	var prev_side := fwd.y > 0.0
	for i in 120:
		cc.orbit_by(Vector2(0.0, -10.0))  # +0.05 rad elevation per call
		fwd = -cam.global_transform.basis.z
		var side := fwd.y > 0.0
		if side != prev_side:
			cycles += 1
			prev_side = side
		max_fwd_y = maxf(max_fwd_y, fwd.y)
		min_fwd_y = minf(min_fwd_y, fwd.y)
	if max_fwd_y <= 0.995:
		fail += 1
		print("FAIL: camera never crossed the pole below the pivot (max fwd.y=%.3f, old clamp caps at 0.985)" % max_fwd_y)
	if min_fwd_y >= -0.995:
		fail += 1
		print("FAIL: camera never crossed the pole above the pivot (min fwd.y=%.3f, old clamp caps at -0.985)" % min_fwd_y)
	if cycles < 2:
		fail += 1
		print("FAIL: camera never finished a full over-the-top cycle (side changes=%d)" % cycles)
	if not cam.global_transform.basis.is_finite():
		fail += 1
		print("FAIL: camera basis became NaN during free orbit")
	if not cam.global_transform.basis.is_orthonormal():
		fail += 1
		print("FAIL: camera basis not orthonormal after free orbit")

	# --- set_view_axis snap views + reset
	for axis in [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.FORWARD, Vector3.BACK]:
		cc.set_view_axis(axis)
		fwd = -cam.global_transform.basis.z
		var expected: Vector3 = -axis.normalized()
		if fwd.distance_to(expected) > 0.02:
			fail += 1
			print("FAIL: set_view_axis(%s) forward=%.3f expected=%.3f" % [axis, fwd, expected])
	cc.reset_view()
	fwd = -cam.global_transform.basis.z
	if cam.global_position.distance_to(cc.get_pivot()) > cc.default_distance + 0.01:
		fail += 1
		print("FAIL: reset_view did not restore default distance")
	if not (fwd.y > 0.2 and fwd.z < -0.8):
		fail += 1
		print("FAIL: reset_view did not restore default orientation")

	if fail == 0:
		print("PASS: camera orbits freely in all directions (no elevation clamp, no gimbal flip)")
	quit(1 if fail > 0 else 0)