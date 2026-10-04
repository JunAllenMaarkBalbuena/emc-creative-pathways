extends Node

## Persistent settings manager. Autoload singleton that handles audio buses,
## display settings, and saves/loads to user://settings.json.

signal settings_changed

const SAVE_PATH := "user://settings.json"

var master_volume := 0.8
var music_volume := 0.8
var sfx_volume := 0.8
var voice_volume := 0.8
var fullscreen := false
var screen_resolution := Vector2i(1280, 720)

func _ready() -> void:
	_load_settings()
	_apply_all()

func set_master_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	_apply_audio()
	_save_progress()
	settings_changed.emit()

func set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	_apply_audio()
	_save_progress()
	settings_changed.emit()

func set_sfx_volume(value: float) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)
	_apply_audio()
	_save_progress()
	settings_changed.emit()

func set_voice_volume(value: float) -> void:
	voice_volume = clampf(value, 0.0, 1.0)
	_apply_audio()
	_save_progress()
	settings_changed.emit()

func set_fullscreen(enabled: bool) -> void:
	fullscreen = enabled
	_apply_display()
	_save_progress()
	settings_changed.emit()

func set_resolution(res: Vector2i) -> void:
	screen_resolution = res
	_apply_display()
	_save_progress()
	settings_changed.emit()

func _apply_all() -> void:
	_apply_audio()
	_apply_display()

func _apply_audio() -> void:
	_set_bus_volume("Master", master_volume)
	_set_bus_volume("Music", music_volume)
	_set_bus_volume("SFX", sfx_volume)
	_set_bus_volume("Voice", voice_volume)

func _set_bus_volume(bus_name: String, volume: float) -> void:
	var bus_idx := AudioServer.get_bus_index(bus_name)
	if bus_idx == -1:
		return
	AudioServer.set_bus_volume_db(bus_idx, linear_to_db(pow(volume, 2.0)))

func _apply_display() -> void:
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(screen_resolution)

func _save_progress() -> void:
	var data := {
		"master_volume": master_volume,
		"music_volume": music_volume,
		"sfx_volume": sfx_volume,
		"voice_volume": voice_volume,
		"fullscreen": fullscreen,
		"screen_resolution": [screen_resolution.x, screen_resolution.y],
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(data))

func _load_settings() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return
	master_volume = parsed.get("master_volume", 0.8)
	music_volume = parsed.get("music_volume", 0.8)
	sfx_volume = parsed.get("sfx_volume", 0.8)
	voice_volume = parsed.get("voice_volume", 0.8)
	fullscreen = parsed.get("fullscreen", false)
	var res = parsed.get("screen_resolution", [1280, 720])
	if res is Array and res.size() == 2:
		screen_resolution = Vector2i(int(res[0]), int(res[1]))
