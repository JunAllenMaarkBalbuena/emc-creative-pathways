class_name Painter
extends RefCounted

## Core painting engine for the Digital Art Lab.
## Handles brush strokes, erasing, flood fill, and eyedropper sampling.
## Operates directly on LayerData.image pixels.

# ── Brush tip cache ──────────────────────────────────────────
# Pre-rendered circular brush tips keyed by (size, hardness).
# Each tip is a 2D alpha map stored as a PackedFloat32Array of length size*size.
var _brush_cache: Dictionary[String, PackedFloat32Array] = {}  # key: "size_hardness" -> PackedFloat32Array


func get_brush_tip(size: int, hardness: float) -> PackedFloat32Array:
	var key := str(size) + "_" + str(hardness)
	if _brush_cache.has(key):
		return _brush_cache[key]

	var tip := PackedFloat32Array()
	tip.resize(size * size)
	var radius := size * 0.5
	var cx := radius - 0.5
	var cy := radius - 0.5
	var inv_hardness := 1.0 - hardness
	if inv_hardness < 0.01:
		inv_hardness = 0.01

	for y in size:
		for x in size:
			var dx := float(x) - cx
			var dy := float(y) - cy
			var dist := sqrt(dx * dx + dy * dy)
			var alpha := 0.0
			if dist <= radius:
				if hardness >= 1.0:
					alpha = 1.0
				else:
					# Soft falloff: full opacity in the core, linear fade at edge
					var core := radius * hardness
					if dist <= core:
						alpha = 1.0
					else:
						alpha = 1.0 - (dist - core) / (radius - core)
			tip[y * size + x] = clampf(alpha, 0.0, 1.0)
	_brush_cache[key] = tip
	return tip


func clear_cache():
	_brush_cache.clear()


# ── Brush stroke ─────────────────────────────────────────────
# Draws a paint dab at (cx, cy) on the layer.
# color = RGBA, size = pixel diameter, hardness = 0..1, opacity = 0..1
# Works on the dab's region as raw RGBA8 bytes (4 engine calls per dab
# instead of one get_pixel/set_pixel pair per pixel). The blend math is
# identical to the previous per-pixel version, and byte quantization
# (round(v * 255)) matches Image.set_pixel.
func paint_dab(layer: LayerData, cx: float, cy: float, color: Color,
		size: int, hardness: float, opacity: float):
	if layer == null or layer.image == null:
		return

	var img := layer.image
	var iw := img.get_width()
	var ih := img.get_height()
	var rad := ceilf(size * 0.5)
	var tip: PackedFloat32Array = get_brush_tip(size, hardness)
	var blend_a: float = color.a * opacity

	# Bounding box clamped to image bounds
	var x0 := maxi(0, int(floor(cx - rad)))
	var y0 := maxi(0, int(floor(cy - rad)))
	var x1 := mini(iw - 1, int(ceil(cx + rad)))
	var y1 := mini(ih - 1, int(ceil(cy + rad)))
	var w := x1 - x0 + 1
	var h := y1 - y0 + 1
	if w <= 0 or h <= 0:
		return

	var region := img.get_region(Rect2i(x0, y0, w, h))
	var bytes: PackedByteArray = region.get_data()
	var tip_ox := int(floor(cx - rad))
	var tip_oy := int(floor(cy - rad))
	var cr := color.r
	var cg := color.g
	var cb := color.b

	for py in h:
		var ty := y0 + py - tip_oy
		for px in w:
			var tx := x0 + px - tip_ox
			if tx < 0 or ty < 0 or tx >= size or ty >= size:
				continue
			var tip_alpha := tip[ty * size + tx]
			if tip_alpha <= 0.0:
				continue
			var final_a := blend_a * tip_alpha
			if final_a <= 0.0:
				continue
			var idx := (py * w + px) * 4
			var dr := bytes[idx] / 255.0
			var dg := bytes[idx + 1] / 255.0
			var db := bytes[idx + 2] / 255.0
			var da := bytes[idx + 3] / 255.0
			bytes[idx] = int(round((cr * final_a + dr * (1.0 - final_a)) * 255.0))
			bytes[idx + 1] = int(round((cg * final_a + dg * (1.0 - final_a)) * 255.0))
			bytes[idx + 2] = int(round((cb * final_a + db * (1.0 - final_a)) * 255.0))
			bytes[idx + 3] = int(round((final_a + da * (1.0 - final_a)) * 255.0))

	var out := Image.create_from_data(w, h, false, region.get_format(), bytes)
	img.blit_rect(out, Rect2i(0, 0, w, h), Vector2i(x0, y0))


# ── Eraser ───────────────────────────────────────────────────
# Same as brush but removes alpha instead of adding colour.
func erase_dab(layer: LayerData, cx: float, cy: float,
		size: int, hardness: float, opacity: float):
	if layer == null or layer.image == null:
		return

	var img := layer.image
	var iw := img.get_width()
	var ih := img.get_height()
	var rad := ceilf(size * 0.5)
	var tip := get_brush_tip(size, hardness)
	var erase_strength := opacity

	var x0 := maxi(0, int(floor(cx - rad)))
	var y0 := maxi(0, int(floor(cy - rad)))
	var x1 := mini(iw - 1, int(ceil(cx + rad)))
	var y1 := mini(ih - 1, int(ceil(cy + rad)))
	var w := x1 - x0 + 1
	var h := y1 - y0 + 1
	if w <= 0 or h <= 0:
		return

	var region := img.get_region(Rect2i(x0, y0, w, h))
	var bytes: PackedByteArray = region.get_data()
	var tip_ox := int(floor(cx - rad))
	var tip_oy := int(floor(cy - rad))

	for py in h:
		var ty := y0 + py - tip_oy
		for px in w:
			var tx := x0 + px - tip_ox
			if tx < 0 or ty < 0 or tx >= size or ty >= size:
				continue
			var tip_alpha := tip[ty * size + tx]
			if tip_alpha <= 0.0:
				continue
			var reduction := tip_alpha * erase_strength
			if reduction <= 0.0:
				continue
			var idx := (py * w + px) * 4
			var da := bytes[idx + 3] / 255.0
			bytes[idx + 3] = int(round(da * (1.0 - reduction) * 255.0))

	var out := Image.create_from_data(w, h, false, region.get_format(), bytes)
	img.blit_rect(out, Rect2i(0, 0, w, h), Vector2i(x0, y0))


# ── Flood fill ───────────────────────────────────────────────
# Fills contiguous pixels of similar colour starting at (sx, sy).
func flood_fill(layer: LayerData, sx: int, sy: int, fill_color: Color, tolerance: float):
	if layer == null or layer.image == null:
		return
	if sx < 0 or sy < 0 or sx >= layer.image.get_width() or sy >= layer.image.get_height():
		return

	var img := layer.image
	var w := img.get_width()
	var h := img.get_height()
	var target: Color = img.get_pixel(sx, sy)

	# If the target pixel is already the fill colour, skip to avoid infinite loop.
	if _color_close(target, fill_color, tolerance):
		return

	var visited := PackedByteArray()
	visited.resize(w * h)
	visited.fill(0)

	var stack: Array[Vector2i] = [Vector2i(sx, sy)]
	while stack.size() > 0:
		var p: Vector2i = stack.pop_back()
		if p.x < 0 or p.y < 0 or p.x >= w or p.y >= h:
			continue
		var idx: int = p.y * w + p.x
		if visited[idx] != 0:
			continue
		visited[idx] = 1

		var pc: Color = img.get_pixel(p.x, p.y)
		if not _color_close(pc, target, tolerance):
			continue

		var fa := fill_color.a
		var blended := Color(
			fill_color.r * fa + pc.r * (1.0 - fa),
			fill_color.g * fa + pc.g * (1.0 - fa),
			fill_color.b * fa + pc.b * (1.0 - fa),
			maxf(fa, pc.a)
		)
		img.set_pixel(p.x, p.y, blended)

		stack.append(Vector2i(p.x + 1, p.y))
		stack.append(Vector2i(p.x - 1, p.y))
		stack.append(Vector2i(p.x, p.y + 1))
		stack.append(Vector2i(p.x, p.y - 1))


func _color_close(a: Color, b: Color, tolerance: float) -> bool:
	return abs(a.r - b.r) <= tolerance and \
		   abs(a.g - b.g) <= tolerance and \
		   abs(a.b - b.b) <= tolerance and \
		   abs(a.a - b.a) <= tolerance


# ── Eyedropper ───────────────────────────────────────────────
# Returns the colour at (sx, sy) from the composited result.
func sample_color(composited: Image, sx: int, sy: int) -> Color:
	if composited == null:
		return Color.BLACK
	sx = clampi(sx, 0, composited.get_width() - 1)
	sy = clampi(sy, 0, composited.get_height() - 1)
	return composited.get_pixel(sx, sy)
