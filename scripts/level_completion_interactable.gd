class_name LevelCompletionInteractable
extends Interactable

## Drop this on any Area3D with a collision shape to complete a level through
## player interaction. The linked LevelDefinition contains all progression data.
@export var level: LevelDefinition

func _progression() -> Node:
	return LevelProgression

func _ready() -> void:
	if level != null:
		_progression().register_level(level)

func interact(player: PlayerController) -> String:
	interaction_started.emit(player)
	if level == null:
		push_warning("LevelCompletionInteractable has no LevelDefinition assigned.")
		return interaction_message
	var progression := _progression()
	if progression.is_level_completed(level.level_id):
		return level.completion_message
	if not progression.is_level_unlocked(level.level_id):
		return "This level is locked."
	if not progression.complete_level(level):
		return "Level progress could not be updated."
	if level.load_next_scene_on_completion and not level.next_scene_path.is_empty():
		SceneTransition.change_scene(level.next_scene_path)
	return level.completion_message

func get_prompt_title() -> String:
	return level.display_name if level != null else prompt_title

func get_prompt_content() -> String:
	if level == null:
		return prompt_content
	if _progression().is_level_completed(level.level_id):
		return level.completion_message
	if not prompt_content.is_empty():
		return prompt_content
	return level.description
