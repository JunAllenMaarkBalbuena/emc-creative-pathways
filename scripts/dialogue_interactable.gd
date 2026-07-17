class_name DialogueInteractable
extends Interactable

@export var dialogue_id := ""
@export var use_dialogue_sequence := false

func interact(player: PlayerController) -> String:
	interaction_started.emit(player)
	if use_prompt_content_as_feedback:
		return get_prompt_content()
	return DialogueDatabase.get_text(dialogue_id, interaction_message)

func get_prompt_title() -> String:
	return DialogueDatabase.get_prompt_title(dialogue_id, prompt_title)

func get_prompt_content() -> String:
	return DialogueDatabase.get_prompt_content(dialogue_id, prompt_content)
