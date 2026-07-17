extends Node3D

@onready var player: PlayerController = $Player
@onready var status_label: Label = $Interface/Status
@onready var prompt_panel: Control = $Interface/InteractionPrompt
@onready var prompt_title: Label = $Interface/InteractionPrompt/Content/Title
@onready var prompt_content: Label = $Interface/InteractionPrompt/Content/Content
@onready var feedback_label: Label = $Interface/Feedback
@onready var joystick: EMCMobileJoystick = $Interface/VirtualJoystick
@onready var interact_button: Button = $Interface/InteractionPrompt/Content/InteractButton
@onready var dialogue_panel: PanelContainer = $Interface/DialoguePanel
@onready var dialogue_speaker: Label = $Interface/DialoguePanel/Content/Speaker
@onready var dialogue_text: Label = $Interface/DialoguePanel/Content/Text
@onready var dialogue_continue: Button = $Interface/DialoguePanel/Content/ContinueButton

var _feedback_time := 0.0
var _last_interaction_target: Interactable
var _dialogue_lines: Array = []
var _dialogue_index := 0

func _ready() -> void:
	prompt_panel.hide()
	dialogue_panel.hide()
	joystick.value_changed.connect(player.set_virtual_move)
	interact_button.pressed.connect(player.try_interact)
	player.interaction_target_changed.connect(_on_interaction_target_changed)
	player.interaction_triggered.connect(_on_interaction_triggered)
	player.interaction_performed.connect(_on_interaction_performed)
	dialogue_continue.pressed.connect(_show_next_dialogue_line)

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
		if not _dialogue_lines.is_empty():
			_dialogue_index = 0
			prompt_panel.hide()
			dialogue_panel.show()
			_show_current_dialogue_line()
			return
	feedback_label.text = message
	feedback_label.show()
	_feedback_time = 3.0

func _show_next_dialogue_line() -> void:
	_dialogue_index += 1
	if _dialogue_index >= _dialogue_lines.size():
		dialogue_panel.hide()
		if _last_interaction_target != null:
			_on_interaction_target_changed(_last_interaction_target)
		return
	_show_current_dialogue_line()

func _show_current_dialogue_line() -> void:
	var line: Dictionary = _dialogue_lines[_dialogue_index]
	dialogue_speaker.text = String(line.get("speaker", ""))
	dialogue_text.text = String(line.get("text", ""))
	var is_player_line := String(line.get("side", "right")) == "left"
	dialogue_panel.anchor_left = 0.0 if is_player_line else 1.0
	dialogue_panel.anchor_right = 0.0 if is_player_line else 1.0
	dialogue_panel.offset_left = 28.0 if is_player_line else -520.0
	dialogue_panel.offset_right = 520.0 if is_player_line else -28.0
