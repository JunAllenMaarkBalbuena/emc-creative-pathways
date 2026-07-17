class_name CollectibleInteractable
extends Interactable

@export var dialogue_id := "collectible_badge"
var collected := false

func interact(player: PlayerController) -> String:
	if collected:
		return "This item has already been collected."
	collected = true
	monitoring = false
	hide()
	return get_prompt_content() if use_prompt_content_as_feedback else DialogueDatabase.get_text(dialogue_id, interaction_message)

func get_prompt_title() -> String:
	return DialogueDatabase.get_prompt_title(dialogue_id, prompt_title)

func get_prompt_content() -> String:
	return DialogueDatabase.get_prompt_content(dialogue_id, prompt_content)
