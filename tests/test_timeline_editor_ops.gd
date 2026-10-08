extends SceneTree

## KeyframeController editing primitives (Task 1, multi-track timeline round):
## move_key / remove_keys / slide_keys / duplicate_keys / set_all, plus the
## null-safe history + timeline injection. Every op keeps the flat list
## sorted, stays inside [0, timeline.duration], emits keyframes_changed once,
## and pushes EditorHistory only when one is wired (bare controllers stay
## untouched). set_all is the quiet loader path: emits once, pushes nothing,
## and undo after it leaves keyframes untouched (Review-Focus #2, controller
## half).

var _emits := 0


func _init() -> void:
	var failures := _run()
	if failures.is_empty():
		print("PASS: timeline editor ops — move/remove/slide/duplicate + history + quiet set_all")
		quit(0)
	else:
		for f in failures:
			print("FAIL: ", f)
		quit(1)


func _run() -> Array[String]:
	var failures: Array[String] = []

	# --- move_key ------------------------------------------------------------
	var wired := _make_wired()
	var ctrl := wired[0] as KeyframeController
	var history := wired[2] as EditorHistory
	ctrl.add_keyframe(0.0, "ball", KeyframeController.TARGET_OBJECT, "position", Vector3(0, 0, 0))
	ctrl.add_keyframe(1.0, "ball", KeyframeController.TARGET_OBJECT, "position", Vector3(4, 0, 0))
	ctrl.add_keyframe(2.0, "ball", KeyframeController.TARGET_OBJECT, "position", Vector3(8, 0, 0))
	_emits = 0
	ctrl.keyframes_changed.connect(_on_keyframes_changed)
	if not ctrl.move_key(2, 0.5):
		failures.append("move_key(2, 0.5) should succeed")
	if _times(ctrl) != [0.0, 0.5, 1.0]:
		failures.append("move_key should re-time and keep the list sorted, got %s" % [_times(ctrl)])
	if (ctrl.keyframes[1] as AnimationKeyframeData).value != Vector3(8, 0, 0):
		failures.append("move_key should move the key at the given index, not another")
	if _emits != 1:
		failures.append("move_key should emit keyframes_changed once")
	if not history.can_undo():
		failures.append("move_key should push an undo entry when history is wired")
	if not history.undo():
		failures.append("undo after move_key should succeed")
	elif _times(ctrl) != [0.0, 1.0, 2.0]:
		failures.append("undo should restore the pre-move times, got %s" % [_times(ctrl)])
	if not history.redo():
		failures.append("redo after undo-move should succeed")
	elif _times(ctrl) != [0.0, 0.5, 1.0]:
		failures.append("redo should re-apply the move, got %s" % [_times(ctrl)])
	_emits = 0
	if not ctrl.move_key(1, 9.0):
		failures.append("move_key(1, 9.0) should succeed")
	if _times(ctrl) != [0.0, 1.0, 5.0]:
		failures.append("move_key should clamp to the timeline duration, got %s" % [_times(ctrl)])
	if _emits != 1:
		failures.append("a clamped move_key should still emit")
	if not history.undo() or _times(ctrl) != [0.0, 0.5, 1.0]:
		failures.append("undo should restore the pre-clamped-move times")
	if ctrl.move_key(-1, 1.0) or ctrl.move_key(3, 1.0):
		failures.append("move_key with an invalid index must return false")

	# --- remove_keys ----------------------------------------------------------
	wired = _make_wired()
	ctrl = wired[0] as KeyframeController
	history = wired[2] as EditorHistory
	ctrl.add_keyframe(0.0, "ball", KeyframeController.TARGET_OBJECT, "position", Vector3(0, 0, 0))
	ctrl.add_keyframe(1.0, "ball", KeyframeController.TARGET_OBJECT, "position", Vector3(4, 0, 0))
	ctrl.add_keyframe(2.0, "ball", KeyframeController.TARGET_OBJECT, "position", Vector3(8, 0, 0))
	ctrl.add_keyframe(3.0, "ball", KeyframeController.TARGET_OBJECT, "position", Vector3(12, 0, 0))
	_emits = 0
	ctrl.keyframes_changed.connect(_on_keyframes_changed)
	if not ctrl.remove_keys([0, 2]):
		failures.append("remove_keys([0, 2]) should succeed")
	if ctrl.keyframes.size() != 2 or _times(ctrl) != [1.0, 3.0]:
		failures.append("remove_keys should drop both pre-call indices, got %s" % [_times(ctrl)])
	if _emits != 1:
		failures.append("remove_keys should emit keyframes_changed once")
	if not history.undo():
		failures.append("undo after remove_keys should succeed")
	elif _times(ctrl) != [0.0, 1.0, 2.0, 3.0]:
		failures.append("undo should restore the removed keys, got %s" % [_times(ctrl)])
	if not history.redo():
		failures.append("redo after undo-remove should succeed")
	elif _times(ctrl) != [1.0, 3.0]:
		failures.append("redo should re-remove, got %s" % [_times(ctrl)])
	if ctrl.remove_keys([]):
		failures.append("remove_keys([]) must return false")
	if ctrl.remove_keys([-1]) or ctrl.remove_keys([2]):
		failures.append("remove_keys with an invalid index must return false")
	if ctrl.remove_keys([0, 2]):
		failures.append("remove_keys must fail on any invalid index, with no partial removal")
	elif ctrl.keyframes.size() != 2:
		failures.append("a failed remove_keys must not partially remove")

	# --- slide_keys -----------------------------------------------------------
	wired = _make_wired()
	ctrl = wired[0] as KeyframeController
	history = wired[2] as EditorHistory
	ctrl.add_keyframe(1.0, "ball", KeyframeController.TARGET_OBJECT, "position", Vector3(0, 0, 0))
	ctrl.add_keyframe(2.0, "ball", KeyframeController.TARGET_OBJECT, "position", Vector3(4, 0, 0))
	ctrl.add_keyframe(3.0, "ball", KeyframeController.TARGET_OBJECT, "position", Vector3(8, 0, 0))
	_emits = 0
	ctrl.keyframes_changed.connect(_on_keyframes_changed)
	if not ctrl.slide_keys([0, 1], 1.0):
		failures.append("slide_keys([0, 1], 1.0) should succeed")
	if _times(ctrl) != [2.0, 3.0, 3.0]:
		failures.append("slide_keys should add the delta and pack colliding keys, got %s" % [_times(ctrl)])
	if _emits != 1:
		failures.append("slide_keys should emit keyframes_changed once")
	if not history.undo():
		failures.append("undo after slide_keys should succeed")
	elif _times(ctrl) != [1.0, 2.0, 3.0]:
		failures.append("undo should restore the pre-slide times, got %s" % [_times(ctrl)])
	if not history.redo():
		failures.append("redo should re-apply the slide")
	elif _times(ctrl) != [2.0, 3.0, 3.0]:
		failures.append("redo should re-apply the slide times, got %s" % [_times(ctrl)])
	if not ctrl.slide_keys([0], 9.0):
		failures.append("slide_keys([0], 9.0) should succeed")
	elif _times(ctrl) != [3.0, 3.0, 5.0]:
		failures.append("slide_keys should clamp at the duration, got %s" % [_times(ctrl)])
	if ctrl.slide_keys([], 0.5):
		failures.append("slide_keys([]) must return false")
	if ctrl.slide_keys([9], 0.5):
		failures.append("slide_keys with an invalid index must return false")

	# --- duplicate_keys -------------------------------------------------------
	wired = _make_wired()
	ctrl = wired[0] as KeyframeController
	history = wired[2] as EditorHistory
	ctrl.add_keyframe(0.0, "ball", KeyframeController.TARGET_OBJECT, "position", Vector3(0, 0, 0))
	ctrl.add_keyframe(1.0, "ball", KeyframeController.TARGET_OBJECT, "position", Vector3(4, 0, 0))
	ctrl.add_keyframe(2.0, "cam", KeyframeController.TARGET_CAMERA, "fov", 45.0)
	_emits = 0
	ctrl.keyframes_changed.connect(_on_keyframes_changed)
	# offset 0 duplicates in place (stacked).
	if not ctrl.duplicate_keys([0], 0.0):
		failures.append("duplicate_keys([0], 0.0) should succeed")
	if ctrl.keyframes.size() != 4 or _times(ctrl) != [0.0, 0.0, 1.0, 2.0]:
		failures.append("duplicate_keys with offset 0 should stack a copy in place, got %s" % [_times(ctrl)])
	if _emits != 1:
		failures.append("duplicate_keys should emit keyframes_changed once")
	if not history.undo():
		failures.append("undo after duplicate_keys should succeed")
	elif ctrl.keyframes.size() != 3 or _times(ctrl) != [0.0, 1.0, 2.0]:
		failures.append("undo should remove the duplicate, got %s" % [_times(ctrl)])
	if not history.redo():
		failures.append("redo after undo-duplicate should succeed")
	elif ctrl.keyframes.size() != 4 or _times(ctrl) != [0.0, 0.0, 1.0, 2.0]:
		failures.append("redo should re-add the duplicate, got %s" % [_times(ctrl)])
	# offset copies at time + offset (indices: 0=A, 1=A2, 2=B, 3=C).
	if not ctrl.duplicate_keys([2], 1.0):
		failures.append("duplicate_keys([2], 1.0) should succeed")
	if ctrl.keyframes.size() != 5 or _times(ctrl) != [0.0, 0.0, 1.0, 2.0, 2.0]:
		failures.append("duplicate_keys should copy at time + offset, got %s" % [_times(ctrl)])
	# A camera-lane key authored as "cam" duplicates with its id/type intact.
	if not ctrl.duplicate_keys([3], 0.5):
		failures.append("duplicate_keys of the camera key should succeed")
	var cam_copy := _find_at(ctrl, 2.5, "cam", "fov")
	if cam_copy == null:
		failures.append("duplicated camera key should land at time + offset with target_id \"cam\"")
	elif cam_copy.target_type != KeyframeController.TARGET_CAMERA or cam_copy.value != 45.0:
		failures.append("duplicated camera key should keep target_type and value")
	# A copy pushed past the duration clamps to it.
	if not ctrl.duplicate_keys([0], 99.0):
		failures.append("duplicate_keys([0], 99.0) should succeed")
	if _find_at(ctrl, 5.0, "ball", "position") == null:
		failures.append("a duplicate clamping past the duration should land at it")
	if ctrl.duplicate_keys([], 1.0):
		failures.append("duplicate_keys([]) must return false")
	if ctrl.duplicate_keys([99], 1.0):
		failures.append("duplicate_keys with an invalid index must return false")

	# --- set_all (quiet loader path, Review-Focus #2 controller half) ---------
	wired = _make_wired()
	ctrl = wired[0] as KeyframeController
	history = wired[2] as EditorHistory
	var built: Array[AnimationKeyframeData] = []
	var kf_a := AnimationKeyframeData.new()
	kf_a.time = 0.0
	kf_a.target_id = "ball"
	kf_a.target_type = KeyframeController.TARGET_OBJECT
	kf_a.property_path = "position"
	kf_a.value = Vector3(1, 1, 1)
	built.append(kf_a)
	var kf_b := AnimationKeyframeData.new()
	kf_b.time = 1.0
	kf_b.target_id = "cam"
	kf_b.target_type = KeyframeController.TARGET_CAMERA
	kf_b.property_path = "fov"
	kf_b.value = 60.0
	built.append(kf_b)
	_emits = 0
	ctrl.keyframes_changed.connect(_on_keyframes_changed)
	ctrl.set_all(built)
	if ctrl.keyframes.size() != 2 or _times(ctrl) != [0.0, 1.0]:
		failures.append("set_all should replace the keyframe list, got %s" % [_times(ctrl)])
	if _emits != 1:
		failures.append("set_all should emit keyframes_changed exactly once")
	if history.can_undo():
		failures.append("set_all must push no history entry")
	if history.undo():
		failures.append("undo after set_all must return false")
	if ctrl.keyframes.size() != 2:
		failures.append("undo after set_all must leave the loaded keys untouched")
	if (ctrl.keyframes[0] as AnimationKeyframeData).value != Vector3(1, 1, 1):
		failures.append("set_all should keep the assigned key values")

	# --- bare controller (no history / timeline) push nothing -----------------
	var bare := KeyframeController.new()
	bare.add_keyframe(0.0, "ball", KeyframeController.TARGET_OBJECT, "position", Vector3(0, 0, 0))
	bare.add_keyframe(1.0, "ball", KeyframeController.TARGET_OBJECT, "position", Vector3(4, 0, 0))
	if not bare.move_key(0, -3.0):
		failures.append("bare move_key should succeed without history/timeline")
	if _times(bare) != [0.0, 1.0]:
		failures.append("bare move_key should floor at 0, got %s" % [_times(bare)])
	if not bare.remove_keys([0]):
		failures.append("bare remove_keys should succeed without history")
	if not bare.slide_keys([0], 0.5) or _times(bare) != [1.5]:
		failures.append("bare slide_keys should succeed without history")
	if not bare.duplicate_keys([0], 0.0) or bare.keyframes.size() != 2:
		failures.append("bare duplicate_keys should succeed without history")

	return failures


func _make_wired() -> Array:
	var timeline := TimelineController.new()
	timeline.fps = 12
	timeline.duration = 5.0
	var history := EditorHistory.new()
	var ctrl := KeyframeController.new()
	ctrl.timeline = timeline
	ctrl.history = history
	return [ctrl, timeline, history]


func _times(ctrl: KeyframeController) -> Array[float]:
	var out: Array[float] = []
	for kf in ctrl.keyframes:
		out.append(kf.time)
	return out


func _find_at(ctrl: KeyframeController, time: float, target_id: String, property_path: String) -> AnimationKeyframeData:
	for kf in ctrl.keyframes:
		if kf.time == time and kf.target_id == target_id and kf.property_path == property_path:
			return kf
	return null


func _on_keyframes_changed() -> void:
	_emits += 1