class_name DoorInteractable
extends Interactable

@export var door_mesh_path: NodePath = NodePath("DoorMesh")
@export var open_angle := -90.0
@export var open_duration := 0.6
@export var dialogue_id := "library_door_locked"

var is_open := false

func interact(player: PlayerController) -> String:
	if is_open:
		return "The laboratory door is already open."
	is_open = true
	var door_mesh := get_node_or_null(door_mesh_path) as Node3D
	if door_mesh != null:
		create_tween().tween_property(door_mesh, "rotation:y", deg_to_rad(open_angle), open_duration)
	return get_prompt_content() if use_prompt_content_as_feedback else DialogueDatabase.get_text(dialogue_id, "The door opens.")

func get_prompt_title() -> String:
	return DialogueDatabase.get_prompt_title(dialogue_id, prompt_title)

func get_prompt_content() -> String:
	return DialogueDatabase.get_prompt_content(dialogue_id, prompt_content)
