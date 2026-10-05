class_name ColorPickerControl
extends Control

signal color_changed(color: Color)
signal drag_started()
signal drag_ended(final_color: Color)

var wheel_radius := 80.0
var slider_width := 20.0
var spacing := 10.0
var border_color := Color(0.3, 0.3, 0.35, 1)

var _hue := 0.0
var _sat := 1.0
var _val := 1.0
var _alpha := 1.0
var _color := Color.WHITE
var _dragging_wheel := false
var _dragging_value := false
var _dragging_alpha := false
var _hex_text := ""


func _ready():
	custom_minimum_size = Vector2(wheel_radius * 2 + slider_width * 2 + spacing * 3 + 16,
		wheel_radius * 2 + 80)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_update_color()


func set_color(c: Color):
	_color = c
	_hue = c.h
	_sat = c.s
	_val = c.v
	_alpha = c.a
	_hex_text = "#" + c.to_html(false)
	queue_redraw()


func get_color() -> Color:
	return _color


func _update_color():
	_color = Color.from_hsv(_hue, _sat, _val)
	_color.a = _alpha
	_hex_text = "#" + _color.to_html(false)
	color_changed.emit(_color)
	queue_redraw()


func _draw():
	var wheel_diameter := wheel_radius * 2.0
	var wheel_origin := Vector2(spacing, spacing + 20)
	var value_bar_origin := Vector2(wheel_diameter + spacing * 2, spacing + 20)
	var alpha_bar_origin := Vector2(wheel_diameter + slider_width + spacing * 3, spacing + 20)
	_draw_wheel(wheel_origin)
	_draw_value_bar(value_bar_origin)
	_draw_alpha_bar(alpha_bar_origin)
	_draw_hex_input()
	var swatch_rect := Rect2(spacing, wheel_diameter + spacing + 24,
		wheel_diameter + slider_width + spacing, 28)
	var checked := _checker_for(swatch_rect, 8)
	for rect in checked:
		draw_rect(rect[0], rect[1])
	draw_rect(swatch_rect, _color)
	draw_rect(swatch_rect, border_color, false, 1.0)


func _draw_wheel(origin: Vector2):
	var center := origin + Vector2(wheel_radius, wheel_radius)
	var segs := 64
	var da := TAU / segs
	for i in segs:
		var a1 := da * i
		var a2 := da * (i + 1)
		var p1 := center + Vector2(cos(a1), sin(a1)) * wheel_radius
		var p2 := center + Vector2(cos(a2), sin(a2)) * wheel_radius
		var c1: Color = Color.from_hsv(float(i) / segs, 1.0, 1.0)
		var c2: Color = Color.from_hsv(float(i + 1) / segs, 1.0, 1.0)
		var mid := (p1 + p2) / 2.0
		draw_colored_polygon([center, p1, mid], c1)
		draw_colored_polygon([center, mid, p2], c2)
		var bands := 5
		for j in bands:
			var t0 := float(j) / bands
			var t1 := float(j + 1) / bands
			var inner_r := wheel_radius * t0
			var outer_r := wheel_radius * t1
			var mid_t := (t0 + t1) * 0.5
			var alpha := (1.0 - mid_t) * (1.0 - mid_t)
			var col: Color = Color(1, 1, 1, alpha)
			var ip1 := center + Vector2(cos(a1), sin(a1)) * inner_r
			var ip2 := center + Vector2(cos(a2), sin(a2)) * inner_r
			var op1 := center + Vector2(cos(a1), sin(a1)) * outer_r
			var op2 := center + Vector2(cos(a2), sin(a2)) * outer_r
			draw_colored_polygon([ip1, op1, op2], col)
			draw_colored_polygon([ip1, op2, ip2], col)
	var select_angle := _hue * TAU
	var select_dist := _sat * wheel_radius
	var select_pos := center + Vector2(cos(select_angle), sin(select_angle)) * select_dist
	draw_circle(select_pos, 5.0, Color.WHITE)
	draw_circle(select_pos, 5.0, Color.BLACK, false, 1.5)


func _draw_value_bar(origin: Vector2):
	var bar_h := wheel_radius * 2.0
	var bar_rect := Rect2(origin, Vector2(slider_width, bar_h))
	var hue_color: Color = Color.from_hsv(_hue, _sat, 1.0)
	for y in int(bar_h):
		var t := y / bar_h
		var v := 1.0 - t
		var c: Color = Color(hue_color.r * v, hue_color.g * v, hue_color.b * v, 1.0)
		draw_rect(Rect2(origin.x, origin.y + y, slider_width, 1), c)
	draw_rect(bar_rect, border_color, false, 1.0)
	var handle_y := origin.y + bar_h * (1.0 - _val)
	var handle_rect := Rect2(origin.x - 2, handle_y - 4, slider_width + 4, 8)
	draw_rect(handle_rect, Color.WHITE)
	draw_rect(handle_rect, Color(0.2, 0.2, 0.25, 1), false, 1.0)


func _draw_alpha_bar(origin: Vector2):
	var bar_h := wheel_radius * 2.0
	var bar_rect := Rect2(origin, Vector2(slider_width, bar_h))
	# Checkerboard underlay so the alpha you pick is visibly honest.
	var cell := 7
	for gy in int(bar_h / cell) + 1:
		for gx in int(slider_width / cell) + 1:
			var rect := Rect2(origin.x + gx * cell, origin.y + gy * cell, cell, cell)
			var shade := 0.82 if (gx + gy) % 2 == 0 else 0.58
			draw_rect(rect, Color(shade, shade, shade, 1.0))
	var rgb: Color = Color.from_hsv(_hue, _sat, _val)
	for y in int(bar_h):
		var t := y / bar_h
		var a := 1.0 - t
		draw_rect(Rect2(origin.x, origin.y + y, slider_width, 1),
			Color(rgb.r, rgb.g, rgb.b, a))
	draw_rect(bar_rect, border_color, false, 1.0)
	var handle_y := origin.y + bar_h * (1.0 - _alpha)
	var handle_rect := Rect2(origin.x - 2, handle_y - 4, slider_width + 4, 8)
	draw_rect(handle_rect, Color.WHITE)
	draw_rect(handle_rect, Color(0.2, 0.2, 0.25, 1), false, 1.0)


func _checker_for(rect: Rect2, cell: int) -> Array[Array]:
	var cells: Array[Array] = []
	for y in range(0, int(rect.size.y), cell):
		for x in range(0, int(rect.size.x), cell):
			var cx := int(rect.position.x) + x
			var cy := int(rect.position.y) + y
			var shade := 0.82 if (int(x / float(cell)) + int(y / float(cell))) % 2 == 0 else 0.58
			cells.append([
				Rect2(cx, cy, minf(cell, rect.size.x - x), minf(cell, rect.size.y - y)),
				Color(shade, shade, shade, 1.0),
			])
	return cells


func _draw_hex_input():
	var wheel_diameter := wheel_radius * 2.0
	var hex_rect := Rect2(spacing, wheel_diameter + spacing + 56, wheel_diameter + slider_width + spacing, 24)
	draw_rect(hex_rect, Color(0.12, 0.14, 0.2, 1))
	draw_rect(hex_rect, border_color, false, 1.0)


func _gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed:
		var mpos: Vector2 = event.position
		var wheel_diameter := wheel_radius * 2.0
		var wheel_origin := Vector2(spacing, spacing + 20)
		var center := wheel_origin + Vector2(wheel_radius, wheel_radius)
		var dist: float = mpos.distance_to(center)
		if dist <= wheel_radius:
			_dragging_wheel = true
			drag_started.emit()
			_pick_wheel(mpos - center)
			accept_event()
		else:
			var value_bar_origin := Vector2(wheel_diameter + spacing * 2, spacing + 20)
			var bar_rect := Rect2(value_bar_origin, Vector2(slider_width, wheel_radius * 2))
			if bar_rect.has_point(mpos):
				_dragging_value = true
				drag_started.emit()
				_pick_value(mpos, value_bar_origin)
				accept_event()
			else:
				var alpha_bar_origin := Vector2(wheel_diameter + slider_width + spacing * 3, spacing + 20)
				var alpha_rect := Rect2(alpha_bar_origin, Vector2(slider_width, wheel_radius * 2))
				if alpha_rect.has_point(mpos):
					_dragging_alpha = true
					drag_started.emit()
					_pick_alpha(mpos, alpha_bar_origin)
					accept_event()
	if event is InputEventMouseButton and not event.pressed:
		var was_dragging := _dragging_wheel or _dragging_value or _dragging_alpha
		_dragging_wheel = false
		_dragging_value = false
		_dragging_alpha = false
		if was_dragging:
			drag_ended.emit(_color)
	if event is InputEventMouseMotion:
		var mpos: Vector2 = event.position
		if _dragging_wheel:
			var wheel_origin := Vector2(spacing, spacing + 20)
			_pick_wheel(mpos - wheel_origin - Vector2(wheel_radius, wheel_radius))
		elif _dragging_value:
			var wheel_diameter := wheel_radius * 2.0
			var value_bar_origin := Vector2(wheel_diameter + spacing * 2, spacing + 20)
			_pick_value(mpos, value_bar_origin)
		elif _dragging_alpha:
			var wheel_diameter := wheel_radius * 2.0
			var alpha_bar_origin := Vector2(wheel_diameter + slider_width + spacing * 3, spacing + 20)
			_pick_alpha(mpos, alpha_bar_origin)


func _pick_wheel(local: Vector2):
	var angle := fmod(atan2(local.y, local.x) + TAU, TAU)
	_hue = angle / TAU
	_sat = clampf(local.length() / wheel_radius, 0.0, 1.0)
	_update_color()


func _pick_value(mpos: Vector2, bar_origin: Vector2):
	var bar_h := wheel_radius * 2.0
	var t := (mpos.y - bar_origin.y) / bar_h
	_val = clampf(1.0 - t, 0.0, 1.0)
	_update_color()


func _pick_alpha(mpos: Vector2, bar_origin: Vector2):
	var bar_h := wheel_radius * 2.0
	var t := (mpos.y - bar_origin.y) / bar_h
	_alpha = clampf(1.0 - t, 0.0, 1.0)
	_update_color()
