extends Node3D

@onready var player: PlayerController = $Player
@onready var status_label: Label = $Interface/Overlay/Status
@onready var prompt_panel: Control = $Interface/Overlay/InteractionPrompt
@onready var prompt_title: Label = $Interface/Overlay/InteractionPrompt/Content/Title
@onready var prompt_content: Label = $Interface/Overlay/InteractionPrompt/Content/Content
@onready var feedback_label: Label = $Interface/Overlay/Feedback
@onready var joystick: EMCMobileJoystick = $Interface/Overlay/VirtualJoystick
@onready var interact_button: Button = $Interface/Overlay/InteractionPrompt/Content/InteractButton
@onready var portrait: TextureRect = $Interface/Overlay/Portrait
@onready var dialogue_panel: PanelContainer = $Interface/Overlay/DialoguePanel
@onready var dialogue_speaker: Label = $Interface/Overlay/DialoguePanel/Content/SpeakerName
@onready var dialogue_text: RichTextLabel = $Interface/Overlay/DialoguePanel/Content/DialogueText
@onready var choices_container: VBoxContainer = $Interface/Overlay/DialoguePanel/Content/Choices
@onready var close_button: Button = $Interface/Overlay/DialoguePanel/CloseButton
@onready var continue_button: Button = $Interface/Overlay/DialoguePanel/ContinueButton

var _feedback_time := 0.0
var _last_interaction_target: Interactable
var _dialogue_lines: Array = []
var _dialogue_index := 0
var _dialogue_id := ""
var _typewriter_tween: Tween
var _is_typing := false
var _full_text := ""
var _has_choices := false
var _choice_buttons: Array[Button] = []

const TYPEWRITER_SPEED := 0.03
const MAX_CHOICES := 4

func _ready() -> void:
	prompt_panel.hide()
	dialogue_panel.hide()
	portrait.hide()
	close_button.hide()
	continue_button.hide()
	_create_choice_buttons()
	joystick.value_changed.connect(player.set_virtual_move)
	interact_button.pressed.connect(player.try_interact)
	close_button.pressed.connect(_close_dialogue)
	continue_button.pressed.connect(_on_continue_pressed)
	player.interaction_target_changed.connect(_on_interaction_target_changed)
	player.interaction_triggered.connect(_on_interaction_triggered)
	player.interaction_performed.connect(_on_interaction_performed)

func _create_choice_buttons() -> void:
	for i in MAX_CHOICES:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(0, 48)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.visible = false
		btn.pressed.connect(_on_choice_pressed.bind(i))
		choices_container.add_child(btn)
		_choice_buttons.append(btn)

func _unhandled_input(event: InputEvent) -> void:
	if not dialogue_panel.visible:
		return
	if event.is_action_pressed("ui_cancel"):
		_close_dialogue()
		return
	if _has_choices:
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		if _is_typing:
			_skip_typewriter()
		else:
			_advance_dialogue()

func _process(delta: float) -> void:
	var state := "Sprinting" if Input.is_action_pressed("sprint") else "Walking"
	status_label.text = "EMC Simulator — 2.5D Character Prototype\nWASD / Arrow Keys: Move    Shift: Sprint\n%s  •  Speed %.1f m/s" % [state, Vector2(player.velocity.x, player.velocity.z).length()]
	if _feedback_time > 0.0:
		_feedback_time -= delta
		if _feedback_time <= 0.0:
			feedback_label.hide()

func _on_interaction_target_changed(target: Interactable) -> void:
	if dialogue_panel.visible:
		return
	prompt_panel.visible = target != null
	if target != null:
		prompt_title.text = target.get_prompt_title()
		prompt_content.text = target.get_prompt_content()
		interact_button.text = target.interaction_button_text

func _on_interaction_triggered(target: Interactable) -> void:
	_last_interaction_target = target

func _on_interaction_performed(message: String) -> void:
	if _last_interaction_target is DialogueInteractable and _last_interaction_target.use_dialogue_sequence:
		_dialogue_lines = DialogueDatabase.get_dialogue_lines(_last_interaction_target.dialogue_id)
		_dialogue_id = _last_interaction_target.dialogue_id
		if not _dialogue_lines.is_empty():
			_dialogue_index = 0
			prompt_panel.hide()
			dialogue_panel.show()
			_show_current_dialogue_line()
			return
	feedback_label.text = message
	feedback_label.show()
	_feedback_time = 3.0

func _show_current_dialogue_line() -> void:
	var line: Dictionary = _dialogue_lines[_dialogue_index]
	var speaker_name := String(line.get("speaker", ""))
	var text := String(line.get("text", ""))
	var side := String(line.get("side", "right"))

	dialogue_speaker.text = speaker_name

	var tex := DialogueDatabase.get_portrait(_dialogue_id, "player" if side == "left" else "npc")
	portrait.texture = tex
	portrait.visible = tex != null
	if tex != null:
		var panel_left := dialogue_panel.position.x
		if side == "left":
			portrait.position.x = panel_left
		else:
			portrait.position.x = panel_left + dialogue_panel.size.x - portrait.custom_minimum_size.x

	close_button.show()
	continue_button.hide()

	var choices: Array = DialogueDatabase.get_choices(line)
	_has_choices = choices.size() > 0
	_hide_choice_buttons()

	if _has_choices:
		_start_typewriter(text)
		_typewriter_tween.finished.connect(_show_choices.bind(choices), CONNECT_ONE_SHOT)
	else:
		_start_typewriter(text)

func _show_choices(choices: Array) -> void:
	for i in _choice_buttons.size():
		if i < choices.size():
			_choice_buttons[i].text = String(choices[i].get("text", ""))
			_choice_buttons[i].visible = true
		else:
			_choice_buttons[i].visible = false

func _hide_choice_buttons() -> void:
	for btn in _choice_buttons:
		btn.visible = false

func _on_choice_pressed(index: int) -> void:
	var line: Dictionary = _dialogue_lines[_dialogue_index]
	var choices: Array = DialogueDatabase.get_choices(line)
	if index >= choices.size():
		return
	var choice: Dictionary = choices[index]
	var next_id := String(choice.get("next", ""))
	_hide_choice_buttons()
	_has_choices = false
	if not next_id.is_empty():
		_start_dialogue(next_id)
	else:
		_advance_dialogue()

func _start_dialogue(dialogue_id: String) -> void:
	_dialogue_lines = DialogueDatabase.get_dialogue_lines(dialogue_id)
	_dialogue_id = dialogue_id
	_dialogue_index = 0
	if _dialogue_lines.is_empty():
		_close_dialogue()
		return
	_show_current_dialogue_line()

func _start_typewriter(text: String) -> void:
	if _typewriter_tween:
		_typewriter_tween.kill()
	_full_text = text
	_is_typing = true
	dialogue_text.text = ""
	_typewriter_tween = create_tween()
	for i in text.length():
		_typewriter_tween.tween_callback(_append_character.bind(text[i])).set_delay(TYPEWRITER_SPEED)
	_typewriter_tween.tween_callback(_on_typewriter_finished)

func _append_character(ch: String) -> void:
	dialogue_text.text += ch

func _on_typewriter_finished() -> void:
	_is_typing = false
	dialogue_text.text = _full_text
	if not _has_choices:
		continue_button.show()

func _skip_typewriter() -> void:
	if _typewriter_tween:
		_typewriter_tween.kill()
	dialogue_text.text = _full_text
	_is_typing = false
	if not _has_choices:
		continue_button.show()

func _on_continue_pressed() -> void:
	if _is_typing:
		_skip_typewriter()
	else:
		_advance_dialogue()

func _advance_dialogue() -> void:
	continue_button.hide()
	_dialogue_index += 1
	if _dialogue_index >= _dialogue_lines.size():
		_close_dialogue()
		return
	_show_current_dialogue_line()

func _close_dialogue() -> void:
	if _typewriter_tween:
		_typewriter_tween.kill()
	_is_typing = false
	_has_choices = false
	_hide_choice_buttons()
	dialogue_panel.hide()
	portrait.hide()
	close_button.hide()
	continue_button.hide()
	_dialogue_lines = []
	_dialogue_index = 0
	if _last_interaction_target != null:
		_on_interaction_target_changed(_last_interaction_target)
