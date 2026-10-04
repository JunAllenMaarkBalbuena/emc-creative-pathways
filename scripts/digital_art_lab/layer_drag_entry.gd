extends Control

var layer_index: int = -1

func _get_drag_data(_pos: Vector2) -> Variant:
	var preview := ColorRect.new()
	preview.color = Color(0.25, 0.45, 0.75, 0.4)
	preview.custom_minimum_size = size
	preview.size = size
	set_drag_preview(preview)
	return {"layer_index": layer_index}
