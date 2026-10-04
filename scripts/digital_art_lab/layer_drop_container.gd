extends VBoxContainer

var drop_handler: Callable

func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
	return typeof(data) == TYPE_DICTIONARY and data.has("layer_index")

func _drop_data(_pos: Vector2, data: Variant):
	if drop_handler.is_valid():
		var target := _child_at(get_global_mouse_position())
		if target >= 0:
			drop_handler.call(data.layer_index, target)

func _child_at(pos: Vector2) -> int:
	for i in get_child_count():
		if get_child(i).get_global_rect().has_point(pos):
			return i
	return -1
