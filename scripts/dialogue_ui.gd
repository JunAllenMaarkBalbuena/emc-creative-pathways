@tool
class_name DialogueUI
extends CanvasLayer

## Self-contained, reusable dialogue UI component.
## Manages dialogue display, typewriter effect, portraits, choices, and input.
## Start a conversation with start_dialogue() and listen for dialogue_ended.

@export_category("Typewriter")
@export_range(0.01, 0.2, 0.01) var typewriter_speed := 0.03

@export_category("Choices")
@export_range(1, 6) var max_choices := 4

@export_group("Portrait Layouts")
@export var portrait_layouts: Array[PortraitLayout] = []

@export_group("Portrait Preview")
@export var preview_portrait: Texture2D
@export var preview_target: int = 1
@export var preview_scale := Vector2(1.0, 1.0)
@export_range(0.0, 1.0, 0.001) var preview_anchor_left := 0.829
@export_range(0.0, 1.0, 0.001) var preview_anchor_top := 0.356
@export_range(0.0, 1.0, 0.001) var preview_anchor_right := 0.966
@export_range(0.0, 1.0, 0.001) var preview_anchor_bottom := 0.648
@export var preview_offset_left := -0.558
@export var preview_offset_top := 0.312
@export var preview_offset_right := -0.190
@export var preview_offset_bottom := 0.096
@export var preview_visible := false

@export var fallback_player_portrait: Texture2D
@export var fallback_npc_portrait: Texture2D

const DEFAULT_PLAYER_ANCHORS := Vector4(0.033, 0.356, 0.142, 0.648)
const DEFAULT_PLAYER_OFFSETS := Vector4(-0.016, 0.312, 0.416, 0.096)
const DEFAULT_NPC_ANCHORS := Vector4(0.829, 0.356, 0.966, 0.648)
const DEFAULT_NPC_OFFSETS := Vector4(-0.558, 0.312, -0.190, 0.096)

var _dialogue_lines: Array = []
var _dialogue_index := 0
var _dialogue_id := ""
var _typewriter_tween: Tween
var _is_typing := false
var _full_text := ""
var _has_choices := false
var _choice_buttons: Array[Button] = []
var _active_layout: PortraitLayout = null
var _preview_was_visible := false

@onready var dialogue_panel: PanelContainer = $DialoguePanel
@onready var dialogue_speaker: Label = $DialoguePanel/Content/SpeakerName
@onready var dialogue_text: RichTextLabel = $DialoguePanel/Content/DialogueText
@onready var choices_container: VBoxContainer = $DialoguePanel/Content/Choices
@onready var close_button: Button = $DialoguePanel/CloseButton
@onready var continue_button: Button = $DialoguePanel/ContinueButton
@onready var player_portrait: TextureRect = $PlayerPortrait
@onready var npc_portrait: TextureRect = $NpcPortrait

signal dialogue_started
signal dialogue_line_changed(index: int, speaker: String, text: String)
signal dialogue_choice_made(index: int, choice_text: String)
signal dialogue_ended

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if fallback_player_portrait == null:
		fallback_player_portrait = preload("res://assets/image/Player.png")
	if fallback_npc_portrait == null:
		fallback_npc_portrait = preload("res://assets/image/Mika.png")
	dialogue_panel.hide()
	player_portrait.hide()
	npc_portrait.hide()
	close_button.hide()
	continue_button.hide()
	close_button.focus_mode = Control.FOCUS_NONE
	continue_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(close_dialogue)
	continue_button.pressed.connect(_on_continue_pressed)
	dialogue_panel.gui_input.connect(_on_dialogue_panel_gui_input)
	dialogue_speaker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dialogue_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_create_choice_buttons()

func _create_choice_buttons() -> void:
	for i in max_choices:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(0, 48)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.focus_mode = Control.FOCUS_NONE
		btn.visible = false
		btn.pressed.connect(_on_choice_pressed.bind(i))
		choices_container.add_child(btn)
		_choice_buttons.append(btn)

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_update_editor_preview()

func _update_editor_preview() -> void:
	if not is_inside_tree():
		return
	var p := get_node_or_null("PlayerPortrait") as TextureRect
	var n := get_node_or_null("NpcPortrait") as TextureRect
	if p == null or n == null:
		return
	if not preview_visible or preview_portrait == null:
		if _preview_was_visible:
			_restore_default_portrait(p, false)
			_restore_default_portrait(n, true)
			p.hide()
			n.hide()
			_preview_was_visible = false
		return
	_preview_was_visible = true
	var target_rect := n if preview_target == 1 else p
	var other_rect := p if preview_target == 1 else n
	other_rect.hide()
	target_rect.texture = preview_portrait
	_apply_control_values(target_rect,
		preview_scale,
		preview_anchor_left, preview_anchor_top, preview_anchor_right, preview_anchor_bottom,
		preview_offset_left, preview_offset_top, preview_offset_right, preview_offset_bottom)
	target_rect.show()

func _apply_control_values(rect: TextureRect, rect_scale: Vector2,
	a_l: float, a_t: float, a_r: float, a_b: float,
	o_l: float, o_t: float, o_r: float, o_b: float) -> void:
	rect.anchors_preset = Control.PRESET_FULL_RECT
	rect.anchor_left = a_l
	rect.anchor_top = a_t
	rect.anchor_right = a_r
	rect.anchor_bottom = a_b
	rect.offset_left = o_l
	rect.offset_top = o_t
	rect.offset_right = o_r
	rect.offset_bottom = o_b
	rect.scale = rect_scale

func _apply_layout_to_portrait(rect: TextureRect, layout: PortraitLayout, is_npc: bool) -> void:
	if is_npc:
		_apply_control_values(rect, layout.npc_scale,
			layout.npc_anchor_left, layout.npc_anchor_top,
			layout.npc_anchor_right, layout.npc_anchor_bottom,
			layout.npc_offset_left, layout.npc_offset_top,
			layout.npc_offset_right, layout.npc_offset_bottom)
	else:
		_apply_control_values(rect, layout.player_scale,
			layout.player_anchor_left, layout.player_anchor_top,
			layout.player_anchor_right, layout.player_anchor_bottom,
			layout.player_offset_left, layout.player_offset_top,
			layout.player_offset_right, layout.player_offset_bottom)

func _restore_default_portrait(rect: TextureRect, is_npc: bool) -> void:
	var anchors := DEFAULT_NPC_ANCHORS if is_npc else DEFAULT_PLAYER_ANCHORS
	var offsets := DEFAULT_NPC_OFFSETS if is_npc else DEFAULT_PLAYER_OFFSETS
	_apply_control_values(rect, Vector2.ONE,
		anchors.x, anchors.y, anchors.z, anchors.w,
		offsets.x, offsets.y, offsets.z, offsets.w)

func _find_layout(dialogue_id: String) -> PortraitLayout:
	for layout in portrait_layouts:
		if layout.dialogue_id == dialogue_id:
			return layout
	return null

func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if not dialogue_panel.visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close_dialogue()
		get_viewport().set_input_as_handled()
		return
	if _has_choices:
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		if _is_typing:
			_skip_typewriter()
		else:
			_advance_dialogue()
		get_viewport().set_input_as_handled()

func is_open() -> bool:
	return dialogue_panel.visible

func start_dialogue(dialogue_id: String) -> void:
	_dialogue_lines = DialogueDatabase.get_dialogue_lines(dialogue_id)
	_dialogue_id = dialogue_id
	_dialogue_index = 0
	_active_layout = _find_layout(dialogue_id)
	if _dialogue_lines.is_empty():
		close_dialogue()
		return
	dialogue_panel.show()
	dialogue_started.emit()
	_show_current_dialogue_line()

func start_dialogue_lines(lines: Array, dialogue_id: String = "") -> void:
	_dialogue_lines = lines
	_dialogue_id = dialogue_id
	_dialogue_index = 0
	_active_layout = _find_layout(dialogue_id)
	if _dialogue_lines.is_empty():
		close_dialogue()
		return
	dialogue_panel.show()
	dialogue_started.emit()
	_show_current_dialogue_line()

func close_dialogue() -> void:
	if _typewriter_tween:
		_typewriter_tween.kill()
	_is_typing = false
	_has_choices = false
	_hide_choice_buttons()
	dialogue_panel.hide()
	player_portrait.hide()
	npc_portrait.hide()
	close_button.hide()
	continue_button.hide()
	_active_layout = null
	_dialogue_lines = []
	_dialogue_index = 0
	dialogue_ended.emit()

func _show_current_dialogue_line() -> void:
	var line: Dictionary = _dialogue_lines[_dialogue_index]
	var speaker_name := String(line.get("speaker", ""))
	var text := String(line.get("text", ""))
	var side := String(line.get("side", "right"))

	dialogue_speaker.text = speaker_name

	var is_player_side := side == "left"
	var active_portrait := player_portrait if is_player_side else npc_portrait
	var tex := DialogueDatabase.get_portrait(_dialogue_id, "player" if is_player_side else "npc")
	if tex == null:
		tex = fallback_player_portrait if is_player_side else fallback_npc_portrait
	player_portrait.hide()
	npc_portrait.hide()
	active_portrait.texture = tex

	if _active_layout != null:
		_apply_layout_to_portrait(active_portrait, _active_layout, not is_player_side)
	else:
		_restore_default_portrait(player_portrait, false)
		_restore_default_portrait(npc_portrait, true)

	active_portrait.show()

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

	dialogue_line_changed.emit(_dialogue_index, speaker_name, text)

func _show_choices(choices: Array) -> void:
	for i in _choice_buttons.size():
		if i < choices.size():
			_choice_buttons[i].text = String(choices[i].get("text", ""))
			_choice_buttons[i].visible = true
			_choice_buttons[i].disabled = true
		else:
			_choice_buttons[i].visible = false
	get_tree().create_timer(1.0).timeout.connect(_enable_choices, CONNECT_ONE_SHOT)

func _enable_choices() -> void:
	for btn in _choice_buttons:
		btn.disabled = false

func _hide_choice_buttons() -> void:
	for btn in _choice_buttons:
		btn.visible = false

func _on_choice_pressed(index: int) -> void:
	var line: Dictionary = _dialogue_lines[_dialogue_index]
	var choices: Array = DialogueDatabase.get_choices(line)
	if index >= choices.size():
		return
	var choice: Dictionary = choices[index]
	var choice_text := String(choice.get("text", ""))
	var next_id := String(choice.get("next", ""))
	_hide_choice_buttons()
	_has_choices = false
	dialogue_choice_made.emit(index, choice_text)
	if not next_id.is_empty():
		_start_dialogue(next_id)
	else:
		_advance_dialogue()

func _start_dialogue(dialogue_id: String) -> void:
	_dialogue_lines = DialogueDatabase.get_dialogue_lines(dialogue_id)
	_dialogue_id = dialogue_id
	_dialogue_index = 0
	_active_layout = _find_layout(dialogue_id)
	if _dialogue_lines.is_empty():
		close_dialogue()
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
		_typewriter_tween.tween_callback(_append_character.bind(text[i])).set_delay(typewriter_speed)
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
	if _has_choices:
		var line: Dictionary = _dialogue_lines[_dialogue_index]
		var choices: Array = DialogueDatabase.get_choices(line)
		_show_choices(choices)
	else:
		continue_button.show()

func _on_dialogue_panel_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _has_choices:
			return
		if _is_typing:
			_skip_typewriter()
		else:
			_advance_dialogue()

func _on_continue_pressed() -> void:
	if _is_typing:
		_skip_typewriter()
	else:
		_advance_dialogue()

func _advance_dialogue() -> void:
	continue_button.hide()
	_dialogue_index += 1
	if _dialogue_index >= _dialogue_lines.size():
		close_dialogue()
		return
	_show_current_dialogue_line()
