extends Control

const BG_COLOR := Color(0.08, 0.1, 0.18, 1)
const GRID_COLOR := Color(0.2, 0.25, 0.35, 0.3)
const LAB_W := 848
const LAB_H := 540
const SLOT_COLOR := Color(0.15, 0.2, 0.3, 0.5)

var editor: FlowchartEditor
var _gizmo_layer: Control

var puzzle_slots: Array[Dictionary] = []

func redraw():
	queue_redraw()
	if _gizmo_layer:
		_gizmo_layer.queue_redraw()
		move_child(_gizmo_layer, get_child_count() - 1)

func _ready():
	_gizmo_layer = Control.new()
	_gizmo_layer.name = "GizmoLayer"
	_gizmo_layer.set_script(preload("res://scripts/gizmo_layer.gd"))
	_gizmo_layer.parent_ref = self
	_gizmo_layer.mouse_filter = MOUSE_FILTER_IGNORE
	_gizmo_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_gizmo_layer)
	move_child(_gizmo_layer, get_child_count() - 1)

func _gizmo_draw(target: Control):
	if not editor or not editor.show_gizmo: return
	if editor._selected_nodes.size() > 0 and not editor._rubber_active:
		_draw_move_gizmo_on(target)

func _draw():
	if not editor: return
	draw_rect(Rect2(Vector2.ZERO, size), BG_COLOR)
	var gs := 20
	for x in range(0, int(size.x), gs):
		draw_line(Vector2(x, 0), Vector2(x, size.y), GRID_COLOR)
	for y in range(0, int(size.y), gs):
		draw_line(Vector2(0, y), Vector2(size.x, y), GRID_COLOR)

	# Lab workspace boundary reference
	var lab_rect := Rect2(0, 0, LAB_W, LAB_H)
	draw_rect(lab_rect, Color(0.3, 0.6, 1.0, 0.08))
	draw_rect(lab_rect, Color(0.3, 0.6, 1.0, 0.25), false, 1.0)
	var font := ThemeDB.fallback_font
	var fs := ThemeDB.fallback_font_size
	draw_string(font, Vector2(4, fs + 2),
		"Lab Workspace (%d x %d)" % [LAB_W, LAB_H], HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
		Color(0.3, 0.6, 1.0, 0.4))

	# Slot placeholders — skip occupied slots (like lab), draw empty ones as guide
	var occupied := {}
	if editor:
		for n in editor._nodes:
			occupied[n.node_id] = true
	for slot in puzzle_slots:
		var sx := slot.get("pos_x", 0) as float
		var sy := slot.get("pos_y", 0) as float
		var sw := slot.get("width", 140) as float
		var sh := slot.get("height", 50) as float
		var gs2 := 20.0
		sx = round(sx / gs2) * gs2
		sy = round(sy / gs2) * gs2
		var sid: String = slot.get("id", "")
		if occupied.get(sid, false):
			continue
		var rect := Rect2(sx, sy, sw, sh)
		draw_rect(rect, SLOT_COLOR)
		draw_rect(rect, Color(0.1, 0.14, 0.21, 0.6), false, 2.0)
		var label: String = slot.get("label", "???")
		var tc := Color(0.4, 0.5, 0.7, 0.6)
		draw_string(font, Vector2(sx + 8, sy + sh * 0.5 + fs * 0.35),
			label, HORIZONTAL_ALIGNMENT_CENTER, sw - 16, fs, tc)

	for ci in editor._connections.size():
		var conn = editor._connections[ci]
		var fn = editor._find_node(conn.from_node)
		var tn = editor._find_node(conn.to_node)
		if not fn or not tn: continue
		var fp = fn.get_port_center(conn.get("from_port", FlowchartEditorNode.Port.BOTTOM))
		var tp = tn.get_port_center(conn.get("to_port", FlowchartEditorNode.Port.TOP))
		var a = fp - global_position
		var b = tp - global_position
		var mid_y = (a.y + b.y) * 0.5
		var segs: Array = [[a, Vector2(a.x, mid_y)]]
		if abs(a.x - b.x) > 4:
			segs.append([Vector2(a.x, mid_y), Vector2(b.x, mid_y)])
		segs.append([Vector2(b.x, mid_y), b])
		var is_hover := ci == editor._hovered_connection
		var conn_col := Color(0.2, 0.8, 1.0, 0.9)
		var conn_glw := Color(0.2, 0.8, 1.0, 0.2)
		if is_hover:
			conn_col = Color(1.0, 0.3, 0.3, 1.0)
			conn_glw = Color(1.0, 0.3, 0.3, 0.35)
		for s in segs:
			draw_line(s[0], s[1], conn_glw, 6.0)
			draw_line(s[0], s[1], conn_col, 3.0)
		var dir := Vector2(0, 1)
		if abs(a.x - b.x) > 4:
			var last = segs[segs.size() - 1]
			dir = (last[1] - last[0]).normalized()
		var arr_len := 8.0
		var arr_w := 4.0
		var perp := Vector2(-dir.y, dir.x)
		draw_line(b, b + dir * -arr_len + perp * arr_w, conn_col, 2.5)
		draw_line(b, b + dir * -arr_len - perp * arr_w, conn_col, 2.5)
		var clbl: String = conn.get("label", "")
		if not clbl.is_empty():
			var mid: Vector2 = a + (b - a) * 0.5
			if is_hover:
				draw_string(ThemeDB.fallback_font, mid + Vector2(4, -4), clbl,
					HORIZONTAL_ALIGNMENT_LEFT, -1, ThemeDB.fallback_font_size, Color(1, 1, 1, 0.9))
			else:
				draw_string(ThemeDB.fallback_font, mid + Vector2(4, -4), clbl,
					HORIZONTAL_ALIGNMENT_LEFT, -1, ThemeDB.fallback_font_size, Color(1, 1, 0.7, 0.85))

	if editor._dragging_port:
		var drag_col := Color(1, 1, 1, 0.7)
		var drag_glow := Color(1, 1, 1, 0.15)
		var drag_from = editor._dragging_port.get_port_center(editor._dragging_port_idx) - global_position
		draw_line(drag_from, editor._drag_line_to, drag_glow, 6.0)
		draw_line(drag_from, editor._drag_line_to, drag_col, 3.0)

	if editor._rubber_active:
		var r := Rect2(editor._rubber_start, Vector2.ZERO)
		r = r.expand(editor._rubber_end)
		draw_rect(r, Color(0.3, 0.6, 1.0, 0.1))
		draw_rect(r, Color(0.3, 0.6, 1.0, 0.6), false, 1.5)

func _draw_move_gizmo_on(target: Control):
	var gz := editor._get_gizmo_center()
	if gz == Vector2.ZERO: return
	var gs := 80.0
	var ah := 9.0
	var cx := gz.x
	var cy := gz.y
	var hp := editor._gizmo_hover
	var dg := editor._gizmo_drag
	var y_col := Color(0.2, 1.0, 0.4, 0.9)
	var y_glow := Color(0.2, 1.0, 0.4, 0.15)
	var y_w := 3.0
	var y_gw := 8.0
	if dg == 2 or hp == 2:
		y_col = Color(0.4, 1.0, 0.6, 1.0)
		y_glow = Color(0.2, 1.0, 0.4, 0.3)
		y_w = 4.5
		y_gw = 12.0
	target.draw_line(Vector2(cx, cy), Vector2(cx, cy - gs), y_glow, y_gw)
	target.draw_line(Vector2(cx, cy), Vector2(cx, cy - gs), y_col, y_w)
	target.draw_line(Vector2(cx, cy - gs), Vector2(cx - ah * 0.5, cy - gs + ah), y_col, 2.5)
	target.draw_line(Vector2(cx, cy - gs), Vector2(cx + ah * 0.5, cy - gs + ah), y_col, 2.5)
	var font := ThemeDB.fallback_font
	var fsz := ThemeDB.fallback_font_size
	target.draw_string(font, Vector2(cx + 3, cy - gs + fsz * 0.35), "Y", HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, y_col)
	var x_col := Color(1.0, 0.6, 0.1, 0.9)
	var x_glow := Color(1.0, 0.6, 0.1, 0.15)
	var x_w := 3.0
	var x_gw := 8.0
	if dg == 1 or hp == 1:
		x_col = Color(1.0, 0.8, 0.3, 1.0)
		x_glow = Color(1.0, 0.6, 0.1, 0.3)
		x_w = 4.5
		x_gw = 12.0
	target.draw_line(Vector2(cx, cy), Vector2(cx + gs, cy), x_glow, x_gw)
	target.draw_line(Vector2(cx, cy), Vector2(cx + gs, cy), x_col, x_w)
	target.draw_line(Vector2(cx + gs, cy), Vector2(cx + gs - ah, cy - ah * 0.5), x_col, 2.5)
	target.draw_line(Vector2(cx + gs, cy), Vector2(cx + gs - ah, cy + ah * 0.5), x_col, 2.5)
	target.draw_string(font, Vector2(cx + gs + 3, cy + fsz * 0.35), "X", HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, x_col)
	var hs := 4.0
	var c_col := Color(1, 1, 1, 0.9)
	if dg == 0 or hp == 0:
		c_col = Color(1, 1, 1, 1.0)
		hs = 6.0
	target.draw_rect(Rect2(cx - hs, cy - hs, hs * 2, hs * 2), c_col)

func _gui_input(event: InputEvent):
	if editor:
		editor._on_canvas_input(event)
		if event is InputEventMouseMotion:
			editor._on_canvas_hover(event.position)
		elif event is InputEventMouseButton and not event.pressed:
			editor._on_canvas_hover(event.position)
