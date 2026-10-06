extends Control

## Storyboard panel (PLAN stage): reorder the assignment's story beats and
## confirm the arrangement. The root validates with
## assignment_manager.order_story_beats(ids) (Challenge A).

signal order_submitted(ids: Array[String])

var _beats: Array[Dictionary] = []
var _order: Array[String] = []

@onready var beat_list: VBoxContainer = %BeatList
@onready var status_label: Label = %Status

func set_beats(beats: Array[Dictionary]) -> void:
	_beats = beats
	_order.clear()
	for beat in beats:
		_order.append(str(beat.get("id", "")))
	status_label.text = ""
	_rebuild()

func mark_ok() -> void:
	status_label.text = "Order accepted. Continue!"

func set_status(text: String) -> void:
	status_label.text = text

func _rebuild() -> void:
	for child in beat_list.get_children():
		child.queue_free()
	for i in _order.size():
		beat_list.add_child(_make_row(i, _order[i]))

func _make_row(index: int, id: String) -> Control:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = "%d. %s" % [index + 1, _text_for(id)]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var up := Button.new()
	up.text = "▲"
	up.custom_minimum_size = Vector2(48, 48)
	up.tooltip_text = "Move up"
	up.pressed.connect(_on_move_up.bind(id))
	row.add_child(up)
	var down := Button.new()
	down.text = "▼"
	down.custom_minimum_size = Vector2(48, 48)
	down.tooltip_text = "Move down"
	down.pressed.connect(_on_move_down.bind(id))
	row.add_child(down)
	return row

func _text_for(id: String) -> String:
	for beat in _beats:
		if str(beat.get("id", "")) == id:
			return str(beat.get("text", id))
	return id

func _move(id: String, dir: int) -> void:
	var i := _order.find(id)
	var j := i + dir
	if i < 0 or j < 0 or j >= _order.size():
		return
	_order[i] = _order[j]
	_order[j] = id
	set_status("Press CONFIRM to check the order.")
	_rebuild()

func _on_move_up(id: String) -> void:
	_move(id, -1)

func _on_move_down(id: String) -> void:
	_move(id, 1)

func _on_confirm_pressed() -> void:
	order_submitted.emit(_order)