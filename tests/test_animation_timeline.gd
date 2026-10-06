extends SceneTree

## TimelineController test: pure-clock step_time (no engine frames), play/stop
## with end-of-timeline rollover and loop wrap, frame-index mapping from the
## FrameController frame channel at fps boundaries, and RF3 input validation
## (set_fps rejects out-of-range; set_duration rejects negatives and anything
## above max_duration, clamping exactly 0.0 to 0.01).

func _init() -> void:
	var failures := _run()
	if failures.is_empty():
		print("PASS: timeline clock, fps/duration validation, frame channel at fps boundaries")
		quit(0)
	else:
		for f in failures:
			print("FAIL: ", f)
		quit(1)


func _run() -> Array[String]:
	var failures: Array[String] = []
	var frames := FrameController.new()
	for i in 3:
		frames.add_frame()
	var ctrl := TimelineController.new()
	ctrl.frame_controller_ref = frames

	if not ctrl.set_fps(12):
		failures.append("set_fps(12) rejected")
	if not ctrl.set_duration(5.0):
		failures.append("set_duration(5.0) rejected")

	# Determinism: pure calls advance the clock without any engine frames.
	ctrl.play()
	ctrl.step_time(0.5)
	ctrl.step_time(0.5)
	if absf(ctrl.current_time - 1.0) > 0.0001:
		failures.append("step_time was not deterministic (expected 1.0)")

	# Play/stop: stop resets the clock.
	ctrl.stop()
	if ctrl.is_playing():
		failures.append("stop() left the timeline playing")
	if absf(ctrl.current_time) > 0.0001:
		failures.append("stop() did not reset current_time to 0")

	# End of timeline: step past the duration stops playback at the end.
	ctrl.play()
	ctrl.step_time(5.0)
	if ctrl.is_playing():
		failures.append("playback should stop at the end of the timeline")
	if absf(ctrl.current_time - 5.0) > 0.0001:
		failures.append("current_time did not clamp to duration at the end")

	# Loop: wraps to the remainder and keeps playing.
	ctrl.loop = true
	ctrl.play()
	ctrl.step_time(6.0)
	if not ctrl.is_playing():
		failures.append("looped timeline should keep playing after wrap")
	if absf(ctrl.current_time - 1.0) > 0.0001:
		failures.append("looped timeline did not wrap to 1.0")
	ctrl.loop = false
	ctrl.stop()

	# Frame channel at fps boundaries: 3 frames at 12fps -> last frame 2.
	if ctrl.frame_index_at(0.0) != 0:
		failures.append("frame_index_at(0.0) should be 0")
	if ctrl.frame_index_at(0.5) != 2:
		failures.append("frame_index_at(0.5) should clamp to the last index 2")
	ctrl.current_time = 0.3
	if ctrl.current_frame_index() != 2:
		failures.append("current_frame_index at 0.3s should clamp to 2")
	if absf(ctrl.current_frame_progress() - 0.6) > 0.01:
		failures.append("current_frame_progress at 0.3s should be ~0.6")

	# RF3: fps/duration validation.
	if ctrl.set_fps(0) != false or ctrl.fps != 12:
		failures.append("set_fps(0) must be rejected without changing fps")
	if ctrl.set_fps(13) != true or ctrl.fps != 13:
		failures.append("set_fps(13) must be accepted")
	if ctrl.set_fps(61) != false:
		failures.append("set_fps(61) must be rejected")
	if ctrl.set_duration(-1) != false or absf(ctrl.duration - 5.0) > 0.0001:
		failures.append("set_duration(-1) must be rejected without changing duration")
	if ctrl.set_duration(0.0) != true or absf(ctrl.duration - 0.01) > 0.0001:
		failures.append("set_duration(0.0) must be accepted and clamped to 0.01")
	if ctrl.set_duration(31.0) != false:
		failures.append("set_duration(31.0) must be rejected (above max_duration)")

	# frame_index_at never exceeds frames.size() - 1, even for huge times.
	if ctrl.frame_index_at(1e9) != 2:
		failures.append("frame_index_at must clamp for huge times")
	return failures