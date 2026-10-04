class_name LevelDefinition
extends Resource

## Designer-owned data for one level. Create one .tres file per level and
## configure it in the Inspector; gameplay scenes do not need hard-coded IDs.
@export_category("Identity")
@export var level_id := ""
@export var display_name := "New Level"
@export_multiline var description := ""

@export_category("Progression")
@export var starts_unlocked := false
@export var next_level_id := ""
@export_file("*.tscn") var next_scene_path := ""
@export var load_next_scene_on_completion := false
@export_category("Rewards")
## These flags are also written to GameConditions for doors and other legacy
## interactables that use condition_id.
@export var reward_condition_ids: PackedStringArray = []
@export_multiline var completion_message := "Level complete."
