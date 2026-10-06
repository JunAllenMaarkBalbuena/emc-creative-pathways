extends SceneTree

## FrameController test: the frame list is the timeline's frame channel
## (Texture2D swaps at a per-frame duration). Add/duplicate/reorder/remove
## with an invariant: a timeline always has at least one frame, so removing
## the last remaining frame returns false and leaves size 1. Durations clamp
## to >= 0.01; frame_index stays contiguous after every mutation.

const TEX_PATH := "res://assets/Scene_BG/Menu_Bg_image.png"

func _init() -> void:
	var failures := _run()
	if failures.is_empty():
		print("PASS: frame list add/remove/duplicate/reorder with min-1 invariant")
		quit(0)
	else:
		for f in failures:
			print("FAIL: ", f)
		quit(1)


func _run() -> Array[String]:
	var failures: Array[String] = []
	var tex := load(TEX_PATH) as Texture2D
	var ctrl := FrameController.new()

	var a := ctrl.add_frame(tex, 0.2)
	var b := ctrl.add_frame(tex)
	var c := ctrl.add_frame(null, 0.5)
	if ctrl.frames.size() != 3:
		failures.append("expected 3 frames after adds")
	if a.frame_index != 0 or b.frame_index != 1 or c.frame_index != 2:
		failures.append("add_frame did not auto-index")
	if absf(b.duration - 0.1) > 0.001:
		failures.append("default duration should be 0.1")

	if ctrl.duplicate_frame(1) == false:
		failures.append("duplicate_frame returned false")
	elif ctrl.frames.size() != 4 or ctrl.frames[2].texture != b.texture:
		failures.append("duplicate did not copy the texture ref")

	# After duplicate: [a, b, b', c]. move 0 -> 2 gives [b, b', a, c].
	if ctrl.move_frame(0, 2) == false:
		failures.append("move_frame returned false")
	elif ctrl.frames[0] != b or ctrl.frames[2] != a or ctrl.frames[1] == b:
		failures.append("move_frame did not reorder as expected")

	if ctrl.set_frame_duration(0, 0) == false or absf(ctrl.frames[0].duration - 0.01) > 0.001:
		failures.append("set_frame_duration did not clamp to 0.01")

	# Remove down to exactly one; the last removal is refused.
	if not ctrl.remove_frame(3):
		failures.append("remove_frame(3) failed on a size-4 list")
	if not ctrl.remove_frame(1):
		failures.append("remove_frame(1) failed")
	if not ctrl.remove_frame(0):
		failures.append("remove_frame(0) failed")
	if ctrl.remove_frame(0) != false or ctrl.frames.size() != 1:
		failures.append("removing the last frame must be refused (min-1 invariant)")

	for i in ctrl.frames.size():
		if ctrl.frames[i].frame_index != i:
			failures.append("frame_index is not contiguous after mutations")
			break
	return failures