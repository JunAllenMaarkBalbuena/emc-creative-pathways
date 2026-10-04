class_name FlowchartNode
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

var node_type: int = NodeType.PROCESS:
	set(v):
		node_type = v
		queue_redraw()

var label_text: String = "":
	set(v):
		label_text = v
		queue_redraw()

var is_ghost := false
var is_highlighted := false
var is_wrong := false

const NODE_WIDTH := 140.0
const NODE_HEIGHT := 50.0

func _init():
	custom_minimum_size = Vector2(NODE_WIDTH, NODE_HEIGHT)
	mouse_filter = MOUSE_FILTER_STOP

func _get_drag_data(_at_position: Vector2):
	var preview := FlowchartNode.new()
	preview.node_type = node_type
	preview.is_ghost = true
	preview.size = Vector2(NODE_WIDTH, NODE_HEIGHT)
	preview.label_text = label_text
	set_drag_preview(preview)
	return {"type": "flowchart_node", "node_type": node_type}

func _draw():
	if is_ghost:
		_draw_ghost()
		return

	var rect := Rect2(Vector2.ZERO, size)
	var color: Color = TYPE_COLORS.get(node_type, Color.WHITE)

	if is_wrong:
		color = Color("#e74c3c")

	match node_type:
		NodeType.START, NodeType.END:
			_oval_shape(rect, color)
		NodeType.PROCESS:
			_rounded_shape(rect, color)
		NodeType.DECISION:
			_diamond_shape(rect, color)
		NodeType.INPUT_OUTPUT:
			_parallelogram_shape(rect, color)

	if is_highlighted:
		draw_rect(rect, Color(1, 1, 0, 0.3), false, 3.0)

	var text_color := Color.WHITE
	var display_text: String = label_text if not label_text.is_empty() else TYPE_LABELS.get(node_type, "")
	var font := ThemeDB.fallback_font
	var font_size := ThemeDB.fallback_font_size
	var text_pos := Vector2(rect.position.x + 8, rect.position.y + rect.size.y * 0.5 + font_size * 0.35)
	draw_string(font, text_pos, display_text, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 16, font_size, text_color)

func _oval_shape(rect: Rect2, color: Color):
	var center := rect.get_center()
	var radii := rect.size * 0.5
	var points := PackedVector2Array()
	var steps := 32
	for i in range(steps):
		var a := TAU * i / steps
		points.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	draw_colored_polygon(points, color)
	for i in range(steps):
		var a := TAU * i / steps
		var a2 := TAU * (i + 1) / steps
		var p1 = center + Vector2(cos(a) * radii.x, sin(a) * radii.y)
		var p2 = center + Vector2(cos(a2) * radii.x, sin(a2) * radii.y)
		draw_line(p1, p2, color.darkened(0.3), 2.0)

func _rounded_shape(rect: Rect2, color: Color):
	var radius := 6.0
	var darker := color.darkened(0.3)
	draw_rect(rect, color)
	draw_line(rect.position + Vector2(radius, 0), rect.position + Vector2(rect.size.x - radius, 0), darker, 2.0)
	draw_line(rect.position + Vector2(0, radius), rect.position + Vector2(0, rect.size.y - radius), darker, 2.0)
	draw_line(rect.position + Vector2(rect.size.x, radius), rect.position + Vector2(rect.size.x, rect.size.y - radius), darker, 2.0)
	draw_line(rect.position + Vector2(radius, rect.size.y), rect.position + Vector2(rect.size.x - radius, rect.size.y), darker, 2.0)

func _diamond_shape(rect: Rect2, color: Color):
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

func _parallelogram_shape(rect: Rect2, color: Color):
	var skew := 16.0
	var points := PackedVector2Array([
		Vector2(rect.position.x + skew, rect.position.y),
		Vector2(rect.end.x, rect.position.y),
		Vector2(rect.end.x - skew, rect.end.y),
		Vector2(rect.position.x, rect.end.y),
	])
	draw_colored_polygon(points, color)
	draw_polyline(points, color.darkened(0.3), 2.0, true)

func _draw_ghost():
	var rect := Rect2(Vector2.ZERO, size)
	var color: Color = TYPE_COLORS.get(node_type, Color.WHITE)
	color.a = 0.3
	draw_rect(rect, color)
	draw_rect(rect, color, false, 1.0)
