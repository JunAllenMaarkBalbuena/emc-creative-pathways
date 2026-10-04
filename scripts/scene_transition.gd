extends CanvasLayer

const FADE_DURATION := 0.35

var _fade_rect: ColorRect
var _is_transitioning := false

func _ready() -> void:
	layer = 200
	process_mode = Node.PROCESS_MODE_ALWAYS
	_fade_rect = ColorRect.new()
	_fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade_rect.color = Color(0, 0, 0, 0)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade_rect)

func change_scene(scene_path: String) -> void:
	if _is_transitioning or scene_path.is_empty():
		return
	_is_transitioning = true
	await _fade_to(1.0)
	_stop_all_audio()
	get_tree().change_scene_to_file(scene_path)
	await get_tree().process_frame
	await _fade_to(0.0)
	_is_transitioning = false

func _fade_to(alpha: float) -> void:
	var tween := create_tween()
	var target_color := _fade_rect.color
	target_color.a = alpha
	tween.tween_property(_fade_rect, "color", target_color, FADE_DURATION)
	await tween.finished

func _stop_all_audio() -> void:
	for player in get_tree().root.find_children("*", "AudioStreamPlayer", true, false):
		player.stop()
