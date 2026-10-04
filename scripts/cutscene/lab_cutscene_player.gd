class_name LabCutscenePlayer
extends Control

signal finished

enum Type { NONE, PNG_SEQUENCE, VIDEO }

var _type := Type.NONE
var _video_player: VideoStreamPlayer
var _overlay: ColorRect
var _controls: HBoxContainer
var _pause_btn: Button
var _skip_btn: Button
var _paused := false

func _ready():
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	_overlay = ColorRect.new()
	_overlay.color = Color(0, 0, 0, 0.7)
	_overlay.mouse_filter = MOUSE_FILTER_IGNORE
	_overlay.anchors_preset = PRESET_FULL_RECT
	add_child(_overlay)
	
	# Controls overlay
	_controls = HBoxContainer.new()
	_controls.set_anchors_preset(PRESET_BOTTOM_RIGHT)
	_controls.offset_left = -180
	_controls.offset_top = -70
	_controls.offset_right = -20
	_controls.offset_bottom = -20
	_controls.mouse_filter = MOUSE_FILTER_STOP
	_controls.add_theme_constant_override("separation", 10)
	add_child(_controls)
	
	_pause_btn = Button.new()
	_pause_btn.text = "❚❚"
	_pause_btn.custom_minimum_size = Vector2(60, 40)
	_pause_btn.pressed.connect(_toggle_pause)
	_controls.add_child(_pause_btn)
	
	_skip_btn = Button.new()
	_skip_btn.text = "Skip ▶▶"
	_skip_btn.custom_minimum_size = Vector2(90, 40)
	_skip_btn.pressed.connect(_skip)
	_controls.add_child(_skip_btn)
	
	hide()

func setup(data: FlowchartPuzzleData):
	print("Cutscene setup called, type: ", data.cutscene_type, " path: ", data.cutscene_path)
	var path := data.cutscene_path
	if path.get_extension().to_lower() in ["ogv", "webm"]:
		_type = Type.VIDEO
	else:
		match data.cutscene_type:
			1:
				_type = Type.PNG_SEQUENCE
			2:
				_type = Type.VIDEO
			_:
				_type = Type.NONE
	if _type == Type.NONE:
		return
	if path.is_empty():
		return
	
	visible = true
	
	if _type == Type.VIDEO:
		_play_video(path)
	else:
		print("PNG sequence cutscenes not yet implemented, skipping")
		finished.emit()

func _play_video(path: String):
	if not ResourceLoader.exists(path):
		print("Video not found: ", path)
		var alt_path := "res://" + path.trim_prefix("res://")
		if ResourceLoader.exists(alt_path):
			path = alt_path
		else:
			finished.emit()
			return
	var stream := load(path) as VideoStream
	if not stream:
		print("Failed to load video stream: ", path)
		finished.emit()
		return
	_video_player = VideoStreamPlayer.new()
	_video_player.stream = stream
	_video_player.autoplay = true
	_video_player.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_video_player.expand = true
	_video_player.mouse_filter = MOUSE_FILTER_IGNORE
	_video_player.finished.connect(_on_video_finished)
	add_child(_video_player)
	move_child(_video_player, 1)
	_video_player.visible = true
	_video_player.play()
	print("Playing video: ", path)

func _on_video_finished():
	finished.emit()

func _toggle_pause():
	_paused = not _paused
	if _video_player:
		if _paused:
			_video_player.paused = true
			_pause_btn.text = "▶"
		else:
			_video_player.paused = false
			_pause_btn.text = "❚❚"

func _skip():
	if _video_player:
		_video_player.stop()
	finished.emit()

func _input(event):
	if visible and event is InputEventMouseButton and event.pressed:
		# Click on video area (not controls) to skip
		if _controls.get_rect().has_point(event.position):
			return
		_skip()

func close():
	if _video_player:
		_video_player.stop()
		_video_player.queue_free()
		_video_player = null
	hide()
