extends Node

## CameraController test: transform set/move/rotate, zoom along the view
## axis with distance clamping, reset to the home framing, and measurable
## framing_ok (distance to scene center + frustum projection) which the
## scoring layer consumes for camera_score.
##
## Scene-harness test on purpose: set_zoom and framing_ok read the camera's
## GLOBAL transform, which requires the node to be inside a running tree.
## SceneTree-script _init runs before the tree starts, so nothing added there
## is inside the tree and global_transform returns identity.

const HOME_POS := Vector3(0, 0.8, 4)

func _ready() -> void:
	var tree := get_tree()
	var failures := await _run()
	if failures.is_empty():
		print("PASS: camera controller transform/zoom/reset/framing")
		tree.quit(0)
	else:
		for f in failures:
			print("FAIL: ", f)
		tree.quit(1)


func _run() -> Array[String]:
	var failures: Array[String] = []
	var stage := Node3D.new()
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	stage.add_child(cam)
	var ctrl := AnimationCameraController.new()
	stage.add_child(ctrl)
	ctrl.camera_path = NodePath("../Camera3D")
	add_child(stage)
	await get_tree().process_frame

	ctrl.set_transform(Vector3(1, 2, 3), Vector3(0, 30, 0))
	if cam.position != Vector3(1, 2, 3):
		failures.append("set_transform did not move the camera")
	if absf(cam.rotation_degrees.y - 30.0) > 0.01:
		failures.append("set_transform did not rotate the camera")

	ctrl.move_offset(Vector3(0, 0, -1))
	if cam.position != Vector3(1, 2, 2):
		failures.append("move_offset did not translate")

	ctrl.rotate_offset(Vector3(0, 10, 0))
	if absf(cam.rotation_degrees.y - 40.0) > 0.01:
		failures.append("rotate_offset did not rotate")

	# Zoom along the (rotated) view axis; reset to a clean orientation first.
	ctrl.set_transform(HOME_POS, Vector3.ZERO)
	ctrl.set_zoom(2.0)
	if absf(cam.position.z - (4.0 - 2.0)) > 0.01:
		failures.append("zoom did not move along -z by the factor")
	ctrl.set_zoom(1000.0)
	if absf(cam.position.length() - 12.0) > 0.01:
		failures.append("zoom did not clamp to max distance 12")
	# Min-distance clamp: creep toward the origin until inside the 0.5 ball.
	ctrl.set_transform(Vector3(0, 0, 0.4), Vector3.ZERO)
	ctrl.set_zoom(0.1)
	if absf(cam.position.length() - 0.5) > 0.01:
		failures.append("zoom did not clamp to min distance 0.5")

	ctrl.set_transform(Vector3(5, 5, 5), Vector3(0, 20, 10))
	ctrl.reset()
	if cam.position != HOME_POS:
		failures.append("reset did not restore home position")
	if cam.rotation_degrees != Vector3.ZERO:
		failures.append("reset did not restore home rotation")
	if absf(cam.fov - 60.0) > 0.01:
		failures.append("reset did not restore fov 60")

	# framing_ok: scene center reachable and all targets on stage.
	ctrl.set_transform(HOME_POS, Vector3.ZERO)
	var near_targets: Array[Vector3] = [Vector3(0, 1, 0), Vector3(1, 1, -1)]
	if not ctrl.framing_ok(Vector3.ZERO, near_targets, 6.0):
		failures.append("framing_ok rejected a well-framed shot")
	if ctrl.framing_ok(Vector3.ZERO, near_targets, 1.0):
		failures.append("framing_ok accepted a shot too far from center")
	var behind: Array[Vector3] = [Vector3(0, 0, 10)]
	if ctrl.framing_ok(Vector3.ZERO, behind, 20.0):
		failures.append("framing_ok accepted a target behind the camera")

	stage.free()
	return failures