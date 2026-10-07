extends Control

## Layers docker (plan Task 5): the composition stack as an ordered list of
## "name — 2D/3D" rows driven by WorldController.layer_summaries(), plus the
## reorder row (↑ ↓ ⤒ ⤓ ⇧ ⇩), the CRUD row (Add/Duplicate/Rename/Delete) and
## the eye/lock toggles for the selection. Every interaction emits a typed
## signal the lab root routes into the WorldController, so the panel DRIVES
## the stack — it is a passive mirror only for rendering.
##
## Keyboard (same _unhandled_input pattern as the root's hotkeys): `[`/`]`
## step the order, H hides, L locks the selection. A focused LineEdit
## swallows its own keys first, so typing still works.
##
## Rebuilds free() old rows instead of queue_free(): set_layers runs during
## objects_changed emission, and tests count rows in the same frame — queued
## frees would leave stale rows visible until the next frame.

signal layer_selected(object_id: String)
signal add_requested
signal delete_requested(object_id: String)
signal duplicate_requested(object_id: String)
signal rename_requested(object_id: String, name: String)
signal visibility_toggled(object_id: String, visible: bool)
signal lock_toggled(object_id: String, locked: bool)
signal move_up_requested(object_id: String)
signal move_down_requested(object_id: String)
signal to_front_requested(object_id: String)
signal to_back_requested(object_id: String)
signal forward_requested(object_id: String)
signal backward_requested(object_id: String)

var _selected_id := ""
## Id -> summary, refreshed on set_layers. Lets set_selected and the keyboard
## shortcuts re-sync eye/lock state without another round-trip.
var _summaries: Dictionary = {}

@onready var layer_list: VBoxContainer = %LayerList
@onready var move_up_button: Button = %MoveUpButton
@onready var move_down_button: Button = %MoveDownButton
@onready var to_front_button: Button = %ToFrontButton
@onready var to_back_button: Button = %ToBackButton
@onready var forward_button: Button = %ForwardButton
@onready var backward_button: Button = %BackwardButton
@onready var add_button: Button = %AddButton
@onready var duplicate_button: Button = %DuplicateButton
@onready var rename_button: Button = %RenameButton
@onready var delete_button: Button = %DeleteButton
@onready var rename_field: LineEdit = %RenameField
@onready var visible_toggle: CheckButton = %VisibleToggle
@onready var lock_toggle: CheckButton = %LockToggle


func set_layers(summaries: Array[Dictionary]) -> void:
	_refresh_summaries(summaries)
	_rebuild()
	_refresh_state()


func set_selected(object_id: String) -> void:
	_selected_id = object_id
	_refresh_state()


## Keyboard shortcuts while the docker is visible: [/] step the order, H/L
## toggle hide/lock on the selection. Echo keys and focused-GUI keys pass.
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_BRACKETLEFT:
			if _selected_id != "":
				move_up_requested.emit(_selected_id)
				get_viewport().set_input_as_handled()
		KEY_BRACKETRIGHT:
			if _selected_id != "":
				move_down_requested.emit(_selected_id)
				get_viewport().set_input_as_handled()
		KEY_H:
			var s := _summary_for(_selected_id)
			if not s.is_empty():
				visibility_toggled.emit(_selected_id, not bool(s.get("visible", true)))
				get_viewport().set_input_as_handled()
		KEY_L:
			var s := _summary_for(_selected_id)
			if not s.is_empty():
				lock_toggled.emit(_selected_id, not bool(s.get("locked", false)))
				get_viewport().set_input_as_handled()


func _refresh_summaries(summaries: Array[Dictionary]) -> void:
	_summaries.clear()
	for s in summaries:
		if s.is_empty():
			continue
		_summaries[str(s.get("id", ""))] = s
	# A selection whose row vanished (deleted, replaced) must not leave stale
	# button state; the world still reports its own selection and will resync.
	if _selected_id != "" and not _summaries.has(_selected_id):
		_selected_id = ""


func _summary_for(object_id: String) -> Dictionary:
	var v: Variant = _summaries.get(object_id, {})
	return {} if v == null else v as Dictionary


func _rebuild() -> void:
	for child in layer_list.get_children():
		child.free()
	for object_id in _summaries:
		var s := _summary_for(object_id)
		var b := Button.new()
		b.text = "%s — %s" % [str(s.get("display_name", object_id)),
			str(s.get("element_type", "2d")).to_upper()]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(0, 40)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_on_layer_pressed.bind(object_id))
		layer_list.add_child(b)


func _refresh_state() -> void:
	var i := 0
	for object_id in _summaries:
		var row := layer_list.get_child(i) as Button
		row.button_pressed = _selected_id == object_id
		i += 1
	var sel := _summary_for(_selected_id)
	visible_toggle.set_pressed_no_signal(bool(sel.get("visible", true)))
	lock_toggle.set_pressed_no_signal(bool(sel.get("locked", false)))
	var has := _selected_id != "" and not sel.is_empty()
	for b in [move_up_button, move_down_button, to_front_button, to_back_button,
			forward_button, backward_button, duplicate_button, rename_button, delete_button]:
		b.disabled = not has
	visible_toggle.disabled = not has
	lock_toggle.disabled = not has
	add_button.disabled = false


func _on_layer_pressed(object_id: String) -> void:
	_selected_id = object_id
	layer_selected.emit(object_id)


func _on_add_pressed() -> void:
	add_requested.emit()


func _on_duplicate_pressed() -> void:
	if _selected_id != "":
		duplicate_requested.emit(_selected_id)


func _on_rename_pressed() -> void:
	if _selected_id == "":
		return
	rename_requested.emit(_selected_id, rename_field.text.strip_edges())
	rename_field.clear()


func _on_delete_pressed() -> void:
	if _selected_id != "":
		delete_requested.emit(_selected_id)


func _on_visible_toggled(pressed: bool) -> void:
	if _selected_id != "":
		visibility_toggled.emit(_selected_id, pressed)


func _on_lock_toggled(pressed: bool) -> void:
	if _selected_id != "":
		lock_toggled.emit(_selected_id, pressed)


func _on_move_up_pressed() -> void:
	if _selected_id != "":
		move_up_requested.emit(_selected_id)


func _on_move_down_pressed() -> void:
	if _selected_id != "":
		move_down_requested.emit(_selected_id)


func _on_to_front_pressed() -> void:
	if _selected_id != "":
		to_front_requested.emit(_selected_id)


func _on_to_back_pressed() -> void:
	if _selected_id != "":
		to_back_requested.emit(_selected_id)


func _on_forward_pressed() -> void:
	if _selected_id != "":
		forward_requested.emit(_selected_id)


func _on_backward_pressed() -> void:
	if _selected_id != "":
		backward_requested.emit(_selected_id)