class_name FlowchartEditor
extends Control

signal puzzle_loaded(path: String)

@export_file("*.tscn") var fallback_scene := "res://scenes/main_menu.tscn"

const CanvasScript := preload("res://scripts/programming_lab/flowchart_editor_canvas.gd")

var _nodes: Array[FlowchartEditorNode] = []
var _connections: Array[Dictionary] = []
var _file_path: String = ""
var _selected_nodes: Array[FlowchartEditorNode] = []
var _next_id := 1
var _modified := false
var _rubber_active := false
var _rubber_start := Vector2.ZERO
var _rubber_end := Vector2.ZERO
var _gizmo_drag := -1  # -1=none, 0=free, 1=x, 2=y
var _gizmo_offset := Vector2.ZERO
var _gizmo_positions: Array[Vector2] = []
var _gizmo_hover := -1  # -1=none, 0=center, 1=x, 2=y
var _hovered_connection := -1
var show_gizmo := true

@onready var canvas: CanvasScript = %Canvas
@onready var new_btn: Button = %NewBtn
@onready var load_btn: Button = %LoadBtn
@onready var save_btn: Button = %SaveBtn
@onready var save_as_btn: Button = %SaveAsBtn
@onready var test_btn: Button = %TestBtn
@onready var gizmo_btn: CheckButton = %GizmoBtn
@onready var back_btn: Button = %BackBtn
@onready var delete_btn: Button = %DeleteBtn
@onready var yes_port_option: OptionButton = %YesPortOption
@onready var no_port_option: OptionButton = %NoPortOption
@onready var conn_label_edit: LineEdit = %ConnLabelEdit
@onready var add_node_btn: Button = %AddNodeBtn
@onready var node_section: VBoxContainer = %NodeSection
@onready var node_type_option: OptionButton = %NodeTypeOption
@onready var node_label_edit: LineEdit = %NodeLabelEdit
@onready var node_prefilled: CheckBox = %NodePrefilled


@onready var title_edit: LineEdit = %TitleEdit
@onready var diff_option: OptionButton = %DiffOption
@onready var desc_edit: TextEdit = %DescEdit
@onready var ipo_input_edit: LineEdit = %IPOInput
@onready var ipo_process_edit: LineEdit = %IPOProcess
@onready var ipo_output_edit: LineEdit = %IPOOutput
@onready var hint1_edit: TextEdit = %Hint1
@onready var hint2_edit: TextEdit = %Hint2
@onready var hint3_edit: TextEdit = %Hint3
@onready var cutscene_type_option: OptionButton = %CutsceneTypeOption
@onready var cutscene_path_edit: LineEdit = %CutscenePathEdit
@onready var cutscene_fps_edit: SpinBox = %CutsceneFpsEdit
@onready var cutscene_browse_btn: Button = %CutsceneBrowseBtn
@onready var status_label: Label = %StatusLabel
@onready var pos_label: Label = %PosLabel

@onready var level_order_list: ItemList = %LevelOrderList
@onready var seq_move_up_btn: Button = %SeqMoveUpBtn
@onready var seq_move_down_btn: Button = %SeqMoveDownBtn
@onready var seq_remove_btn: Button = %SeqRemoveBtn
@onready var seq_add_btn: Button = %SeqAddBtn
@onready var seq_load_btn: Button = %SeqLoadBtn
@onready var seq_save_btn: Button = %SeqSaveBtn

@onready var pseq_path_label: Label = %PSeqPathLabel
@onready var puzzle_order_list: ItemList = %PuzzleOrderList
@onready var pseq_move_up_btn: Button = %PSeqMoveUpBtn
@onready var pseq_move_down_btn: Button = %PSeqMoveDownBtn
@onready var pseq_remove_btn: Button = %PSeqRemoveBtn
@onready var pseq_add_btn: Button = %PSeqAddBtn
@onready var pseq_select_btn: Button = %PSeqSelectBtn
@onready var pseq_save_btn: Button = %PSeqSaveBtn

const PUZZLES_DIR := "res://data/puzzles/"
const GRID_SIZE := 20
const NODE_W := 140
const NODE_H := 50

func _ready():
	canvas.editor = self
	for i in FlowchartEditorNode.NodeType.size():
		node_type_option.add_item(FlowchartEditorNode.TYPE_LABELS.get(i, "Unknown"))
	node_type_option.select(FlowchartEditorNode.NodeType.PROCESS)
	for d in 3:
		diff_option.add_item("★".repeat(d + 1) + "☆".repeat(2 - d))
	diff_option.select(0)
	node_type_option.item_selected.connect(_on_node_type_changed)
	node_label_edit.text_changed.connect(_on_node_label_changed)
	node_prefilled.toggled.connect(_on_node_prefilled_toggled)
	for pname in ["Top", "Bottom", "Left", "Right"]:
		yes_port_option.add_item(pname)
		no_port_option.add_item(pname)
	yes_port_option.selected = FlowchartEditorNode.Port.RIGHT
	no_port_option.selected = FlowchartEditorNode.Port.LEFT
	yes_port_option.visible = false
	no_port_option.visible = false
	yes_port_option.item_selected.connect(_on_yes_port_changed)
	no_port_option.item_selected.connect(_on_no_port_changed)
	conn_label_edit.visible = false
	conn_label_edit.text_submitted.connect(_on_conn_label_submitted)
	conn_label_edit.focus_exited.connect(_on_conn_label_focus_exited)
	title_edit.text_changed.connect(_on_title_changed)
	diff_option.item_selected.connect(_on_diff_changed)
	desc_edit.text_changed.connect(_on_desc_changed)
	ipo_input_edit.text_changed.connect(_on_ipo_input_changed)
	ipo_process_edit.text_changed.connect(_on_ipo_process_changed)
	ipo_output_edit.text_changed.connect(_on_ipo_output_changed)
	hint1_edit.text_changed.connect(_on_hint1_changed)
	hint2_edit.text_changed.connect(_on_hint2_changed)
	hint3_edit.text_changed.connect(_on_hint3_changed)
	cutscene_type_option.add_item("None")
	cutscene_type_option.add_item("Video")
	cutscene_type_option.selected = 0
	cutscene_type_option.item_selected.connect(_on_cutscene_type_changed)
	cutscene_path_edit.text_changed.connect(_on_cutscene_path_changed)
	cutscene_fps_edit.value_changed.connect(_on_cutscene_fps_changed)
	cutscene_browse_btn.pressed.connect(_on_cutscene_browse)
	new_btn.pressed.connect(_on_new)
	load_btn.pressed.connect(_on_load)
	save_btn.pressed.connect(_on_save)
	save_as_btn.pressed.connect(_on_save_as)
	test_btn.pressed.connect(_on_test)
	back_btn.pressed.connect(_on_back)
	delete_btn.pressed.connect(_delete_selected)
	add_node_btn.pressed.connect(_on_add_node)
	gizmo_btn.toggled.connect(_on_gizmo_toggled)
	seq_move_up_btn.pressed.connect(_seq_move_up)
	seq_move_down_btn.pressed.connect(_seq_move_down)
	seq_remove_btn.pressed.connect(_seq_remove)
	seq_add_btn.pressed.connect(_seq_add)
	seq_load_btn.pressed.connect(_seq_load)
	seq_save_btn.pressed.connect(_seq_save)
	pseq_move_up_btn.pressed.connect(_pseq_move_up)
	pseq_move_down_btn.pressed.connect(_pseq_move_down)
	pseq_remove_btn.pressed.connect(_pseq_remove)
	pseq_add_btn.pressed.connect(_pseq_add)
	pseq_select_btn.pressed.connect(_pseq_select)
	pseq_save_btn.pressed.connect(_pseq_save)
	_hide_node_properties()
	_set_status("Ready")
	if ResourceLoader.exists(_sequence_path):
		_seq_load_path(_sequence_path)
	else:
		_refresh_sequence_list()

func _set_status(msg: String):
	status_label.text = msg

func _on_gizmo_toggled(pressed: bool):
	show_gizmo = pressed
	canvas.redraw()
	_set_status("Gizmo " + ("on" if pressed else "off"))

func _select_node(node: FlowchartEditorNode, add := false):
	_gizmo_hover = -1
	canvas.mouse_default_cursor_shape = CURSOR_ARROW
	if not add:
		for n in _selected_nodes:
			n.is_selected = false
			n.queue_redraw()
		_selected_nodes.clear()
	if node and not node in _selected_nodes:
		_selected_nodes.append(node)
		node.is_selected = true
		node.queue_redraw()
	if _selected_nodes.size() == 1:
		_show_node_properties(_selected_nodes[0])
	elif _selected_nodes.size() > 1:
		_hide_node_properties()
	else:
		_hide_node_properties()

func _show_node_properties(node: FlowchartEditorNode):
	node_type_option.select(node.node_type)
	node_label_edit.text = node.label_text
	node_prefilled.button_pressed = node.is_prefilled
	var is_dec := node.node_type == FlowchartEditorNode.NodeType.DECISION
	yes_port_option.visible = is_dec
	no_port_option.visible = is_dec
	if is_dec:
		yes_port_option.selected = node.yes_port
		no_port_option.selected = node.no_port
	node_section.visible = true

func _hide_node_properties():
	node_section.visible = false

func _get_gizmo_center() -> Vector2:
	if _selected_nodes.size() == 0: return Vector2.ZERO
	var sum := Vector2.ZERO
	for n in _selected_nodes:
		sum += n.position + n.size * 0.5
	return sum / _selected_nodes.size()

func _get_gizmo_part(mpos: Vector2) -> int:
	var gz := _get_gizmo_center()
	if gz == Vector2.ZERO: return -1
	var gs := 80.0
	var hs := 6.0
	if abs(mpos.x - gz.x) < hs and abs(mpos.y - gz.y) < hs: return 0
	if abs(mpos.x - gz.x) < 10 and mpos.y < gz.y and mpos.y > gz.y - gs - 4: return 2
	if abs(mpos.y - gz.y) < 10 and mpos.x > gz.x and mpos.x < gz.x + gs + 4: return 1
	return -1

func _find_connection_at(pos: Vector2) -> int:
	for ci in _connections.size():
		var conn = _connections[ci]
		var fn = _find_node(conn.from_node)
		var tn = _find_node(conn.to_node)
		if not fn or not tn: continue
		var a = fn.get_port_center(conn.get("from_port", FlowchartEditorNode.Port.BOTTOM)) - canvas.global_position
		var b = tn.get_port_center(conn.get("to_port", FlowchartEditorNode.Port.TOP)) - canvas.global_position
		var mid_y = (a.y + b.y) * 0.5
		var segs: Array = [[a, Vector2(a.x, mid_y)]]
		if abs(a.x - b.x) > 4:
			segs.append([Vector2(a.x, mid_y), Vector2(b.x, mid_y)])
		segs.append([Vector2(b.x, mid_y), b])
		for s in segs:
			var dist = _point_to_segment_dist(pos, s[0], s[1])
			if dist < 6.0:
				return ci
	return -1

func _point_to_segment_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 == 0: return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)

func _on_canvas_input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var gp := _get_gizmo_part(canvas.get_local_mouse_position())
			if gp >= 0 and _selected_nodes.size() > 0 and show_gizmo:
				_gizmo_drag = gp
				_gizmo_offset = canvas.get_local_mouse_position()
				_gizmo_positions.clear()
				for n in _selected_nodes:
					_gizmo_positions.append(n.position)
				canvas.redraw()
				var names := ["Free", "X", "Y"]
				_set_status("Gizmo " + names[gp])
				return
			_rubber_active = true
			_rubber_start = canvas.get_local_mouse_position()
			_rubber_end = _rubber_start
			canvas.redraw()
			if not Input.is_key_pressed(KEY_SHIFT):
				_select_node(null)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			var ep = canvas.get_local_mouse_position()
			var ci := _find_connection_at(ep)
			if ci >= 0:
				_cut_connection(ci)
				return
			_create_node_at(ep)
	if event is InputEventMouseButton and not event.pressed:
		if _gizmo_drag >= 0:
			_gizmo_drag = -1
			_gizmo_positions.clear()
			_gizmo_hover = -1
			canvas.redraw()
			canvas.mouse_default_cursor_shape = CURSOR_ARROW
			_set_status("Ready")
			return
		if _rubber_active:
			_rubber_active = false
			canvas.redraw()
			var sel_rect := Rect2(_rubber_start, Vector2.ZERO)
			sel_rect = sel_rect.expand(_rubber_end)
			for n in _nodes:
				var nr := Rect2(n.position, n.size)
				if sel_rect.intersects(nr, true):
					if not n in _selected_nodes:
						_selected_nodes.append(n)
						n.is_selected = true
						n.queue_redraw()
			if _selected_nodes.size() > 0:
				_show_node_properties(_selected_nodes[0])
	if event is InputEventMouseMotion:
		if _gizmo_drag >= 0:
			var mpos := canvas.get_local_mouse_position()
			var delta := mpos - _gizmo_offset
			if _gizmo_drag == 1:
				delta.y = 0
			elif _gizmo_drag == 2:
				delta.x = 0
			for i in _selected_nodes.size():
				_selected_nodes[i].position = _gizmo_positions[i] + delta
			_modified = true
			canvas.redraw()
		elif _rubber_active:
			_rubber_end = canvas.get_local_mouse_position()
			canvas.redraw()

func _on_add_node():
	var ntype := node_type_option.selected
	var label := node_label_edit.text
	var prefilled := node_prefilled.button_pressed
	var pos := Vector2(280, 40)
	var max_y := 0
	for n in _nodes:
		if n.position.y + n.size.y > max_y:
			max_y = int(n.position.y + n.size.y)
	if max_y > 0:
		pos = Vector2(280, max_y + 80)
	_create_node_at(pos, ntype, label, prefilled)

func _create_node_at(pos: Vector2, ntype: int = -1, label: String = "", prefilled := false):
	var node := FlowchartEditorNode.new()
	node.node_id = "s" + str(_next_id)
	_next_id += 1
	node.position = _snap(pos)
	node.node_type = ntype if ntype >= 0 else FlowchartEditorNode.NodeType.PROCESS
	node.label_text = label
	node.is_prefilled = prefilled
	node.moved.connect(_on_node_moved)
	node.drag_moved.connect(_on_drag_moved.bind(node))
	node.port_clicked.connect(_on_port_clicked.bind(node))
	node.selected.connect(_on_node_selected.bind(node))
	node.delete_requested.connect(_delete_node.bind(node))
	canvas.add_child(node)
	_nodes.append(node)
	_select_node(node)
	_modified = true
	_set_status("Added " + node.node_id)
	canvas.redraw()
	if _dragging_port:
		_dragging_port = null
		_dragging_port_idx = -1
		set_process(false)

func _on_node_selected(node: FlowchartEditorNode):
	_select_node(node, Input.is_key_pressed(KEY_SHIFT))

func _delete_node(node: FlowchartEditorNode):
	if not node in _nodes:
		return
	_selected_nodes.erase(node)
	_nodes.erase(node)
	var sid = node.node_id
	_connections = _connections.filter(func(c): return c.from_node != sid and c.to_node != sid)
	node.queue_free()
	_modified = true
	_set_status("Deleted " + sid)
	canvas.redraw()

func _delete_selected():
	var to_delete = _selected_nodes.duplicate()
	for n in to_delete:
		_delete_node(n)

func _on_node_moved():
	_modified = true
	canvas.redraw()

func _on_drag_moved(delta: Vector2, node: FlowchartEditorNode):
	for n in _selected_nodes:
		if n != node:
			n.position += delta
	_modified = true
	canvas.redraw()

var _dragging_port = null
var _dragging_port_idx = -1
var _drag_line_to = Vector2.ZERO

func _on_port_clicked(port_idx: int, node: FlowchartEditorNode):
	if _dragging_port == null:
		_dragging_port = node
		_dragging_port_idx = port_idx
		_drag_line_to = node.get_port_center(port_idx) - canvas.global_position
		set_process(true)
	else:
		var target_port = node.get_port_at(node.get_local_mouse_position())
		if target_port >= 0 and node != _dragging_port:
			var from_n = _dragging_port
			var from_p = _dragging_port_idx
			var dup := false
			for c in _connections:
				if c.from_node == from_n.node_id and c.to_node == node.node_id:
					dup = true; break
			if not dup:
				var conn_label := ""
				if from_n.node_type == FlowchartEditorNode.NodeType.DECISION:
					if from_p == from_n.yes_port:
						conn_label = "Yes"
					elif from_p == from_n.no_port:
						conn_label = "No"
				_connections.append({from_node = from_n.node_id, from_port = from_p,
					to_node = node.node_id, to_port = target_port, label = conn_label})
				_bounce_node(from_n)
				_bounce_node(node)
			_modified = true
			_set_status("Connected " + from_n.node_id + " → " + node.node_id)
		_dragging_port = null
		_dragging_port_idx = -1
		set_process(false)

func _bounce_node(n: FlowchartEditorNode):
	var t := create_tween().set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	t.tween_method(func(v: float): n.scale = Vector2(v, v), 1.0, 1.15, 0.15)
	t.tween_method(func(v: float): n.scale = Vector2(v, v), 1.15, 1.0, 0.2)

func _cut_connection(ci: int):
	var conn = _connections[ci]
	var from_id = conn.from_node
	var to_id = conn.to_node
	_connections.remove_at(ci)
	_modified = true
	canvas.redraw()
	_set_status("Cut " + from_id + " → " + to_id)

func _process(_delta):
	if _dragging_port:
		_drag_line_to = canvas.get_local_mouse_position()
		canvas.redraw()

func _unhandled_input(event: InputEvent):
	if event is InputEventKey and event.pressed and _selected_nodes.size() > 0:
		var focus = get_viewport().gui_get_focus_owner()
		if focus and (focus is LineEdit or focus is TextEdit): return
		var step := 1 if event.shift_pressed else GRID_SIZE
		var dir := Vector2.ZERO
		match event.keycode:
			KEY_UP: dir = Vector2(0, -step)
			KEY_DOWN: dir = Vector2(0, step)
			KEY_LEFT: dir = Vector2(-step, 0)
			KEY_RIGHT: dir = Vector2(step, 0)
		if dir != Vector2.ZERO:
			for n in _selected_nodes:
				n.position += dir
			_modified = true
			canvas.redraw()
			get_viewport().set_input_as_handled()

func _on_canvas_hover(pos: Vector2):
	var gs := GRID_SIZE
	var snap_pos := Vector2(round(pos.x / gs) * gs, round(pos.y / gs) * gs)
	pos_label.text = "Grid: (%d, %d)" % [snap_pos.x, snap_pos.y]
	var new_hover := -1
	if show_gizmo and _selected_nodes.size() > 0 and _gizmo_drag < 0:
		new_hover = _get_gizmo_part(pos)
	if new_hover != _gizmo_hover:
		_gizmo_hover = new_hover
		canvas.redraw()
		var cursor := CURSOR_ARROW
		if new_hover == 0:
			cursor = CURSOR_MOVE
		elif new_hover == 1:
			cursor = CURSOR_HSIZE
		elif new_hover == 2:
			cursor = CURSOR_VSIZE
		canvas.mouse_default_cursor_shape = cursor
	var new_conn := _find_connection_at(pos)
	if new_conn != _hovered_connection:
		_hovered_connection = new_conn
		canvas.redraw()
		if new_conn >= 0:
			conn_label_edit.visible = true
			conn_label_edit.text = _connections[new_conn].get("label", "")
		else:
			conn_label_edit.visible = false
			conn_label_edit.text = ""

func _snap(pos: Vector2) -> Vector2:
	return Vector2(round(pos.x / GRID_SIZE) * GRID_SIZE, round(pos.y / GRID_SIZE) * GRID_SIZE)

func _find_node(sid: String) -> FlowchartEditorNode:
	for n in _nodes:
		if n.node_id == sid:
			return n
	return null

func _clear():
	for n in _nodes:
		n.queue_free()
	_nodes.clear()
	_connections.clear()
	_selected_nodes.clear()
	_next_id = 1
	_file_path = ""
	_modified = false
	canvas.puzzle_slots = []
	canvas.redraw()

func _on_save():
	if _file_path.is_empty():
		_on_save_as()
	else:
		_save(_file_path)

func _on_save_as():
	var fd := FileDialog.new()
	fd.access = FileDialog.ACCESS_RESOURCES
	fd.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	fd.add_filter("*.tres", "Flowchart Puzzle Data")
	fd.title = "Save Puzzle As"
	fd.current_dir = PUZZLES_DIR
	fd.current_file = self.to_snake(title_edit.text) + ".tres"
	fd.file_selected.connect(_save)
	fd.canceled.connect(fd.queue_free)
	add_child(fd)
	fd.popup_centered_ratio(0.5)

func _on_load():
	var fd := FileDialog.new()
	fd.access = FileDialog.ACCESS_RESOURCES
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.add_filter("*.tres", "Flowchart Puzzle Data")
	fd.title = "Load Puzzle"
	fd.current_dir = PUZZLES_DIR
	fd.file_selected.connect(load_puzzle)
	fd.canceled.connect(fd.queue_free)
	add_child(fd)
	fd.popup_centered_ratio(0.5)

func _save(path: String):
	var data := FlowchartPuzzleData.new()
	data.puzzle_id = to_snake(title_edit.text)
	data.title = title_edit.text
	data.difficulty = diff_option.selected + 1
	data.problem_description = desc_edit.text
	data.ipo_input = ipo_input_edit.text
	data.ipo_process = ipo_process_edit.text
	data.ipo_output = ipo_output_edit.text
	data.hint_level_1 = hint1_edit.text
	data.hint_level_2 = hint2_edit.text
	data.hint_level_3 = hint3_edit.text
	data.cutscene_type = 2 if cutscene_type_option.selected == 1 else 0
	data.cutscene_path = cutscene_path_edit.text
	data.cutscene_fps = cutscene_fps_edit.value
	data.slots = []
	data.palette_types = []
	data.connections = []

	var used_types := {}
	var gs := GRID_SIZE
	for n in _nodes:
		used_types[n.node_type] = true
		data.slots.append({
			id = n.node_id,
			pos_x = int(round(n.position.x / gs) * gs),
			pos_y = int(round(n.position.y / gs) * gs),
			width = int(n.size.x),
			height = int(n.size.y),
			correct_type = n.node_type,
			label = n.label_text,
			prefilled = n.is_prefilled,
			yes_port = n.yes_port,
			no_port = n.no_port,
		})
	var sorted_types: Array[int] = []
	for k in used_types.keys():
		sorted_types.append(k)
	sorted_types.sort()
	data.palette_types = sorted_types

	for c in _connections:
		data.connections.append({
			from = c.from_node,
			from_port = c.get("from_port", FlowchartEditorNode.Port.BOTTOM),
			to = c.to_node,
			to_port = c.get("to_port", FlowchartEditorNode.Port.TOP),
			label = c.get("label", ""),
		})
	data.resource_path = path
	var res := ResourceSaver.save(data, path)
	if res == OK:
		_file_path = path
		_modified = false
		_set_status("Saved to " + path.get_file())
		if _pending_test:
			_pending_test = false
			call_deferred("_switch_to_lab")
	else:
		_set_status("Save failed: " + str(res))

func load_puzzle(path: String):
	var data := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as FlowchartPuzzleData
	if not data:
		data = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as FlowchartPuzzleData
	if not data:
		_set_status("Failed to load " + path.get_file()); return
	_clear()
	_file_path = path
	title_edit.text = data.title
	diff_option.select(clampi(data.difficulty - 1, 0, 2))
	desc_edit.text = data.problem_description
	ipo_input_edit.text = data.ipo_input
	ipo_process_edit.text = data.ipo_process
	ipo_output_edit.text = data.ipo_output
	hint1_edit.text = data.hint_level_1
	hint2_edit.text = data.hint_level_2
	hint3_edit.text = data.hint_level_3
	cutscene_type_option.selected = 1 if data.cutscene_type in [1, 2] else 0
	cutscene_path_edit.text = data.cutscene_path
	cutscene_fps_edit.value = data.cutscene_fps
	for slot in data.slots:
		var pos = Vector2(slot.get("pos_x", 0), slot.get("pos_y", 0))
		_create_node_at(pos, slot.get("correct_type", FlowchartEditorNode.NodeType.PROCESS),
			slot.get("label", ""), slot.get("prefilled", false))
		_nodes[_nodes.size() - 1].position = pos
		_nodes[_nodes.size() - 1].node_id = slot.get("id", "s" + str(_next_id - 1))
		_nodes[_nodes.size() - 1].yes_port = slot.get("yes_port", FlowchartEditorNode.Port.RIGHT)
		_nodes[_nodes.size() - 1].no_port = slot.get("no_port", FlowchartEditorNode.Port.LEFT)
	for conn in data.connections:
		var fp: int = conn.get("from_port", FlowchartEditorNode.Port.BOTTOM)
		var tp: int = conn.get("to_port", FlowchartEditorNode.Port.TOP)
		var clbl: String = conn.get("label", "")
		var fn: FlowchartEditorNode = _find_node(conn.from)
		if fn and fn.node_type == FlowchartEditorNode.NodeType.DECISION:
			var clbl_lower: String = clbl.to_lower()
			if clbl_lower == "yes":
				fp = fn.yes_port
			elif clbl_lower == "no":
				fp = fn.no_port
		_connections.append({
			from_node = conn.from,
			to_node = conn.to,
			from_port = fp,
			to_port = tp,
			label = clbl,
		})
	_select_node(null)
	_modified = false
	canvas.puzzle_slots = data.slots
	canvas.redraw()
	_set_status("Loaded " + path.get_file())
	puzzle_loaded.emit(path)

func _on_new():
	if _modified:
		pass
	_clear()
	title_edit.text = "New Puzzle"
	diff_option.select(0)
	desc_edit.text = ""
	ipo_input_edit.text = ""
	ipo_process_edit.text = ""
	ipo_output_edit.text = ""
	hint1_edit.text = ""
	hint2_edit.text = ""
	hint3_edit.text = ""
	_file_path = ""
	_set_status("New puzzle")

func _on_back():
	var return_scene := LevelProgression.get_resume_scene()
	if return_scene.is_empty():
		return_scene = fallback_scene
	else:
		LevelProgression.save_spawn_position(return_scene, LevelProgression.get_resume_spawn().get("player", Vector3.ZERO), LevelProgression.get_resume_spawn().get("camera_offset", Vector3.ZERO))
		LevelProgression.clear_resume_state()
	get_tree().change_scene_to_file(return_scene)

var _pending_test := false
var _sequence_path := "res://data/sequences/game_sequence.tres"
var _sequence_ids: Array[String] = []
var _puzzle_level_path := ""
var _puzzle_seq_list: Array[FlowchartPuzzleData] = []

func _on_test():
	if _file_path.is_empty():
		_pending_test = true
		_on_save_as()
	else:
		_save(_file_path)
		call_deferred("_switch_to_lab")

func _switch_to_lab():
	if not is_inside_tree():
		return
	var tree := get_tree()
	if tree:
		tree.change_scene_to_file("res://scenes/programming_lab.tscn")

func _update_connection_ports(n: FlowchartEditorNode):
	for c in _connections:
		if c.from_node == n.node_id:
			var clbl_lower: String = c.get("label", "").to_lower()
			if clbl_lower == "yes":
				c.from_port = n.yes_port
			elif clbl_lower == "no":
				c.from_port = n.no_port
	canvas.redraw()

func _on_yes_port_changed(idx: int):
	if _selected_nodes.size() > 0:
		var n = _selected_nodes[0]
		n.yes_port = idx
		_update_connection_ports(n)
		_modified = true

func _on_no_port_changed(idx: int):
	if _selected_nodes.size() > 0:
		var n = _selected_nodes[0]
		n.no_port = idx
		_update_connection_ports(n)
		_modified = true

func _set_conn_label(text: String):
	if _hovered_connection >= 0 and _hovered_connection < _connections.size():
		_connections[_hovered_connection]["label"] = text
		_modified = true
		canvas.redraw()

func _on_conn_label_submitted(text: String):
	_set_conn_label(text)
	conn_label_edit.release_focus()

func _on_conn_label_focus_exited():
	if _hovered_connection >= 0:
		_set_conn_label(conn_label_edit.text)

func _on_node_type_changed(idx: int):
	if _selected_nodes.size() == 1:
		var n = _selected_nodes[0]
		n.node_type = idx
		if idx == FlowchartEditorNode.NodeType.DECISION:
			n.yes_port = FlowchartEditorNode.Port.RIGHT
			n.no_port = FlowchartEditorNode.Port.LEFT
		_show_node_properties(n)
		_modified = true

func _on_node_label_changed(text: String):
	if _selected_nodes.size() == 1:
		_selected_nodes[0].label_text = text
		_modified = true

func _on_node_prefilled_toggled(val: bool):
	if _selected_nodes.size() == 1:
		_selected_nodes[0].is_prefilled = val
		_modified = true

func _on_title_changed(text: String):
	_modified = true
	if not _file_path.is_empty():
		var new_id = to_snake(text)
		var dir_path = _file_path.get_base_dir()
		var new_path = dir_path + "/" + new_id + ".tres"
		if new_path != _file_path:
			_file_path = new_path
			_set_status("Auto-path: " + _file_path)

func _on_diff_changed(_idx: int): _modified = true
func _on_desc_changed(): _modified = true
func _on_ipo_input_changed(_text: String): _modified = true
func _on_ipo_process_changed(_text: String): _modified = true
func _on_ipo_output_changed(_text: String): _modified = true
func _on_hint1_changed(): _modified = true
func _on_hint2_changed(): _modified = true
func _on_hint3_changed(): _modified = true
func _on_cutscene_type_changed(_idx: int): _modified = true
func _on_cutscene_path_changed(_text: String): _modified = true
func _on_cutscene_fps_changed(_val: float): _modified = true

func _on_cutscene_browse():
	var fd := FileDialog.new()
	fd.access = FileDialog.ACCESS_RESOURCES
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.add_filter("*.ogv,*.webm", "Video files")
	fd.title = "Select cutscene video"
	fd.file_selected.connect(func(p):
		cutscene_path_edit.text = p
		cutscene_type_option.select(1)
		_modified = true
	)
	fd.canceled.connect(fd.queue_free)
	add_child(fd)
	fd.popup_centered_ratio(0.5)

func _seq_load():
	var fd := FileDialog.new()
	fd.access = FileDialog.ACCESS_RESOURCES
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.add_filter("*.tres", "GameSequence Resource")
	fd.title = "Load Level Sequence"
	fd.file_selected.connect(_seq_load_path)
	fd.canceled.connect(fd.queue_free)
	add_child(fd)
	fd.popup_centered_ratio(0.5)

func _seq_load_path(path: String):
	_sequence_path = path
	var seq = ResourceLoader.load(path) as GameSequence
	if seq == null:
		_set_status("Failed to load sequence from " + path.get_file())
		return
	_sequence_ids = seq.level_order_ids.duplicate()
	_refresh_sequence_list()
	_set_status("Loaded " + str(_sequence_ids.size()) + " levels from " + path.get_file())

func _seq_save():
	var seq := GameSequence.new()
	seq.level_order_ids = _sequence_ids.duplicate()
	seq.resource_path = _sequence_path
	var res := ResourceSaver.save(seq, _sequence_path)
	if res == OK:
		_set_status("Saved sequence to " + _sequence_path.get_file())
		_refresh_sequence_list()
	else:
		_set_status("Save failed: " + str(res))

func _refresh_sequence_list():
	level_order_list.clear()
	if _sequence_ids.is_empty():
		level_order_list.add_item("(empty - add levels below)")
		return
	for level_id in _sequence_ids:
		level_order_list.add_item(level_id)

func _seq_move_up():
	var idx := level_order_list.get_selected_items()
	if idx.size() != 1 or idx[0] <= 0:
		return
	var i := idx[0]
	var tmp := _sequence_ids[i]
	_sequence_ids[i] = _sequence_ids[i - 1]
	_sequence_ids[i - 1] = tmp
	_refresh_sequence_list()
	level_order_list.select(i - 1)

func _seq_move_down():
	var idx := level_order_list.get_selected_items()
	if idx.size() != 1 or idx[0] >= _sequence_ids.size() - 1:
		return
	var i := idx[0]
	var tmp := _sequence_ids[i]
	_sequence_ids[i] = _sequence_ids[i + 1]
	_sequence_ids[i + 1] = tmp
	_refresh_sequence_list()
	level_order_list.select(i + 1)

func _seq_remove():
	var idx := level_order_list.get_selected_items()
	if idx.size() != 1:
		return
	_sequence_ids.remove_at(idx[0])
	_refresh_sequence_list()

func _seq_add():
	var fd := FileDialog.new()
	fd.access = FileDialog.ACCESS_RESOURCES
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.add_filter("*.tres", "LevelDefinition Resource")
	fd.title = "Add Level"
	fd.current_dir = "res://data/levels/"
	fd.file_selected.connect(_seq_add_file)
	fd.canceled.connect(fd.queue_free)
	add_child(fd)
	fd.popup_centered_ratio(0.5)

func _seq_add_file(path: String):
	var level = ResourceLoader.load(path) as LevelDefinition
	if level == null or level.level_id.is_empty():
		_set_status("Selected file is not a valid LevelDefinition with a level_id.")
		return
	_sequence_ids.append(level.level_id)
	_refresh_sequence_list()
	_set_status("Added " + level.level_id)

func _pseq_select():
	var fd := FileDialog.new()
	fd.access = FileDialog.ACCESS_RESOURCES
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.add_filter("*.tres", "LevelDefinition Resource")
	fd.title = "Select Level to Edit Puzzle Order"
	fd.current_dir = "res://data/levels/"
	fd.file_selected.connect(_pseq_load_level)
	fd.canceled.connect(fd.queue_free)
	add_child(fd)
	fd.popup_centered_ratio(0.5)

func _pseq_load_level(path: String):
	var level = ResourceLoader.load(path) as LevelDefinition
	if level == null or level.level_id.is_empty():
		_set_status("Failed to load level from " + path.get_file())
		return
	_puzzle_level_path = "res://data/sequences/" + level.level_id + ".tres"
	pseq_path_label.text = _puzzle_level_path.trim_prefix("res://")
	if ResourceLoader.exists(_puzzle_level_path):
		var seq = ResourceLoader.load(_puzzle_level_path)
		if seq != null:
			var order = seq.puzzle_order
			_puzzle_seq_list = order.duplicate()
	_pseq_refresh()
	_set_status("Loaded " + str(_puzzle_seq_list.size()) + " puzzles for " + level.display_name)

func _pseq_save():
	if _puzzle_level_path.is_empty():
		_set_status("No level selected. Click Select Level... first.")
		return
	var seq := PuzzleSequence.new()
	seq.puzzle_order = _puzzle_seq_list.duplicate()
	seq.resource_path = _puzzle_level_path
	var res := ResourceSaver.save(seq, _puzzle_level_path)
	if res == OK:
		_set_status("Saved puzzle order to " + _puzzle_level_path.get_file())
	else:
		_set_status("Save failed: " + str(res))

func _pseq_refresh():
	puzzle_order_list.clear()
	if _puzzle_seq_list.is_empty():
		puzzle_order_list.add_item("(empty - add puzzles below)")
		return
	for p in _puzzle_seq_list:
		var label := p.title if not p.title.is_empty() else p.puzzle_id
		puzzle_order_list.add_item(label)

func _pseq_move_up():
	var idx := puzzle_order_list.get_selected_items()
	if idx.size() != 1 or idx[0] <= 0:
		return
	var i := idx[0]
	var tmp := _puzzle_seq_list[i]
	_puzzle_seq_list[i] = _puzzle_seq_list[i - 1]
	_puzzle_seq_list[i - 1] = tmp
	_pseq_refresh()
	puzzle_order_list.select(i - 1)

func _pseq_move_down():
	var idx := puzzle_order_list.get_selected_items()
	if idx.size() != 1 or idx[0] >= _puzzle_seq_list.size() - 1:
		return
	var i := idx[0]
	var tmp := _puzzle_seq_list[i]
	_puzzle_seq_list[i] = _puzzle_seq_list[i + 1]
	_puzzle_seq_list[i + 1] = tmp
	_pseq_refresh()
	puzzle_order_list.select(i + 1)

func _pseq_remove():
	var idx := puzzle_order_list.get_selected_items()
	if idx.size() != 1:
		return
	_puzzle_seq_list.remove_at(idx[0])
	_pseq_refresh()

func _pseq_add():
	var fd := FileDialog.new()
	fd.access = FileDialog.ACCESS_RESOURCES
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.add_filter("*.tres", "FlowchartPuzzleData Resource")
	fd.title = "Add Puzzle"
	fd.current_dir = PUZZLES_DIR
	fd.file_selected.connect(_pseq_add_file)
	fd.canceled.connect(fd.queue_free)
	add_child(fd)
	fd.popup_centered_ratio(0.5)

func _pseq_add_file(path: String):
	var puzzle = ResourceLoader.load(path) as FlowchartPuzzleData
	if puzzle == null:
		_set_status("Selected file is not a valid FlowchartPuzzleData.")
		return
	_puzzle_seq_list.append(puzzle)
	_pseq_refresh()
	_set_status("Added " + puzzle.title)

func to_snake(text: String) -> String:
	var result := ""
	for c in text:
		if c.is_valid_identifier():
			result += c
		elif c == " " or result.is_empty() or result[result.length() - 1] != "_":
			result += "_"
	while result.ends_with("_"):
		result = result.left(result.length() - 1)
	return result.to_lower()
