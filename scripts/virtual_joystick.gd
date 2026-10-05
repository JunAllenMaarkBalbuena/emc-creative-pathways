class_name EMCMobileJoystick
extends Control

signal value_changed(value: Vector2)

@export_range(40.0, 180.0, 1.0) var radius := 74.0
@export_range(12.0, 80.0, 1.0) var knob_radius := 31.0
@export_range(0.0, 0.8, 0.01) var deadzone := 0.12
@export var mouse_enabled := true

var _dragging := false
var _value := Vector2.ZERO

func _ready() -> void:
	custom_minimum_size = Vector2(radius * 2.0, radius * 2.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_dragging = event.pressed
		_update_value(event.position if event.pressed else size * 0.5)
	elif event is InputEventScreenDrag and _dragging:
		_update_value(event.position)
	elif mouse_enabled and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		_update_value(event.position if event.pressed else size * 0.5)
	elif mouse_enabled and event is InputEventMouseMotion and _dragging:
		_update_value(event.position)

## Returns the control to neutral and reports a zero value, so a character
## driven by it stops moving.
##
## Needed whenever the joystick is hidden while deflected. A hidden Control
## stops receiving _gui_input, so the finger lift that would normally re-centre
## the stick never arrives - without this the last deflected value is held
## forever, and PlayerController keeps preferring it over keyboard input because
## it only adopts the longer of the two.
func reset() -> void:
	_dragging = false
	if _value.is_zero_approx():
		return
	_value = Vector2.ZERO
	value_changed.emit(_value)
	queue_redraw()

func _update_value(touch_position: Vector2) -> void:
	var center := size * 0.5
	_value = ((touch_position - center) / radius).limit_length()
	if _value.length() < deadzone:
		_value = Vector2.ZERO
	value_changed.emit(_value)
	queue_redraw()

func _draw() -> void:
	var center := size * 0.5
	draw_circle(center, radius, Color(0.04, 0.10, 0.20, 0.45))
	draw_arc(center, radius, 0.0, TAU, 48, Color(0.65, 0.85, 1.0, 0.8), 2.0)
	draw_circle(center + _value * radius, knob_radius, Color(0.20, 0.65, 1.0, 0.78))
