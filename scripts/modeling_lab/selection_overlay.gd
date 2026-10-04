class_name SelectionOverlay
extends Control

## Rubber-band selection rectangle drawn inside the SubViewport, using the
## same coordinate space as SubViewport.get_mouse_position() so the box tracks
## the drag exactly. Sits as the last child of the SubViewport so it draws on
## top of the 3D content.

var _from: Vector2 = Vector2.ZERO
var _to: Vector2 = Vector2.ZERO
var _active: bool = false

func show_box(from: Vector2, to: Vector2):
	_from = from
	_to = to
	_active = true
	visible = true
	queue_redraw()

func hide_box():
	_active = false
	visible = false
	queue_redraw()

func _draw():
	if not _active:
		return
	var rect := Rect2(_from, _to - _from).abs()
	draw_rect(rect, Color(0.3, 0.6, 1.0, 0.25), true)
	draw_rect(rect, Color(0.3, 0.6, 1.0, 0.9), false, 1.0)