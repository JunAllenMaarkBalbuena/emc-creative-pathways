class_name DoorInteractable
extends Interactable

@export var door_mesh_path: NodePath = NodePath("DoorMesh")
@export var open_angle := -90.0
@export var open_duration := 0.6
@export var dialogue_id := "library_door_locked"

var is_open := false

@export_group("Open Condition")
@export var enable_condition := false
@export var condition_id := ""
@export var condition_must_be_true := true
@export_multiline var locked_prompt_content := "This door requires completing a task first."

enum OnOpenAction { NONE, SET_CONDITION, LOAD_SCENE, TELEPORT_PLAYER }

@export_group("On Open Action")
@export var enable_on_open_action := false
@export var on_open_action_type: OnOpenAction = OnOpenAction.NONE
@export var on_open_condition_id := ""
@export var on_open_condition_value := true
@export_file("*.tscn") var on_open_scene_path := ""
@export var on_open_teleport_target: NodePath

func interact(player: PlayerController) -> String:
	if is_open:
		return "The laboratory door is already open."
	if enable_condition and not _is_condition_met():
		return DialogueDatabase.get_text(dialogue_id, "The door is locked. You need to complete a task first.")
	is_open = true
	var door_mesh := get_node_or_null(door_mesh_path) as Node3D
	if door_mesh != null:
		create_tween().tween_property(door_mesh, "rotation:y", deg_to_rad(open_angle), open_duration)
	_perform_on_open_action(player)
	return DialogueDatabase.get_text(dialogue_id, "The door opens.")

func _is_condition_met() -> bool:
	if condition_id.is_empty():
		return true
	return GameConditions.get_flag(condition_id) == condition_must_be_true

func _perform_on_open_action(player: PlayerController) -> void:
	if not enable_on_open_action:
		return
	match on_open_action_type:
		OnOpenAction.SET_CONDITION:
			if not on_open_condition_id.is_empty():
				GameConditions.set_flag(on_open_condition_id, on_open_condition_value)
		OnOpenAction.LOAD_SCENE:
			if not on_open_scene_path.is_empty():
				get_tree().change_scene_to_file(on_open_scene_path)
		OnOpenAction.TELEPORT_PLAYER:
			var target_node = get_node_or_null(on_open_teleport_target) as Node3D
			if target_node != null:
				player.global_position = target_node.global_position

func get_prompt_title() -> String:
	return DialogueDatabase.get_prompt_title(dialogue_id, prompt_title)

func get_prompt_content() -> String:
	if enable_condition and not _is_condition_met():
		return locked_prompt_content
	return DialogueDatabase.get_prompt_content(dialogue_id, prompt_content)
