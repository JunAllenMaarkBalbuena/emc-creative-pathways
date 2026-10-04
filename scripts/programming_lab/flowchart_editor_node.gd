class_name FlowchartEditorNode
extends Control

enum NodeType { START, END, PROCESS, DECISION, INPUT_OUTPUT }

const TYPE_COLORS := {
	NodeType.START: Color("#2ecc71"),
	NodeType.END: Color("#e74c3c"),
	NodeType.PROCESS: Color("#3498db"),
	NodeType.DECISION: Color("#f39c12"),
	NodeType.INPUT_OUTPUT: Color("#9b59b6"),
}

const TYPE_LABELS := {
	NodeType.START: "Start",
	NodeType.END: "End",
	NodeType.PROCESS: "Process",
	NodeType.DECISION: "Decision",
	NodeType.INPUT_OUTPUT: "Input/Output",
}

var node_id: String = ""
var node_type: int = NodeType.PROCESS:
	set(v):
		node_type = v
		queue_redraw()
var label_text: String = "":
	set(v):
		label_text = v
		queue_redraw()
var is_prefilled := false
var is_selected := false
var yes_port := Port.RIGHT
var no_port := Port.LEFT
var dragging := false
var drag_offset := Vector2.ZERO
var hovered_port := -1

signal moved
signal drag_moved(delta: Vector2)
signal port_clicked(port_index: int)
signal selected
signal delete_requested

const NODE_W := 140
const NODE_H := 50
const PORT_RADIUS := 5.0
enum Port { TOP = 0, BOTTOM = 1, LEFT = 2, RIGHT = 3 }

func _init():
	custom_minimum_size = Vector2(NODE_W, NODE_H)
	size = Vector2(NODE_W, NODE_H)
	mouse_filter = MOUSE_FILTER_STOP
	mouse_exited.connect(func():
		if hovered_port >= 0:
			hovered_port = -1
			queue_redraw())

func get_port_center(port: int) -> Vector2:
	match port:
		Port.TOP: return global_position + Vector2(size.x * 0.5, 0)
		Port.BOTTOM: return global_position + Vector2(size.x * 0.5, size.y)
		Port.LEFT: return global_position + Vector2(0, size.y * 0.5)
		Port.RIGHT: return global_position + Vector2(size.x, size.y * 0.5)
	return global_position

func get_port_at(local_pos: Vector2) -> int:
	var half := PORT_RADIUS + 4.0
	var cx := size.x * 0.5
	var cy := size.y * 0.5
	if local_pos.distance_to(Vector2(cx, 0)) < half: return Port.TOP
	if local_pos.distance_to(Vector2(cx, size.y)) < half: return Port.BOTTOM
	if local_pos.distance_to(Vector2(0, cy)) < half: return Port.LEFT
	if local_pos.distance_to(Vector2(size.x, cy)) < half: return Port.RIGHT
	return -1

func _draw():
	var rect := Rect2(Vector2.ZERO, size)
	var color: Color = TYPE_COLORS.get(node_type, Color.WHITE)
	match node_type:
		NodeType.START, NodeType.END: _draw_oval(rect, color)
		NodeType.PROCESS: _draw_rounded_rect(rect, color)
		NodeType.DECISION: _draw_diamond(rect, color)
		NodeType.INPUT_OUTPUT: _draw_parallelogram(rect, color)
	if is_selected:
		draw_rect(rect, Color(1, 1, 1, 0.5), false, 2.0)
	var display_text: String = label_text if not label_text.is_empty() else TYPE_LABELS.get(node_type, "")
	if not display_text.is_empty():
		var font := ThemeDB.fallback_font
		var fs := ThemeDB.fallback_font_size
		var tp := Vector2(8, size.y * 0.5 + fs * 0.35)
		draw_string(font, tp, display_text, HORIZONTAL_ALIGNMENT_CENTER, size.x - 16, fs, Color.WHITE)
	for p in [Port.TOP, Port.BOTTOM, Port.LEFT, Port.RIGHT]:
		var pc := Vector2(size.x * 0.5, 0) if p == Port.TOP else \
			Vector2(size.x * 0.5, size.y) if p == Port.BOTTOM else \
			Vector2(0, size.y * 0.5) if p == Port.LEFT else \
			Vector2(size.x, size.y * 0.5)
		if p == hovered_port:
			draw_circle(pc, PORT_RADIUS + 3, Color(0.2, 0.8, 1.0, 0.3))
			draw_circle(pc, PORT_RADIUS + 1, Color(0.2, 0.9, 1.0, 0.9))
			draw_circle(pc, PORT_RADIUS + 1, Color(0.5, 0.9, 1.0, 1), false, 2.0)
		else:
			draw_circle(pc, PORT_RADIUS, Color(1, 1, 1, 0.8))
			draw_circle(pc, PORT_RADIUS, Color(0.2, 0.2, 0.3, 1), false, 1.5)
func _draw_oval(rect: Rect2, color: Color):
	_draw_my_ellipse(rect.get_center(), rect.size * 0.5, color)
	draw_arc(rect.get_center(), rect.size.x * 0.5, 0, TAU, 64, color.darkened(0.3), 2.0)

func _draw_rounded_rect(rect: Rect2, color: Color):
	var radius := 6.0
	var darker := color.darkened(0.3)
	draw_rect(rect, color)
	draw_line(rect.position + Vector2(radius, 0), rect.position + Vector2(rect.size.x - radius, 0), darker, 2.0)
	draw_line(rect.position + Vector2(0, radius), rect.position + Vector2(0, rect.size.y - radius), darker, 2.0)
	draw_line(rect.position + Vector2(rect.size.x, radius), rect.position + Vector2(rect.size.x, rect.size.y - radius), darker, 2.0)
	draw_line(rect.position + Vector2(radius, rect.size.y), rect.position + Vector2(rect.size.x - radius, rect.size.y), darker, 2.0)

func _draw_diamond(rect: Rect2, color: Color):
	var points := PackedVector2Array([
		Vector2(rect.position.x + rect.size.x * 0.5, rect.position.y),
		Vector2(rect.end.x, rect.position.y + rect.size.y * 0.5),
		Vector2(rect.position.x + rect.size.x * 0.5, rect.end.y),
		Vector2(rect.position.x, rect.position.y + rect.size.y * 0.5),
	])
	draw_colored_polygon(points, color)
	draw_polyline(points, color.darkened(0.3), 2.0, true)
	draw_line(points[0], points[2], color.darkened(0.3), 2.0)
	draw_line(points[1], points[3], color.darkened(0.3), 2.0)

func _draw_parallelogram(rect: Rect2, color: Color):
	var skew := 16.0
	var points := PackedVector2Array([
		Vector2(rect.position.x + skew, rect.position.y),
		Vector2(rect.end.x, rect.position.y),
		Vector2(rect.end.x - skew, rect.end.y),
		Vector2(rect.position.x, rect.end.y),
	])
	draw_colored_polygon(points, color)
	draw_polyline(points, color.darkened(0.3), 2.0, true)

func _draw_my_ellipse(center: Vector2, radii: Vector2, color: Color):
	var points := PackedVector2Array()
	var steps := 32
	for i in range(steps):
		var a := TAU * i / steps
		points.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	draw_colored_polygon(points, color)
	for i in range(steps):
		var a := TAU * i / steps
		var a2 := TAU * (i + 1) / steps
		draw_line(center + Vector2(cos(a) * radii.x, sin(a) * radii.y),
			center + Vector2(cos(a2) * radii.x, sin(a2) * radii.y), color.darkened(0.3), 2.0)

func _gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed:
		var port = get_port_at(event.position)
		if port >= 0:
			port_clicked.emit(port)
			accept_event()
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			selected.emit()
			dragging = true
			drag_offset = event.position
			accept_event()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			delete_requested.emit()
			accept_event()
	if event is InputEventMouseMotion:
		var prev = hovered_port
		hovered_port = get_port_at(event.position)
		if hovered_port != prev:
			queue_redraw()
	if event is InputEventMouseButton and not event.pressed and dragging:
		dragging = false
	if event is InputEventMouseMotion and dragging:
		var old_pos = position
		position += event.position - drag_offset
		var frame_delta = position - old_pos
		moved.emit()
		drag_moved.emit(frame_delta)
