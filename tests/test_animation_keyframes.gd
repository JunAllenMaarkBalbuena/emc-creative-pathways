extends SceneTree

## KeyframeController test: keyframe tracks with linear lerp (Vector3/float/
## Color), STEP hold semantics, before-first/after-last clamping, insertion
## sorting by time, per-target track queries, remove, and RF4 orphan-safety
## (evaluate for an unknown target OR a property with no track returns null,
## never an error; a dangling target id after an undo/delete is harmless).

func _init() -> void:
	var failures := _run()
	if failures.is_empty():
		print("PASS: keyframe add/remove/evaluate with linear & step interpolation, orphan-safe")
		quit(0)
	else:
		for f in failures:
			print("FAIL: ", f)
		quit(1)


func _run() -> Array[String]:
	var failures: Array[String] = []
	var ctrl := KeyframeController.new()

	ctrl.add_keyframe(0.0, "ball", KeyframeController.TARGET_OBJECT, "position", Vector3(0, 0, 0))
	ctrl.add_keyframe(1.0, "ball", KeyframeController.TARGET_OBJECT, "position", Vector3(4, 0, 0))
	var mid: Variant = ctrl.evaluate("ball", "position", 0.5)
	if not (mid is Vector3) or (mid as Vector3) != Vector3(2, 0, 0):
		failures.append("linear Vector3 lerp at t=0.5 should be (2,0,0), got %s" % str(mid))

	ctrl.add_keyframe(0.0, "cam", KeyframeController.TARGET_CAMERA, "fov", 40.0)
	ctrl.add_keyframe(2.0, "cam", KeyframeController.TARGET_CAMERA, "fov", 80.0)
	var fov: Variant = ctrl.evaluate("cam", "fov", 1.0)
	if not (fov is float) or absf(fov as float - 60.0) > 0.001:
		failures.append("linear float lerp at t=1.0 should be 60, got %s" % str(fov))

	ctrl.add_keyframe(0.0, "lamp", KeyframeController.TARGET_LIGHT, "light_color", Color(1, 0, 0))
	ctrl.add_keyframe(1.0, "lamp", KeyframeController.TARGET_LIGHT, "light_color", Color(0, 0, 1))
	var col: Variant = ctrl.evaluate("lamp", "light_color", 0.5)
	if not (col is Color) or absf((col as Color).r - 0.5) > 0.001 or absf((col as Color).b - 0.5) > 0.001:
		failures.append("linear Color lerp at t=0.5 should be (0.5,0,0.5), got %s" % str(col))

	# STEP: between keys, the BEFORE key's value applies.
	ctrl.add_keyframe(0.0, "door", KeyframeController.TARGET_OBJECT, "rotation_degrees", Vector3(0, 0, 0), KeyframeController.STEP)
	ctrl.add_keyframe(1.0, "door", KeyframeController.TARGET_OBJECT, "rotation_degrees", Vector3(0, 90, 0), KeyframeController.STEP)
	var stepped: Variant = ctrl.evaluate("door", "rotation_degrees", 0.5)
	if not (stepped is Vector3) or (stepped as Vector3) != Vector3(0, 0, 0):
		failures.append("STEP should give the before-key value, got %s" % str(stepped))

	# Clamping: before the first key -> first value; after the last -> last.
	var before: Variant = ctrl.evaluate("ball", "position", -5.0)
	if (before as Vector3) != Vector3(0, 0, 0):
		failures.append("before-first should clamp to the first value")
	var after: Variant = ctrl.evaluate("ball", "position", 99.0)
	if (after as Vector3) != Vector3(4, 0, 0):
		failures.append("after-last should clamp to the last value")

	ctrl.add_keyframe(2.0, "pulse", KeyframeController.TARGET_OBJECT, "scale", 1.0)
	ctrl.add_keyframe(1.0, "pulse", KeyframeController.TARGET_OBJECT, "scale", 0.5)
	# Keys added out of order stay sorted by time within their track.
	var pulse_times := ctrl.keyframe_times("pulse")
	if pulse_times.size() != 2 or pulse_times[0] != 1.0 or pulse_times[1] != 2.0:
		failures.append("keys added out of order must sort ascending in the pulse track")

	var kfs := ctrl.keyframes_for("ball")
	if kfs.size() != 2:
		failures.append("keyframes_for should return the ball track keys")
	var times := ctrl.keyframe_times("ball")
	if times.size() != 2 or times[0] != 0.0 or times[1] != 1.0:
		failures.append("keyframe_times should return [0.0, 1.0]")

	# RF4: unknown target -> null; known target, unknown property -> null.
	if ctrl.evaluate("ghost_id", "position", 1.0) != null:
		failures.append("evaluate for an unknown target must be null (orphan-safe)")
	if ctrl.evaluate("ball", "scale", 0.5) != null:
		failures.append("evaluate for a property with no track must be null")

	var before_size := ctrl.keyframes.size()
	if not ctrl.remove_keyframe(0):
		failures.append("remove_keyframe(0) failed")
	if ctrl.keyframes.size() != before_size - 1:
		failures.append("remove_keyframe did not shrink the list")
	if ctrl.remove_keyframe(-1) != false or ctrl.remove_keyframe(ctrl.keyframes.size()) != false:
		failures.append("remove_keyframe with an out-of-range index must be false")

	return failures