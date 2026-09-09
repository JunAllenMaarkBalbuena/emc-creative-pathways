class_name CutscenePlayer
extends CanvasLayer

signal cutscene_finished

enum Type { NONE, PNG_SEQUENCE, VIDEO }

var _type := Type.NONE
var _frames: Array[Texture2D] = []
var _durations: Array[float] = []
var _frame_idx := 0
var _is_playing := false
var _paused := false
var _paused_scene_audio: Array[AudioStreamPlayer] = []

@onready var bg_rect: ColorRect = $BGRect
@onready var frame_rect: TextureRect = $FrameRect
@onready var video_player: VideoStreamPlayer = $VideoPlayer
@onready var fade_rect: ColorRect = $FadeRect
@onready var subtitle_label: Label = $SubtitleLabel
@onready var controls: HBoxContainer = $Controls
@onready var pause_btn: Button = $Controls/PauseButton
@onready var skip_btn: Button = $Controls/SkipButton
@onready var bgm_player: AudioStreamPlayer = $BGMPlayer
@onready var sfx_player: AudioStreamPlayer = $SFXPlayer

func _ready():
	pause_btn.pressed.connect(_toggle_pause)
	skip_btn.pressed.connect(skip)
	visible = false
	process_mode = PROCESS_MODE_ALWAYS

func play(data: CutsceneDefinition):
	if data == null:
		return
	_pause_scene_audio()
	visible = true
	if data.is_video():
		_type = Type.VIDEO
		_play_video(data)
	else:
		_type = Type.PNG_SEQUENCE
		_play_frames(data)
	if data.bgm:
		bgm_player.stream = data.bgm
		bgm_player.volume_db = linear_to_db(data.bgm_volume)
		bgm_player.play()

func _play_video(data: CutsceneDefinition):
	frame_rect.visible = false
	video_player.stream = data.video_stream
	video_player.visible = true
	video_player.play()
	video_player.finished.connect(_finish)
	_is_playing = true

func _play_frames(data: CutsceneDefinition):
	video_player.visible = false
	frame_rect.visible = true
	_frames.clear()
	_durations.clear()
	for cf in data.frames:
		if cf.image:
			_frames.append(cf.image)
			_durations.append(cf.duration)
	if _frames.is_empty():
		return
	_frame_idx = 0
	frame_rect.texture = _frames[0]
	_is_playing = true
	_advance_frame_timer(_durations[0] if _durations[0] > 0 else 1.0)

func _advance_frame_timer(duration: float):
	if not _is_playing or _paused:
		return
	var timer := get_tree().create_timer(duration)
	timer.timeout.connect(_next_frame)

func _next_frame():
	if not _is_playing or _paused:
		return
	_frame_idx += 1
	if _frame_idx >= _frames.size():
		_finish()
		return
	frame_rect.texture = _frames[_frame_idx]
	var dur := 1.0
	if _frame_idx < _durations.size() and _durations[_frame_idx] > 0:
		dur = _durations[_frame_idx]
	_advance_frame_timer(dur)

func _finish():
	_is_playing = false
	bgm_player.stop()
	_restore_scene_audio()
	cutscene_finished.emit()

func skip():
	_is_playing = false
	video_player.stop()
	bgm_player.stop()
	_finish()

func _toggle_pause():
	_paused = not _paused
	if _type == Type.VIDEO:
		video_player.paused = _paused
		bgm_player.stream_paused = _paused
	pause_btn.text = "▶" if _paused else "❚❚"

func _pause_scene_audio():
	_paused_scene_audio.clear()
	for player in get_tree().root.find_children("*", "AudioStreamPlayer", true, false):
		if player != bgm_player and player.playing:
			player.stream_paused = true
			_paused_scene_audio.append(player)

func _restore_scene_audio():
	for player in _paused_scene_audio:
		if is_instance_valid(player):
			player.stream_paused = false
	_paused_scene_audio.clear()

func set_subtitle(text: String):
	subtitle_label.text = text
