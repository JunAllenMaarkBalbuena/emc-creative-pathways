extends Node

## Regression test: undo/redo in the Digital Art Lab must restore pixels
## byte-exactly, including over pre-existing content, for float-coordinate
## (diagonal) strokes, the eraser, strokes at the canvas edge, whipsaw
## zigzags, and flood fill. The reported bug: after undo/redo, random
## strips of previously-painted content are erased (transparent) - i.e. the
## restored region is missing pre-stroke pixels.
##
## Each case captures the full layer bytes (and, for the first case, the
## composite) before an action, performs it, undoes via the real _on_undo
## handler, and requires a byte-exact restore; the first case also redoes
## and requires a byte-exact re-apply.

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
	lab.brush_hardness = 1.0
	lab.color_manager.set_primary(Color(0.2, 0.8, 0.4, 1.0))

	# Solid background so any wrongly-erased strip is visible as a hole.
	layer.image.fill(Color(0.3, 0.5, 0.9, 1.0))

	if not await _case_diagonal_float(lab, layer):
		return 1
	if not await _case_eraser(lab, layer):
		return 1
	if not await _case_edge(lab, layer):
		return 1
	if not await _case_zigzag(lab, layer):
		return 1
	if not await _case_fill(lab, layer):
		return 1

	print("PASS: undo/redo restores pixels byte-exactly across all cases")
	return 0


# ── Helpers ──────────────────────────────────────────────────

func _stroke(lab: DigitalArtLab, pts: Array[Vector2]) -> void:
	lab._start_stroke(pts[0])
	for i in range(1, pts.size()):
		lab._continue_stroke(pts[i])
	lab._end_stroke()


func _build_line(from: Vector2, to: Vector2, steps: int) -> Array[Vector2]:
	var pts: Array[Vector2] = []
	for i in range(steps + 1):
		pts.append(from.lerp(to, float(i) / steps))
	return pts


## Returns the first mismatching pixel between the layer and a reference
## byte snapshot, or Vector2i(-1, -1) when they are identical.
func _first_diff(layer: LayerData, ref: PackedByteArray) -> Vector2i:
	var cur := layer.image.get_data()
	if cur == ref:
		return Vector2i(-1, -1)
	var w := layer.image.get_width()
	for i in range(cur.size() / 4):
		var o := i * 4
		if cur[o] != ref[o] or cur[o + 1] != ref[o + 1] \
				or cur[o + 2] != ref[o + 2] or cur[o + 3] != ref[o + 3]:
			return Vector2i(i % w, i / w)
	return Vector2i(-1, -1)


func _count_diff(layer: LayerData, ref: PackedByteArray) -> int:
	var cur := layer.image.get_data()
	if cur == ref:
		return 0
	var n := 0
	for i in range(cur.size() / 4):
		var o := i * 4
		if cur[o] != ref[o] or cur[o + 1] != ref[o + 1] \
				or cur[o + 2] != ref[o + 2] or cur[o + 3] != ref[o + 3]:
			n += 1
	return n


## Debug helper: report the bounding box of the diff and per-row mismatch
## counts plus a few sample pixels, to diagnose strip-assembly corruption.
func _dump_diff(layer: LayerData, ref: PackedByteArray, max_rows: int) -> void:
	var cur := layer.image.get_data()
	var w := layer.image.get_width()
	var h := layer.image.get_height()
	var min_p := Vector2i(w, h)
	var max_p := Vector2i(-1, -1)
	var row_counts: Dictionary = {}
	for i in range(cur.size() / 4):
		var o := i * 4
		var px := Vector2i(i % w, i / w)
		if cur[o] != ref[o] or cur[o + 1] != ref[o + 1] \
				or cur[o + 2] != ref[o + 2] or cur[o + 3] != ref[o + 3]:
			min_p = Vector2i(mini(min_p.x, px.x), mini(min_p.y, px.y))
			max_p = Vector2i(maxi(max_p.x, px.x), maxi(max_p.y, px.y))
			row_counts[px.y] = row_counts.get(px.y, 0) + 1
	print("DEBUG: diff bbox %s .. %s" % [min_p, max_p])
	var shown := 0
	for y in row_counts:
		if shown >= max_rows:
			break
		print("DEBUG: row %d has %d mismatches" % [y, row_counts[y]])
		shown += 1
	# Sample the actual vs expected color at the corner pixels of the bbox.
	var probes: Array[Vector2i] = [
		Vector2i(min_p.x, min_p.y),
		Vector2i(max_p.x, min_p.y),
		Vector2i(min_p.x, max_p.y),
		Vector2i(max_p.x, max_p.y),
	]
	for probe in probes:
		if probe.x < 0 or probe.y < 0 or probe.y >= h or probe.x >= w:
			continue
		var o: int = (probe.y * w + probe.x) * 4
		print("DEBUG: at (%d,%d) got=(%d,%d,%d,%d) want=(%d,%d,%d,%d)" % [
			probe.x, probe.y,
			cur[o], cur[o + 1], cur[o + 2], cur[o + 3],
			ref[o], ref[o + 1], ref[o + 2], ref[o + 3],
		])


# ── Cases ────────────────────────────────────────────────────

func _case_diagonal_float(lab: DigitalArtLab, layer: LayerData) -> bool:
	var before: PackedByteArray = layer.image.get_data()
	# Composite reference right before the stroke. The direct image.fill() above
	# bypassed dirty tracking, so mark the whole canvas dirty and rebuild first,
	# otherwise the cached composite never contained the fill.
	lab.layer_manager.mark_dirty()
	lab._refresh_composite()
	var comp_before: PackedByteArray = lab.layer_manager.get_composited().get_data()

	var pts := _build_line(Vector2(40.0, 40.0), Vector2(470.0, 300.0), 30)
	_stroke(lab, pts)
	var after: PackedByteArray = layer.image.get_data()
	if after == before:
		print("FAIL: diagonal stroke painted nothing over the fill")
		return false

	if not lab.history_manager.can_undo():
		print("FAIL: can_undo false after the diagonal stroke")
		return false
	lab._on_undo()  # real handler: undo + composite refresh + layer UI
	var d := _first_diff(layer, before)
	if d.x >= 0:
		print("FAIL: diagonal-stroke undo left %d px wrong, first at %s" %
			[_count_diff(layer, before), d])
		return false

	# Composite must match the pre-stroke composite after undo.
	lab._refresh_composite()
	if lab.layer_manager.get_composited().get_data() != comp_before:
		print("FAIL: diagonal-stroke undo left the composite stale")
		return false

	if not lab.history_manager.can_redo():
		print("FAIL: can_redo false after the diagonal-stroke undo")
		return false
	lab._on_redo()
	d = _first_diff(layer, after)
	if d.x >= 0:
		print("FAIL: diagonal-stroke redo left %d px wrong, first at %s" %
			[_count_diff(layer, after), d])
		return false
	# Leave the redo undone so later cases start from the pre-stroke state.
	if not lab.history_manager.can_undo():
		print("FAIL: can_undo false before cleanup undo (diagonal stroke)")
		return false
	lab._on_undo()
	return true


func _case_eraser(lab: DigitalArtLab, layer: LayerData) -> bool:
	lab.current_tool = lab.Tool.ERASER
	var before: PackedByteArray = layer.image.get_data()
	var pts := _build_line(Vector2(50.0, 400.0), Vector2(460.0, 60.0), 24)
	_stroke(lab, pts)
	lab.current_tool = lab.Tool.BRUSH
	var after: PackedByteArray = layer.image.get_data()
	if after == before:
		print("FAIL: eraser stroke changed nothing")
		return false
	if not lab.history_manager.can_undo():
		print("FAIL: can_undo false after the eraser stroke")
		return false
	lab._on_undo()
	var d := _first_diff(layer, before)
	if d.x >= 0:
		print("FAIL: eraser-stroke undo left %d px wrong, first at %s" %
			[_count_diff(layer, before), d])
		return false
	return true


func _case_edge(lab: DigitalArtLab, layer: LayerData) -> bool:
	var before: PackedByteArray = layer.image.get_data()
	# Stroke that starts off-canvas (negative y) and hugs the left/right edges.
	var pts: Array[Vector2] = [
		Vector2(30.0, -5.0), Vector2(30.0, 40.0), Vector2(4.0, 90.0),
		Vector2(4.0, 150.0), Vector2(506.0, 150.0), Vector2(508.0, 220.0),
	]
	_stroke(lab, pts)
	var after: PackedByteArray = layer.image.get_data()
	if after == before:
		print("FAIL: edge stroke painted nothing")
		return false
	if not lab.history_manager.can_undo():
		print("FAIL: can_undo false after the edge stroke")
		return false
	lab._on_undo()
	var d := _first_diff(layer, before)
	if d.x >= 0:
		print("FAIL: edge-stroke undo left %d px wrong, first at %s" %
			[_count_diff(layer, before), d])
		_dump_diff(layer, before, 20)
		return false
	return true


func _case_zigzag(lab: DigitalArtLab, layer: LayerData) -> bool:
	var before: PackedByteArray = layer.image.get_data()
	var pts: Array[Vector2] = []
	var p := Vector2(80.0, 120.0)
	var dir_y := 1.0
	for i in 40:
		pts.append(p)
		p.x += 9.0
		p.y += dir_y * 7.0
		if i % 4 == 3:
			dir_y = -dir_y
	_stroke(lab, pts)
	var after: PackedByteArray = layer.image.get_data()
	if after == before:
		print("FAIL: zigzag stroke painted nothing")
		return false
	if not lab.history_manager.can_undo():
		print("FAIL: can_undo false after the zigzag stroke")
		return false
	lab._on_undo()
	var d := _first_diff(layer, before)
	if d.x >= 0:
		print("FAIL: zigzag-stroke undo left %d px wrong, first at %s" %
			[_count_diff(layer, before), d])
		return false
	return true


func _case_fill(lab: DigitalArtLab, layer: LayerData) -> bool:
	var before: PackedByteArray = layer.image.get_data()
	lab._do_fill(Vector2(256.0, 256.0))
	var after: PackedByteArray = layer.image.get_data()
	if after == before:
		print("FAIL: flood fill changed nothing")
		return false
	if not lab.history_manager.can_undo():
		print("FAIL: can_undo false after the flood fill")
		return false
	lab._on_undo()
	var d := _first_diff(layer, before)
	if d.x >= 0:
		print("FAIL: fill undo left %d px wrong, first at %s" %
			[_count_diff(layer, before), d])
		return false
	return true