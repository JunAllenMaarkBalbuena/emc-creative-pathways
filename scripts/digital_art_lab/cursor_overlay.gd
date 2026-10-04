class_name CursorOverlay
extends Control

var cursor_screen_pos := Vector2(-999, -999)
var cursor_visible := false
var cursor_painting := false
var _paint_radius := 0.0
var _crosshair_arm := 8.0

var show_brush_preview := false
var brush_preview_pos := Vector2.ZERO
var brush_preview_size := 20.0
var brush_preview_color := Color.WHITE

func show_cursor(screen_pos: Vector2, painting: bool, paint_radius: float = 0.0, crosshair_arm: float = 8.0):
	cursor_screen_pos = screen_pos
	cursor_visible = true
	cursor_painting = painting
	_paint_radius = paint_radius
	_crosshair_arm = crosshair_arm
	queue_redraw()

func hide_cursor():
	cursor_visible = false
	cursor_painting = false
	queue_redraw()

func set_painting(painting: bool):
	if cursor_visible:
		cursor_painting = painting
		queue_redraw()

func _draw():
	if show_brush_preview:
		_draw_brush_preview()
	if cursor_visible:
		_draw_cursor()

func _draw_cursor():
	var pos := cursor_screen_pos
	if cursor_painting:
		var r := _paint_radius
		if r <= 0:
			r = _crosshair_arm
		draw_circle(pos, r, Color(0.0, 1.0, 0.0, 0.4))
		draw_circle(pos, r, Color(0.0, 1.0, 0.0, 0.9), false, 2.0)
	else:
		var color := Color(0.6, 0.85, 1.0, 0.85)
		draw_line(pos + Vector2(-_crosshair_arm, 0), pos + Vector2(_crosshair_arm, 0), color, 1.5)
		draw_line(pos + Vector2(0, -_crosshair_arm), pos + Vector2(0, _crosshair_arm), color, 1.5)

func _draw_brush_preview():
	var center := brush_preview_pos
	var radius := brush_preview_size * 0.5
	var col := brush_preview_color
	draw_circle(center, radius, Color(col.r, col.g, col.b, 0.3))
	draw_circle(center, radius, Color.WHITE, false, 1.0)