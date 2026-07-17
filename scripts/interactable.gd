class_name Interactable
extends Area3D

## Shared base for doors, NPCs, signs, pickups, switches, terminals, and more.
## Override interact() in a specialized script for custom game behavior.
@export_category("Prompt")
@export var prompt_title := "Interact"
@export_multiline var prompt_content := ""
@export var interaction_button_text := "Interact"
@export var use_prompt_content_as_feedback := false
@export_multiline var interaction_message := "Interaction complete."
@export var interaction_icon: Texture2D

signal interaction_started(player: PlayerController)

func interact(player: PlayerController) -> String:
	interaction_started.emit(player)
	return prompt_content if use_prompt_content_as_feedback else interaction_message

func get_prompt_title() -> String:
	return prompt_title

func get_prompt_content() -> String:
	return prompt_content
