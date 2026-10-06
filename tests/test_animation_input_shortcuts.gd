extends Node

## Task 17: keyboard shortcuts drive the timeline. Space toggles play/pause,
## Right/Left step one frame, Escape exits the lab. The escape path calls
## SceneTransition (an autoload that fades for 0.35 s before swapping the
## scene); this harness checks the lab_closed signal and quits before the
## fade can complete — the plan's "check the signal, not the transition".

const LAB := "res://scenes/animation_production_lab/animation_production_lab.tscn"

var _failures: Array[String] = []
var _escape_count := 0


func _ready() -> void:
	var tree := get_tree()
	_failures = await _run()
	if _failures.is_empty():
		print("PASS: keyboard shortcuts drive the timeline")
		tree.quit(0)
	else:
		for f in _failures:
			print("FAIL: ", f)
		tree.quit(1)


func _run() -> Array[String]:
	var failures: Array[String] = []
	var lab := load(LAB).instantiate() as AnimationProductionLab
	add_child(lab)
	await get_tree().process_frame

	# Space toggles playback.
	_push_key(KEY_SPACE, lab)
	if not lab.timeline.is_playing():
		failures.append("Space should start playback")
	_push_key(KEY_SPACE, lab)
	if lab.timeline.is_playing():
		failures.append("Space should pause playback")

	# Right steps one frame while paused.
	lab.timeline.current_time = 0.0
	var step := 1.0 / float(lab.timeline.fps)
	_push_key(KEY_RIGHT, lab)
	if not is_equal_approx(lab.timeline.current_time, step):
		failures.append("Right should step one frame (%s), got %s" % [step, lab.timeline.current_time])

	# Escape emits lab_closed exactly once; the SceneTransition fade never runs.
	lab.lab_closed.connect(_on_lab_closed)
	_push_key(KEY_ESCAPE, lab)
	await get_tree().process_frame
	if _escape_count != 1:
		failures.append("Escape should emit lab_closed once, got %d" % _escape_count)

	lab.queue_free()
	await get_tree().process_frame
	return failures


func _push_key(keycode: Key, lab: AnimationProductionLab) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.pressed = true
	lab._unhandled_input(ev)


func _on_lab_closed() -> void:
	_escape_count += 1