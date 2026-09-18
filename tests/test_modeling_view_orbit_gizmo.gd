extends SceneTree

## Regression test: the ViewOrbitGizmo must reflect the live camera orientation.
## Its axis handles/spokes are projected through the camera's basis, so they
## rotate as the view spins (rather than the old fixed X/Y screen mapping).
## Behaviors verified here:
##   - without a camera set, fall back to the fixed screen mapping (unchanged)
##   - an axis pointing into/out of the screen collapses to center and is not
##     drawn or clickable (e.g. world FORWARD seen head-on)
##   - rotating the camera moves the handle positions
##   - hit-testing reports the axis you click, never a hidden axis

func _initialize() -> void:
	_run()

func _run() -> void:
	var fail := 0
	var g := ViewOrbitGizmo.new()
	root.add_child(g)
	await process_frame
	g.size = Vector2(200, 200)
	var center := g.size / 2.0
	var R: float = ViewOrbitGizmo.RADIUS + ViewOrbitGizmo.SPOKE_LENGTH

	# No camera: fixed mapping kept (X right, Y up), Z axes stay hidden.
	var p_x: Vector2 = g._axis_screen_pos(center, Vector3.RIGHT)
	if p_x.distance_to(center + Vector2(R, 0.0)) > 1.0:
		fail += 1
		print("FAIL: without a camera the X handle must sit at (center + right, radius)")
	var p_fwd: Vector2 = g._axis_screen_pos(center, Vector3.FORWARD)
	if p_fwd.distance_to(center) > 1.0:
		fail += 1
		print("FAIL: world -Z must collapse to center when it points into the screen")

	# Head-on camera at identity: world FORWARD still points into the screen.
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.global_transform = Transform3D(Basis(), Vector3(0, 0, 8))
	g.set_camera(cam)
	p_fwd = g._axis_screen_pos(center, Vector3.FORWARD)
	if p_fwd.distance_to(center) > 1.0:
		fail += 1
		print("FAIL: head-on FORWARD handle must collapse to center (hidden)")
	p_x = g._axis_screen_pos(center, Vector3.RIGHT)
	if p_x.distance_to(center + Vector2(R, 0.0)) > 1.0:
		fail += 1
		print("FAIL: head-on camera must keep the X handle at fixed radius")

	# Rotating the camera moves the handles (dynamic wheel).
	var p_y_0: Vector2 = g._axis_screen_pos(center, Vector3.UP)  # identity camera
	cam.global_transform = Transform3D(Basis.from_euler(Vector3(0.4, 0.0, 0.0)), Vector3(0, 0, 8))
	var p_y_1: Vector2 = g._axis_screen_pos(center, Vector3.UP)
	if p_y_0.distance_to(p_y_1) < 3.0:
		fail += 1
		print("FAIL: handle positions must move when the camera rotates (%.2f px)" % p_y_0.distance_to(p_y_1))

	# Tilted view: the world -Z handle lands between center and the rim.
	cam.global_transform = Transform3D(Basis.from_euler(Vector3(0.4, 0.0, 0.0)), Vector3(0, 0, 8))
	var p_back: Vector2 = g._axis_screen_pos(center, Vector3.BACK)
	if p_back.distance_to(center) < 3.0 or p_back.distance_to(center) > R - 3.0:
		fail += 1
		print("FAIL: tilted world +Z handle must sit between center and rim (r=%.1f)" % p_back.distance_to(center))

	# Hit test: clicking a visible handle returns that axis; clicking a hidden
	# axis (collapsed to center) must NOT return anything.
	cam.global_transform = Transform3D(Basis(), Vector3(0, 0, 8))
	var h: Vector2 = g._axis_screen_pos(center, Vector3.RIGHT)
	if g._axis_at(h) != Vector3.RIGHT:
		fail += 1
		print("FAIL: clicking the X handle must report axis X (got %s)" % g._axis_at(h))
	if g._axis_at(center) != Vector3.ZERO:
		fail += 1
		print("FAIL: clicking the collapsed (hidden) Z axis must not select an axis")

	if fail == 0:
		print("PASS: ViewOrbitGizmo tracks the live camera orientation and hit-tests correctly")
	quit(1 if fail > 0 else 0)