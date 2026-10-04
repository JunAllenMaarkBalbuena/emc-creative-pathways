class_name CanvasView
extends Control

signal view_changed(zoom: float, offset: Vector2)

var zoom := 1.0
var offset := Vector2.ZERO
var canvas_width := 512
var canvas_height := 512

var show_grid := false
var grid_size := 32
var checker_size := 16
var canvas_color := Color(0.15, 0.15, 0.15, 1)

var cursor_overlay: CursorOverlay

var composite_image: Image:
	set(img):
		composite_image = img
		if img:
			if _composite_texture == null:
				_composite_texture = ImageTexture.create_from_image(img)
			else:
				_composite_texture.set_image(img)
		else:
			_composite_texture = null
		queue_redraw()

var _composite_texture: ImageTexture
var pan_mode := false
var _dragging := false
var _drag_start := Vector2.ZERO
var _drag_offset_start := Vector2.ZERO
var _last_mouse := Vector2.ZERO
var _checker_tile_tex: ImageTexture
var _checker_tile_px := 256


func _ready():
	cursor_overlay = CursorOverlay.new()
	cursor_overlay.name = "CursorOverlay"
	cursor_overlay.anchors_preset = 15
	cursor_overlay.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(cursor_overlay)


func _draw():
	_draw_checkerboard()
	_draw_composite()
	if show_grid:
		_draw_grid()


func _ensure_checker_tile():
	if _checker_tile_tex != null:
		return
	var img := Image.create(_checker_tile_px, _checker_tile_px, false, Image.FORMAT_RGBA8)
	var c1 := Color(0.18, 0.18, 0.18, 1)
	var c2 := Color(0.22, 0.22, 0.22, 1)
	for y in _checker_tile_px:
		for x in _checker_tile_px:
			var cx := int(x / float(checker_size)) % 2
			var cy := int(y / float(checker_size)) % 2
			img.set_pixel(x, y, c1 if (cx + cy) % 2 == 0 else c2)
	_checker_tile_tex = ImageTexture.create_from_image(img)


func _draw_checkerboard():
	var view_rect := Rect2(Vector2.ZERO, size)
	var canvas_rect := Rect2(offset.x, offset.y,
		canvas_width * zoom, canvas_height * zoom)
	var vis_rect: Rect2 = view_rect.intersection(canvas_rect)
	if vis_rect.size.x <= 0 or vis_rect.size.y <= 0:
		return

	_ensure_checker_tile()

	var ts := maxf(32.0, _checker_tile_px * zoom)
	var ts_i := int(ts)
	var start_x := int(floor(vis_rect.position.x / ts)) * ts_i
	var start_y := int(floor(vis_rect.position.y / ts)) * ts_i

	var y := start_y
	while y < int(vis_rect.end.y):
		var x := start_x
		while x < int(vis_rect.end.x):
			draw_texture_rect(_checker_tile_tex, Rect2(x, y, ts, ts), false)
			x += ts_i
		y += ts_i


func _draw_composite():
	if _composite_texture == null:
		return
	if zoom <= 0.001:
		return
	var dest := Rect2(offset.x, offset.y,
		canvas_width * zoom, canvas_height * zoom)
	draw_texture_rect(_composite_texture, dest, false)
	draw_rect(dest, Color(0.4, 0.4, 0.5, 0.5), false, 1.0)


func _draw_grid():
	var gs := grid_size * zoom
	var canvas_rect := Rect2(offset.x, offset.y,
		canvas_width * zoom, canvas_height * zoom)
	var grid_color := Color(0.3, 0.3, 0.4, 0.15)
	var y := canvas_rect.position.y + gs
	while y < canvas_rect.position.y + canvas_rect.size.y:
		draw_line(Vector2(canvas_rect.position.x, y),
			Vector2(canvas_rect.position.x + canvas_rect.size.x, y), grid_color)
		y += gs
	var x := canvas_rect.position.x + gs
	while x < canvas_rect.position.x + canvas_rect.size.x:
		draw_line(Vector2(x, canvas_rect.position.y),
			Vector2(x, canvas_rect.position.y + canvas_rect.size.y), grid_color)
		x += gs


func screen_to_canvas(screen_pos: Vector2) -> Vector2:
	if zoom <= 0.001:
		return screen_pos - offset
	return (screen_pos - offset) / zoom


func canvas_to_screen(canvas_pos: Vector2) -> Vector2:
	return canvas_pos * zoom + offset


func reset_view():
	zoom = 1.0
	var cx := (size.x - canvas_width * zoom) * 0.5
	var cy := (size.y - canvas_height * zoom) * 0.5
	offset = Vector2(maxf(0, cx), maxf(0, cy))
	view_changed.emit(zoom, offset)
	queue_redraw()


func fit_to_view():
	if size.x <= 0 or size.y <= 0:
		zoom = 1.0
		offset = Vector2.ZERO
		return
	var sx: float = size.x / canvas_width
	var sy: float = size.y / canvas_height
	zoom = minf(sx, sy) * 0.9
	offset = Vector2((size.x - canvas_width * zoom) * 0.5,
		(size.y - canvas_height * zoom) * 0.5)
	view_changed.emit(zoom, offset)
	queue_redraw()


func set_zoom(z: float, center: Vector2 = Vector2()):
	var old_zoom: float = zoom
	zoom = clampf(z, 0.1, 10.0)
	if center != Vector2.ZERO:
		offset = center - (center - offset) * (zoom / old_zoom)
	view_changed.emit(zoom, offset)
	queue_redraw()


func handle_input(event: InputEvent):
	var pos := get_local_mouse_position()
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_MIDDLE:
				_dragging = true
				_drag_start = pos
				_drag_offset_start = offset
			MOUSE_BUTTON_LEFT:
				if pan_mode:
					_dragging = true
					_drag_start = pos
					_drag_offset_start = offset
			MOUSE_BUTTON_WHEEL_UP:
				set_zoom(zoom * 1.15, pos)
			MOUSE_BUTTON_WHEEL_DOWN:
				set_zoom(zoom / 1.15, pos)

	if event is InputEventMouseButton and not event.pressed:
		if event.button_index in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_LEFT]:
			_dragging = false

	if event is InputEventMouseMotion:
		_last_mouse = pos
		if _dragging:
			offset = _drag_offset_start + (pos - _drag_start)
			view_changed.emit(zoom, offset)
			queue_redraw()
