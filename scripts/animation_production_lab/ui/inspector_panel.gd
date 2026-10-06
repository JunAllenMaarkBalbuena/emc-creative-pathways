extends Control

## Inspector panel (STAGING/CAMERA/LIGHTING stages): object list, position
## spinboxes, visibility toggle, delete. Emits edits typed for the root.

signal object_selected(object_id: String)
signal transform_edited(object_id: String, property: String, value: Variant)
signal visibility_toggled(object_id: String, visible: bool)
signal delete_requested(object_id: String)

var _selected_id := ""

@onready var object_list: VBoxContainer = %ObjectList
@onready var pos_x: SpinBox = %PosX
@onready var pos_y: SpinBox = %PosY
@onready var pos_z: SpinBox = %PosZ
@onready var visible_toggle: CheckButton = %VisibleToggle
@onready var delete_button: Button = %DeleteButton

func set_object_list(objects: Array[Dictionary]) -> void:
	_rebuild(objects)

func select_object(object_id: String) -> void:
	_selected_id = object_id

func set_object_data(data: Dictionary) -> void:
	if data.is_empty():
		return
	var pos: Vector3 = data.get("position", Vector3.ZERO)
	pos_x.set_value_no_signal(pos.x)
	pos_y.set_value_no_signal(pos.y)
	pos_z.set_value_no_signal(pos.z)
	visible_toggle.set_pressed_no_signal(bool(data.get("visible", true)))
	delete_button.disabled = false

func _rebuild(objects: Array[Dictionary]) -> void:
	for child in object_list.get_children():
		child.queue_free()
	for data in objects:
		var object_id := str(data.get("id", ""))
		var b := Button.new()
		b.text = "%s  (%s)" % [object_id, str(data.get("category", ""))]
		b.custom_minimum_size = Vector2(0, 44)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_on_object_pressed.bind(object_id))
		object_list.add_child(b)

func _on_object_pressed(object_id: String) -> void:
	_selected_id = object_id
	object_selected.emit(object_id)

func _on_position_changed(_value: float) -> void:
	if _selected_id == "":
		return
	var pos := Vector3(pos_x.value, pos_y.value, pos_z.value)
	transform_edited.emit(_selected_id, "position", pos)

func _on_visible_toggled(pressed: bool) -> void:
	if _selected_id == "":
		return
	visibility_toggled.emit(_selected_id, pressed)

func _on_delete_pressed() -> void:
	if _selected_id == "":
		return
	delete_requested.emit(_selected_id)
	_selected_id = ""