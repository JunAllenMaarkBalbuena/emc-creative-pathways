class_name ViewOrbitGizmo
extends Control

signal orbit_by(delta: Vector2)
signal view_axis_requested(axis: Vector3)
signal view_reset_requested

const AXIS_INFO := {
	Vector3.RIGHT: {"label": "X", "color": Color(0.95, 0.3, 0.3)},
	Vector3.UP: {"label": "Y", "color": Color(0.35, 0.9, 0.4)},
	Vector3.BACK: {"label": "Z", "color": Color(0.35, 0.55, 0.95)},
	Vector3.LEFT: {"label": "-X", "color": Color(0.95, 0.3, 0.3)},
	Vector3.DOWN: {"label": "-Y", "color": Color(0.35, 0.9, 0.4)},
	Vector3.FORWARD: {"label": "-Z", "color": Color(0.35, 0.55, 0.95)},
}

const RADIUS: float = 34.0
const SPOKE_LENGTH: float = 26.0
const HANDLE_RADIUS: float = 7.0
const HIT_RADIUS: float = 16.0

var _dragging: bool = false
var _hovered_axis: Vector3 = Vector3.ZERO
var _touch_index: int = -1
var _camera: Camera3D = null
var _last_cam_basis: Basis

func _ready():
	custom_minimum_size = Vector2(RADIUS * 2 + SPOKE_LENGTH * 2, RADIUS * 2 + SPOKE_LENGTH * 2)
	mouse_filter = Control.MOUSE_FILTER_STOP

func set_camera(camera: Camera3D):
	_camera = camera
	if _camera:
		_last_cam_basis = _camera.global_transform.basis
	queue_redraw()

func _process(_delta: float):
	if _camera and is_instance_valid(_camera):
		var basis := _camera.global_transform.basis
		if basis != _last_cam_basis:
			_last_cam_basis = basis
			queue_redraw()

func _gui_input(event: InputEvent):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if (event.position - size / 2.0).length() <= 9.0:
				view_reset_requested.emit()
				return
			var axis := _axis_at(event.position)
			if axis != Vector3.ZERO:
				view_axis_requested.emit(axis)
				return
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
			_touch_index = -1
			queue_redraw()
	if event is InputEventMouseMotion:
		if _dragging:
			orbit_by.emit(event.relative)
		else:
			_update_hover(event.position)
	if event is InputEventScreenTouch:
		if event.pressed:
			_dragging = true
			_touch_index = event.index
		elif event.index == _touch_index:
			_dragging = false
			_touch_index = -1
	if event is InputEventScreenDrag:
		if event.index == _touch_index and _dragging:
			orbit_by.emit(event.relative)

func _notification(what: int):
	if what == NOTIFICATION_MOUSE_EXIT:
		_hovered_axis = Vector3.ZERO
		queue_redraw()

func _update_hover(mouse_pos: Vector2):
	var hit := _axis_at(mouse_pos)
	if hit != _hovered_axis:
		_hovered_axis = hit
		queue_redraw()
	if hit != Vector3.ZERO:
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	else:
		mouse_default_cursor_shape = Control.CURSOR_ARROW

func _axis_at(screen_pos: Vector2) -> Vector3:
	var center := size / 2.0
	for axis in AXIS_INFO:
		var pos := _axis_screen_pos(center, axis)
		if pos.distance_to(center) < 0.1:
			continue  # collapsed axis (points into/out of screen); not clickable
		if (screen_pos - pos).length() <= HIT_RADIUS:
			return axis
	return Vector3.ZERO

func _axis_screen_dir(axis: Vector3) -> Vector2:
	# Project the world-space axis through the camera so the mini-gizmo
	# tilts exactly like the current view. Without a camera, fall back to
	# the old fixed screen mapping.
	if _camera and is_instance_valid(_camera):
		var cam_dir := _camera.global_transform.basis.inverse() * axis
		return Vector2(cam_dir.x, -cam_dir.y)
	return Vector2(axis.x, -axis.y)

func _axis_screen_pos(center: Vector2, axis: Vector3) -> Vector2:
	# Keep the projected length (not normalized): a world axis tilted away
	# from the camera foreshortens toward center, exactly like a nav cube.
	var dir := _axis_screen_dir(axis)
	if dir.length() < 0.05:
		return center
	return center + dir * (RADIUS + SPOKE_LENGTH)

func _draw():
	var center := size / 2.0

	# Backdrop disc
	draw_circle(center, RADIUS + SPOKE_LENGTH + 6.0, Color(0.05, 0.06, 0.09, 0.55))

	# Axis spokes + handles
	for axis in AXIS_INFO:
		var info: Dictionary = AXIS_INFO[axis]
		var col: Color = info["color"]
		var pos := _axis_screen_pos(center, axis)
		if pos.distance_to(center) < 0.05:
			continue  # collapsed axis (points into/out of screen); not drawn
		var dir := (pos - center) / (RADIUS + SPOKE_LENGTH)
		draw_line(center + dir * RADIUS, pos, col, 2.0, true)
		var handle_col := col.lightened(0.25) if _hovered_axis == axis else col
		draw_circle(pos, HANDLE_RADIUS, handle_col)
		draw_string(ThemeDB.fallback_font, pos + Vector2(-4, 4), info["label"],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)

	# Center reset dot
	draw_circle(center, 5.0, Color(0.9, 0.9, 0.95, 0.9))
