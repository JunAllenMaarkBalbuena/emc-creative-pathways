class_name SettingsUI
extends Control

## Reusable settings panel. Instance in any scene to get audio sliders,
## fullscreen toggle, and resolution picker. Saves via SettingsManager.

signal settings_closed

@onready var master_slider: HSlider = $Panel/VBox/Master/MasterSlider
@onready var music_slider: HSlider = $Panel/VBox/Music/MusicSlider
@onready var sfx_slider: HSlider = $Panel/VBox/SFX/SFXSlider
@onready var voice_slider: HSlider = $Panel/VBox/Voice/VoiceSlider
@onready var fullscreen_check: CheckBox = $Panel/VBox/Display/FullscreenCheck
@onready var resolution_option: OptionButton = $Panel/VBox/Display/ResolutionOption
@onready var close_button: Button = $Panel/VBox/CloseButton

var _settings: Node

var _resolutions := [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
]

func _ready() -> void:
	_settings = get_node_or_null("/root/SettingsManager")
	_setup_resolution_items()
	_load_values()
	master_slider.value_changed.connect(_on_master_changed)
	music_slider.value_changed.connect(_on_music_changed)
	sfx_slider.value_changed.connect(_on_sfx_changed)
	voice_slider.value_changed.connect(_on_voice_changed)
	fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	resolution_option.item_selected.connect(_on_resolution_selected)
	close_button.pressed.connect(_on_close_pressed)
	hide()

func _setup_resolution_items() -> void:
	resolution_option.clear()
	for res in _resolutions:
		resolution_option.add_item("%d x %d" % [res.x, res.y])
		resolution_option.set_item_metadata(resolution_option.item_count - 1, res)

func open() -> void:
	_load_values()
	show()

func _load_values() -> void:
	if _settings == null:
		return
	master_slider.value = _settings.master_volume
	music_slider.value = _settings.music_volume
	sfx_slider.value = _settings.sfx_volume
	voice_slider.value = _settings.voice_volume
	fullscreen_check.button_pressed = _settings.fullscreen
	_select_resolution(_settings.screen_resolution)

func _on_master_changed(value: float) -> void:
	if _settings != null:
		_settings.set_master_volume(value)

func _on_music_changed(value: float) -> void:
	if _settings != null:
		_settings.set_music_volume(value)

func _on_sfx_changed(value: float) -> void:
	if _settings != null:
		_settings.set_sfx_volume(value)

func _on_voice_changed(value: float) -> void:
	if _settings != null:
		_settings.set_voice_volume(value)

func _on_fullscreen_toggled(enabled: bool) -> void:
	if _settings != null:
		_settings.set_fullscreen(enabled)

func _on_resolution_selected(index: int) -> void:
	if _settings == null:
		return
	var res := _get_resolution_from_index(index)
	_settings.set_resolution(res)

func _on_close_pressed() -> void:
	hide()
	settings_closed.emit()

func _select_resolution(res: Vector2i) -> void:
	for i in resolution_option.item_count:
		if resolution_option.get_item_metadata(i) == res:
			resolution_option.select(i)
			return

func _get_resolution_from_index(index: int) -> Vector2i:
	return resolution_option.get_item_metadata(index)
