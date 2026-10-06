extends Node

## Regression test: fast brush strokes must ink the WHOLE mouse path.
##
## The Digital Art Lab sampled one dab per motion event in _continue_stroke
## and then reset its length accumulator, so a fast mouse move that jumped
## far between events inked only a single spacing-step and dropped the rest
## of the segment - the "brush line lags behind when drawing fast" report.
##
## This harness drives synthetic fast events (60 px jumps at 6 px dab
## spacing = 10 dabs per event) straight through _start_stroke /
## _continue_stroke / _end_stroke and then walks the full path checking that
## every 3 px step got ink. With the bug the vast majority of the path stays
## bare; with the fix the line is continuous. The stroke is timed and printed
## as a generous catastrophic-regression guard (coverage is the real assert).

var _fail := 0

func _ready() -> void:
	var tree := get_tree()
	_fail = await _run()
	tree.quit(_fail)

func _run() -> int:
	var scene := load("res://scenes/digital_art_lab/digital_art_lab.tscn") as PackedScene
	var lab := scene.instantiate() as DigitalArtLab
	add_child(lab)
	await get_tree().process_frame

	var layer := lab.layer_manager.get_active()
	if layer == null or layer.image == null:
		print("FAIL: digital art lab has no active layer")
		return 1

	lab.brush_size = 20
	lab.brush_spacing = 0.3   # 6 px between dabs
	lab.brush_opacity = 1.0
	lab.brush_hardness = 1.0  # hard tip: dabs are solid

	# A fast stroke: every motion event jumps 60 px (10x the dab spacing).
	var pts: Array[Vector2] = []
	var p := Vector2(50.0, 100.0)
	for i in 20:
		pts.append(p)
		p.x += 60.0

	var t0 := Time.get_ticks_usec()
	lab._start_stroke(pts[0])
	for i in range(1, pts.size()):
		lab._continue_stroke(pts[i])
	lab._end_stroke()
	var elapsed_us := Time.get_ticks_usec() - t0

	# Coverage: every 3 px step along the whole path must be inked.
	var gaps := 0
	var step_px := 3.0
	for i in range(1, pts.size()):
		var a: Vector2 = pts[i - 1]
		var b: Vector2 = pts[i]
		var seg_dist := a.distance_to(b)
		var steps := int(seg_dist / step_px)
		for s in range(1, steps + 1):
			var q: Vector2 = a.lerp(b, s * step_px / seg_dist)
			var px := clampi(int(q.x), 0, layer.image.get_width() - 1)
			var py := clampi(int(q.y), 0, layer.image.get_height() - 1)
			if layer.image.get_pixel(px, py).a < 0.5:
				gaps += 1

	print("stroke: %d events, %d px travelled, %.2f ms, %d uncovered steps"
		% [pts.size() - 1, int(pts.back().x - pts.front().x), elapsed_us / 1000.0, gaps])
	if gaps > 0:
		print("FAIL: fast stroke left %d uncovered steps - the brush line lags the cursor" % gaps)
		return 1
	if elapsed_us > 500_000:
		print("FAIL: fast stroke took %.2f ms - drawing is pathologically slow" % (elapsed_us / 1000.0))
		return 1
	print("PASS: fast stroke fully inked end to end in %.2f ms" % (elapsed_us / 1000.0))
	# ── Undo/redo round-trip ──────────────────────────────────
	# Validates the incremental strip capture in history_manager: a second
	# stroke over existing content must undo back to the exact pre-stroke
	# pixels and redo to the exact post-stroke pixels.
	var before_undo: PackedByteArray = layer.image.get_data()

	var pts2: Array[Vector2] = []
	var q := Vector2(50.0, 200.0)
	for i in 20:
		pts2.append(q)
		q.x += 60.0
	lab._start_stroke(pts2[0])
	for i in range(1, pts2.size()):
		lab._continue_stroke(pts2[i])
	lab._end_stroke()
	var after_stroke2: PackedByteArray = layer.image.get_data()

	if not lab.history_manager.undo(lab.layer_manager):
		print("FAIL: undo of a brush stroke returned false")
		return 1
	if layer.image.get_data() != before_undo:
		print("FAIL: undo did not restore the pre-stroke layer exactly")
		return 1
	if not lab.history_manager.redo(lab.layer_manager):
		print("FAIL: redo of a brush stroke returned false")
		return 1
	if layer.image.get_data() != after_stroke2:
		print("FAIL: redo did not re-apply the stroke exactly")
		return 1
	print("PASS: stroke undo/redo round-trips exactly")
	return 0
