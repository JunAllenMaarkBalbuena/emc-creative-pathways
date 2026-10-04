class_name FlowchartWorkspace
extends Control

signal puzzle_changed
signal puzzle_completed
signal wrong_drop_attempted

var puzzle_data: FlowchartPuzzleData
var placed_nodes: Dictionary = {}
var _slot_rects: Dictionary = {}
var _zoom := 1.0
var _offset := Vector2.ZERO
var _line_start: String = ""
var _line_end: Vector2
var _is_drawing_line := false

const GRID_SIZE := 20
const ROW_SPACING := 60   # slot height (50) + uniform gap (10)
const TOP_PADDING := 10   # padding from workspace top
const GRID_COLOR := Color(0.2, 0.25, 0.35, 0.3)
const BG_COLOR := Color(0.08, 0.1, 0.18, 1)
const SLOT_COLOR := Color(0.15, 0.2, 0.3, 0.5)
const SLOT_HOVER_COLOR := Color(0.2, 0.3, 0.45, 0.7)
const LINE_COLOR := Color(0.4, 0.7, 1.0, 0.8)
const CORRECT_COLOR := Color(0.18, 0.9, 0.4, 0.9)
const WRONG_COLOR := Color(0.9, 0.2, 0.2, 0.9)

func _draw():
	_draw_grid()
	_draw_slots()
	_draw_connections()
	if _is_drawing_line:
		draw_line(_get_slot_top_center(_line_start), _line_end, LINE_COLOR, 2.0)

func _draw_grid():
	draw_rect(Rect2(Vector2.ZERO, size), BG_COLOR)
	var gs := GRID_SIZE * _zoom
	for x in range(0, int(size.x), int(gs)):
		draw_line(Vector2(x, 0), Vector2(x, size.y), GRID_COLOR)
	for y in range(0, int(size.y), int(gs)):
		draw_line(Vector2(0, y), Vector2(size.x, y), GRID_COLOR)

func _draw_slots():
	if puzzle_data == null:
		return
	for slot in puzzle_data.slots:
		var rect := _get_slot_rect(slot)
		var color := SLOT_COLOR
		var sid: String = slot.get("id", "")
		if sid in placed_nodes:
			continue
		draw_rect(rect, color)
		draw_rect(rect, Color(color.r * 0.7, color.g * 0.7, color.b * 0.7, color.a * 1.2), false, 2.0)
		var label: String = slot.get("label", "???")
		var font := ThemeDB.fallback_font
		var fs := ThemeDB.fallback_font_size
		var tc := Color(0.4, 0.5, 0.7, 0.6)
		var tp := Vector2(rect.position.x + 8, rect.position.y + rect.size.y * 0.5 + fs * 0.35)
		draw_string(font, tp, label, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 16, fs, tc)

func _draw_connections():
	if puzzle_data == null:
		return
	for c in puzzle_data.connections:
		var from_id: String = c.get("from", "")
		var to_id: String = c.get("to", "")
		if from_id in placed_nodes and to_id in placed_nodes:
			var from_pos := _get_node_port(placed_nodes[from_id], from_id, c)
			var to_pos := _get_node_port(placed_nodes[to_id], to_id, c, true)
			var mid_y := from_pos.y

			if from_pos.y != to_pos.y:
				if to_pos.y < from_pos.y:
					mid_y = from_pos.y + 25
				else:
					mid_y = (from_pos.y + to_pos.y) * 0.5
			draw_line(from_pos, Vector2(from_pos.x, mid_y), LINE_COLOR, 2.0)

			if abs(from_pos.x - to_pos.x) > 4:
				draw_line(Vector2(from_pos.x, mid_y), Vector2(to_pos.x, mid_y), LINE_COLOR, 2.0)

			draw_line(Vector2(to_pos.x, mid_y), to_pos, LINE_COLOR, 2.0)
			draw_arrow(Vector2(to_pos.x, to_pos.y - 10), to_pos, LINE_COLOR)
			var branch_label: String = c.get("label", "")
			if not branch_label.is_empty():
				var lbl_pos := Vector2(from_pos.x + 8, mid_y - 4)
				var font := ThemeDB.fallback_font
				var fs := ThemeDB.fallback_font_size
				draw_string(font, lbl_pos, branch_label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 0, 0.9))

func draw_arrow(from: Vector2, to: Vector2, color: Color):
	var angle := from.angle_to_point(to)
	var arrow_len := 8.0
	var p1 := to + Vector2(cos(angle + 2.5), sin(angle + 2.5)) * arrow_len
	var p2 := to + Vector2(cos(angle - 2.5), sin(angle - 2.5)) * arrow_len
	draw_line(to, p1, color, 2.0)
	draw_line(to, p2, color, 2.0)

func setup(data: FlowchartPuzzleData):
	puzzle_data = data
	placed_nodes.clear()
	_slot_rects.clear()
	for child in get_children():
		if child is FlowchartNode:
			child.queue_free()
	for slot in data.slots:
		if slot.get("prefilled", false):
			var sid: String = slot.get("id", "")
			var ntype: int = slot.get("correct_type", FlowchartNode.NodeType.PROCESS)
			var drop_pos := _get_slot_rect(slot).position + Vector2(1, 1)
			var label: String = slot.get("label", "")
			_direct_place(sid, ntype, drop_pos, label)
	queue_redraw()

func _normalize_positions():
	if puzzle_data == null or puzzle_data.slots.is_empty():
		return
	var slots = puzzle_data.slots
	var sorted = slots.duplicate()
	sorted.sort_custom(func(a, b): return a.get("pos_y", 0) < b.get("pos_y", 0))
	var rows := []
	var cur_y := -1000
	for slot in sorted:
		var sy = slot.get("pos_y", 0)
		if abs(sy - cur_y) > 20:
			rows.append([])
			cur_y = sy
		rows[rows.size() - 1].append(slot)
	for i in range(rows.size()):
		var row_y = i * ROW_SPACING + TOP_PADDING
		for slot in rows[i]:
			slot["pos_y"] = row_y
	var min_x := INF
	var max_x := -INF
	for slot in slots:
		var sx = slot.get("pos_x", 0)
		if sx < min_x: min_x = sx
		if sx > max_x: max_x = sx
	var avail_w = size.x if size.x > 0 else 848.0
	var cur_center = (min_x + max_x) / 2.0
	var shift = round((avail_w / 2.0 - cur_center) / GRID_SIZE) * GRID_SIZE
	for slot in slots:
		slot["pos_x"] = slot.get("pos_x", 0) + shift

func _get_slot_rect(slot: Dictionary) -> Rect2:
	var sx: float = slot.get("pos_x", 0) * _zoom + _offset.x
	var sy: float = slot.get("pos_y", 0) * _zoom + _offset.y
	var sw: float = (slot.get("width", 140)) * _zoom
	var sh: float = (slot.get("height", 50)) * _zoom
	var gs := GRID_SIZE * _zoom
	sx = round(sx / gs) * gs
	sy = round(sy / gs) * gs
	return Rect2(sx, sy, sw, sh)

func _get_slot_id_at(pos: Vector2) -> String:
	if puzzle_data == null:
		return ""
	for slot in puzzle_data.slots:
		var rect := _get_slot_rect(slot)
		if rect.has_point(pos):
			return slot.get("id", "")
	return ""

func _get_slot_top_center(slot_id: String) -> Vector2:
	var slot := puzzle_data.get_slot(slot_id)
	if slot.is_empty():
		return Vector2.ZERO
	var rect := _get_slot_rect(slot)
	return Vector2(rect.position.x + rect.size.x * 0.5, rect.position.y)

func _get_port_position(node: FlowchartNode, port: int) -> Vector2:
	match port:
		0: return node.position + Vector2(node.size.x * 0.5, 0)           # TOP
		1: return node.position + Vector2(node.size.x * 0.5, node.size.y)  # BOTTOM
		2: return node.position + Vector2(0, node.size.y * 0.5)            # LEFT
		3: return node.position + Vector2(node.size.x, node.size.y * 0.5)  # RIGHT
	return node.position + Vector2(node.size.x * 0.5, node.size.y)

func _get_node_port(node: FlowchartNode, slot_id: String, conn: Dictionary, is_input := false) -> Vector2:
	if is_input:
		return _get_port_position(node, 0)
	var slot := puzzle_data.get_slot(slot_id)
	var st: int = slot.get("correct_type", FlowchartNode.NodeType.PROCESS)
	if st == FlowchartNode.NodeType.DECISION:
		var label: String = conn.get("label", "")
		if label.to_lower() == "yes":
			return _get_port_position(node, slot.get("yes_port", 3))
		elif label.to_lower() == "no":
			return _get_port_position(node, slot.get("no_port", 2))
	return _get_port_position(node, int(conn.get("from_port", 1)))

func can_drop_at(pos: Vector2) -> bool:
	var sid := _get_slot_id_at(pos)
	if sid.is_empty() or sid in placed_nodes:
		return false
	return true

func drop_node_at(node_type: int, pos: Vector2) -> bool:
	var sid := _get_slot_id_at(pos)
	if sid.is_empty() or sid in placed_nodes:
		return false
	var slot := puzzle_data.get_slot(sid)
	if slot.is_empty():
		return false
	var expected: int = slot.get("correct_type", -1)
	if expected != -1 and expected != node_type:
		wrong_drop_attempted.emit()
		return false
	var node := FlowchartNode.new()
	node.node_type = node_type
	var label: String = slot.get("label", "")
	node.label_text = label
	if label.is_empty():
		node.label_text = FlowchartNode.TYPE_LABELS.get(node_type, "")
	var rect := _get_slot_rect(slot)
	node.position = rect.position
	node.size = rect.size
	add_child(node)
	placed_nodes[sid] = node
	puzzle_changed.emit()
	queue_redraw()
	if _check_complete():
		puzzle_completed.emit()
	return true

func remove_node_at(pos: Vector2) -> bool:
	var sid := _get_slot_id_at(pos)
	if sid.is_empty() or not sid in placed_nodes:
		return false
	placed_nodes[sid].queue_free()
	placed_nodes.erase(sid)
	puzzle_changed.emit()
	queue_redraw()
	return true

func _direct_place(slot_id: String, node_type: int, _pos: Vector2, label: String):
	var node := FlowchartNode.new()
	node.node_type = node_type
	node.label_text = label
	var slot := puzzle_data.get_slot(slot_id)
	var rect := _get_slot_rect(slot)
	node.size = rect.size
	node.position = rect.position
	add_child(node)
	placed_nodes[slot_id] = node

func _can_drop_data(pos: Vector2, _data) -> bool:
	return can_drop_at(pos)

func _drop_data(pos: Vector2, data):
	if data is Dictionary and data.get("type") == "flowchart_node":
		drop_node_at(data["node_type"], pos)

func _check_complete() -> bool:
	if puzzle_data == null:
		return false
	for slot in puzzle_data.slots:
		var sid: String = slot.get("id", "")
		if not sid in placed_nodes:
			return false
	return true

func get_incorrect_slots() -> Array:
	var result: Array = []
	if puzzle_data == null:
		return result
	for slot in puzzle_data.slots:
		var sid: String = slot.get("id", "")
		if sid in placed_nodes:
			var node: FlowchartNode = placed_nodes[sid] as FlowchartNode
			if not puzzle_data.validate_slot(sid, node.node_type):
				result.append(sid)
	return result

func highlight_slots(slot_ids: Array):
	for sid in slot_ids:
		if sid in placed_nodes:
			placed_nodes[sid].is_highlighted = true
	queue_redraw()

func clear_highlights():
	for sid in placed_nodes:
		placed_nodes[sid].is_highlighted = false
		placed_nodes[sid].is_wrong = false
	queue_redraw()

func mark_wrong(slot_ids: Array):
	for sid in slot_ids:
		if sid in placed_nodes:
			placed_nodes[sid].is_wrong = true
	queue_redraw()

func reset():
	for sid in placed_nodes.keys():
		placed_nodes[sid].queue_free()
	placed_nodes.clear()
	clear_highlights()
	if puzzle_data:
		setup(puzzle_data)
	queue_redraw()

func get_execution_path() -> Array:
	var result: Array = []
	if puzzle_data == null:
		return result
	var slot_map: Dictionary = {}
	for slot in puzzle_data.slots:
		slot_map[slot.get("id", "")] = slot

	var visited: Dictionary = {}
	var path: Array = []
	var current_id: String = ""
	for slot in puzzle_data.slots:
		var ct: int = slot.get("correct_type", -1)
		if ct == FlowchartNode.NodeType.START:
			current_id = slot.get("id", "")
			break
	if current_id.is_empty():
		return result

	while not current_id.is_empty() and not visited.has(current_id):
		visited[current_id] = true
		path.append(current_id)
		var conns := puzzle_data.get_slot_connections(current_id)
		if conns.is_empty():
			break
		current_id = conns[0].get("to", "")

	return path
