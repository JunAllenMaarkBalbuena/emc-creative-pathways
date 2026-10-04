class_name GameSequence
extends Resource

## Defines the global order in which levels unlock. List LevelDefinition
## level_ids in the order they should unlock (e.g. ["orientation",
## "coding_lab", "animation_studio"]). The autoload LevelProgression
## reads this to determine which level unlocks next.
@export var level_order_ids: Array[String] = []
