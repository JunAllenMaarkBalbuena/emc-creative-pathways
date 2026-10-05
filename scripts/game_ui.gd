class_name GameUI
extends CanvasLayer

## Reusable HUD component. Instance in any level to get status display,
## interaction prompt, feedback toasts, virtual joystick, interact button,
## and a pause menu with quick settings.

@onready var status_label: Label = $Overlay/Status
@onready var prompt_panel: Control = $Overlay/InteractionPrompt
@onready var prompt_title: Label = $Overlay/InteractionPrompt/Content/Title
@onready var prompt_content: Label = $Overlay/InteractionPrompt/Content/Content
@onready var interact_button: Button = $Overlay/InteractionPrompt/Content/InteractButton
@onready var feedback_label: Label = $Overlay/Feedback
@onready var joystick: EMCMobileJoystick = $Overlay/VirtualJoystick
@onready var menu_button: Button = $Overlay/MenuButton
@onready var pause_panel: PanelContainer = $Overlay/PausePanel
@onready var master_slider: HSlider = $Overlay/PausePanel/VBox/Master/Slider
@onready var touch_toggle: CheckButton = $Overlay/PausePanel/VBox/TouchControls
@onready var resume_button: Button = $Overlay/PausePanel/VBox/Buttons/ResumeButton
@onready var quit_button: Button = $Overlay/PausePanel/VBox/Buttons/QuitButton

## Set this in the Inspector instead of relying on sibling path lookups.
@export var dialogue_ui_path: NodePath

var _player: PlayerController
var _feedback_time := 0.0
var _current_target: Interactable
var _is_paused := false
## Whether the on-screen joystick belongs on screen at all. Decided once in
## _ready and then respected by every show/hide, so the dialogue handlers
## cannot switch it back on for a platform that does not want it.
var _touch_controls := false

func _ready() -> void:
	# The joystick is a plain Control with no visible=false in the scene, so it
	# renders on every platform unless something hides it. On a desktop build it
	# sits over the bottom-left 148x148 px with mouse_filter = STOP, which both
	# looks wrong and swallows clicks meant for whatever is behind it.
	#
	# Movement is unaffected either way: PlayerController merges the joystick's
	# _virtual_move with Input.get_vector() by taking whichever is longer, so a
	# hidden joystick simply contributes zero.
	_touch_controls = Platform.wants_touch_controls()
	joystick.visible = _touch_controls
	# Seed the checkbox before connecting, so assigning button_pressed cannot
	# loop back through _on_touch_controls_toggled and write an override that
	# silently outranks the real platform decision.
	touch_toggle.button_pressed = _touch_controls
	touch_toggle.toggled.connect(_on_touch_controls_toggled)

	prompt_panel.hide()
	feedback_label.hide()
	pause_panel.hide()
	menu_button.pressed.connect(_toggle_pause)
	resume_button.pressed.connect(_toggle_pause)
	quit_button.pressed.connect(_return_to_menu)
	master_slider.value_changed.connect(_on_master_volume_changed)
	var settings = get_node_or_null("/root/SettingsManager")
	if settings != null:
		master_slider.value = settings.master_volume
	call_deferred("_setup_player")

func _on_touch_controls_toggled(pressed: bool) -> void:
	# Forces the decision for this session so the joystick can be switched on for
	# desktop playtesting. Deliberately does not touch
	# Platform.show_desktop_settings() - a desktop tester who enables the
	# joystick keeps their fullscreen and resolution options.
	Platform.set_touch_controls_override(pressed)
	_touch_controls = pressed
	if not pressed:
		# Same reason as _on_dialogue_started: hiding a deflected joystick would
		# strand the last value, because the release event lands on nothing.
		joystick.reset()
	joystick.visible = pressed


func _on_master_volume_changed(value: float) -> void:
	var settings = get_node_or_null("/root/SettingsManager")
	if settings != null:
		settings.set_master_volume(value)

func _toggle_pause() -> void:
	_is_paused = not _is_paused
	get_tree().paused = _is_paused
	pause_panel.visible = _is_paused
	menu_button.text = "▶" if _is_paused else "☰"

func _return_to_menu() -> void:
	get_tree().paused = false
	if _player != null:
		var cam = get_tree().current_scene.get_node_or_null("PlayerFollowCamera")
		var cam_offset = cam.global_position - _player.global_position if cam else Vector3.ZERO
		var scene_path = get_tree().current_scene.scene_file_path
		if LevelProgression.has_resume_state():
			LevelProgression.save_lab_resume_state(scene_path, _player.global_position, cam_offset)
		else:
			LevelProgression.save_resume_state(scene_path, _player.global_position, cam_offset)
		LevelProgression.save_skin_index(_player.get_skin_index())
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_toggle_pause()
		elif event.keycode == KEY_F9:
			_reset_and_restart()

func _reset_and_restart() -> void:
	var progression := get_node_or_null("/root/LevelProgression")
	if progression != null:
		progression.reset_progress()
	get_tree().call_deferred("reload_current_scene")

func _setup_player() -> void:
	_player = _find_player()
	if _player == null:
		push_warning("GameUI: No PlayerController found in scene tree.")
		return
	joystick.value_changed.connect(_player.set_virtual_move)
	interact_button.pressed.connect(_player.try_interact)
	_player.interaction_target_changed.connect(_on_target_changed)
	_player.interaction_triggered.connect(_on_target_triggered)
	_player.interaction_performed.connect(_on_interaction_performed)
	_player.skin_changed.connect(_on_skin_changed)
	var dialogue_ui := _get_dialogue_ui()
	if dialogue_ui != null:
		dialogue_ui.dialogue_started.connect(_on_dialogue_started)
		dialogue_ui.dialogue_ended.connect(_on_dialogue_ended)

## Both handlers go through the _touch_controls flag rather than show()/hide()
## directly. Calling joystick.show() unconditionally on dialogue end would bring
## the joystick back on a desktop build every time a conversation finished.
func _on_dialogue_started() -> void:
	# Neutralise before hiding. A hidden Control receives no _gui_input, so a
	# thumb lifted mid-conversation would never re-centre the stick and the
	# character would keep walking on its last deflected value.
	joystick.reset()
	joystick.visible = false
	prompt_panel.hide()

func _on_dialogue_ended() -> void:
	joystick.visible = _touch_controls
	refresh_prompt()

func _find_player() -> PlayerController:
	var root := get_tree().current_scene
	if root == null:
		return null
	var nodes := root.find_children("*", "CharacterBody3D", true, false)
	for node in nodes:
		if node is PlayerController:
			return node
	return null

func _process(delta: float) -> void:
	if _player == null:
		return
	var state := "Sprinting" if Input.is_action_pressed("sprint") else "Walking"
	status_label.text = "EMC Simulator [%s]\nWASD / Arrow Keys: Move    Shift: Sprint    Tab: Switch Character\n%s  \u2022  Speed %.1f m/s\n[F9: Reset Progress]" % [_player.get_skin_name(), state, Vector2(_player.velocity.x, _player.velocity.z).length()]
	if _feedback_time > 0.0:
		_feedback_time -= delta
		if _feedback_time <= 0.0:
			feedback_label.hide()

func _on_target_changed(target: Interactable) -> void:
	if _is_paused:
		return
	var dialogue_ui := _get_dialogue_ui()
	if dialogue_ui != null and dialogue_ui.is_open():
		return
	_current_target = target
	prompt_panel.visible = target != null
	if target != null:
		prompt_title.text = target.get_prompt_title()
		prompt_content.text = target.get_prompt_content()
		interact_button.text = target.interaction_button_text

func _on_target_triggered(target: Interactable) -> void:
	_current_target = target

func _on_interaction_performed(message: String) -> void:
	var dialogue_ui := _get_dialogue_ui()
	if dialogue_ui != null and dialogue_ui.is_open():
		return
	if dialogue_ui != null and _current_target is DialogueInteractable and _current_target.use_dialogue_sequence:
		dialogue_ui.start_dialogue(_current_target.dialogue_id)
		prompt_panel.hide()
		return
	show_feedback(message)

func _get_dialogue_ui() -> DialogueUI:
	if dialogue_ui_path != NodePath():
		var node := get_node_or_null(dialogue_ui_path)
		if node is DialogueUI:
			return node
	var sibling := get_node_or_null("../DialogueUI")
	if sibling is DialogueUI:
		return sibling
	var root := get_tree().current_scene
	if root == null:
		return null
	var found := root.find_children("*", "DialogueUI", true, false)
	if found.size() > 0 and found[0] is DialogueUI:
		return found[0]
	return null

func _on_skin_changed(skin_name: String) -> void:
	show_feedback("Switched to: " + skin_name, 2.0)

func show_feedback(message: String, duration := 3.0) -> void:
	feedback_label.text = message
	feedback_label.show()
	_feedback_time = duration

func refresh_prompt() -> void:
	if _current_target != null:
		_on_target_changed(_current_target)
