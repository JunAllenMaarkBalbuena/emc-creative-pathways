extends Node

## Regression test: pressing E both advances the dialogue (dialogue_ui._input)
## AND re-triggers player.try_interact() (player physics poll), causing a
## double-fire that restarts the conversation on every line.

var _fail := 0
var _interaction_fires := 0
var _dialogue_ui: DialogueUI
var _current_target: Interactable

func _ready() -> void:
	var tree := get_tree()
	var player := (load("res://scenes/player.tscn") as PackedScene).instantiate()
	add_child(player)
	await tree.process_frame

	_dialogue_ui = (load("res://scenes/dialogue_ui.tscn") as PackedScene).instantiate()
	add_child(_dialogue_ui)
	await tree.process_frame

	var npc := Area3D.new()
	npc.set_script(load("res://scripts/dialogue_interactable.gd"))
	npc.dialogue_id = "npc_kyle_coding"
	npc.use_dialogue_sequence = true
	add_child(npc)
	_current_target = npc
	player._on_interaction_area_entered(npc)
	player.interaction_performed.connect(_on_interaction_performed)

	# Press 1: opens the dialogue
	await _tap_interact()
	await tree.create_timer(1.6).timeout
	if not _dialogue_ui.is_open():
		_fail = 1
		print("FAIL: dialogue did not open on first E press")
		tree.quit(_fail)
		return
	if _interaction_fires != 1:
		_fail = 1
		print("FAIL: first E press fired interact %d times (expected 1)" % _interaction_fires)

	# Press 2: must advance the dialogue, NOT restart it.
	await _tap_interact()
	await tree.create_timer(1.6).timeout
	if _dialogue_ui._dialogue_index != 1:
		_fail = 1
		print("FAIL: after 2nd E press dialogue index=%d (expected 1; restarted?)" % _dialogue_ui._dialogue_index)
	if _interaction_fires != 1:
		_fail = 1
		print("FAIL: 2nd E press re-fired player interact (%d total)" % _interaction_fires)

	if _fail == 0:
		print("PASS: E advances dialogue without re-triggering player interact")
	tree.quit(_fail)

func _tap_interact() -> void:
	var ev := InputMap.action_get_events("interact")[0].duplicate() as InputEventKey
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().process_frame
	await get_tree().process_frame
	var rel := InputMap.action_get_events("interact")[0].duplicate() as InputEventKey
	rel.pressed = false
	Input.parse_input_event(rel)
	await get_tree().process_frame

func _on_interaction_performed(_message: String) -> void:
	_interaction_fires += 1
	if _current_target is DialogueInteractable and _current_target.use_dialogue_sequence:
		_dialogue_ui.start_dialogue(_current_target.dialogue_id)
