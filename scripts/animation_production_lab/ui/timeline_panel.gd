extends Control

## Timeline panel (FRAMES/KEYFRAME/TIMING): one tap row per frame (spec §8 —
## rows, not pixel handles), add/remove, and apply the selected library asset.

signal frame_selected(index: int)
signal frame_added
signal frame_removed(index: int)
signal frame_texture_requested(index: int)

var _count := 0
var _selected := -1

@onready var frame_list: VBoxContainer = %FrameList
@onready var remove_button: Button = %RemoveFrame
@onready var use_button: Button = %UseAsset

func set_frame_count(count: int) -> void:
	_count = count
	if _selected >= _count:
		_selected = _count - 1
	_rebuild()

func _rebuild() -> void:
	for child in frame_list.get_children():
		child.queue_free()
	for i in _count:
		var b := Button.new()
		b.text = "Frame %d" % (i + 1)
		b.custom_minimum_size = Vector2(0, 44)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_on_frame_pressed.bind(i))
		frame_list.add_child(b)
	remove_button.disabled = _selected < 0
	use_button.disabled = _selected < 0

func _on_frame_pressed(index: int) -> void:
	_selected = index
	frame_selected.emit(index)
	_rebuild()

func _on_add_pressed() -> void:
	frame_added.emit()

func _on_remove_pressed() -> void:
	if _selected >= 0:
		frame_removed.emit(_selected)
		_selected = -1

func _on_use_asset_pressed() -> void:
	if _selected >= 0:
		frame_texture_requested.emit(_selected)