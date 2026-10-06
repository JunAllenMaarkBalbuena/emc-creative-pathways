extends SceneTree

## Gate: the 2.5D Animation Production Lab must have a LevelDefinition
## registered with the project's convention (data/levels/.tres), unlocked
## from the start (it is a menu-launched tool lab, like the other three)
## and carrying the reward condition used by doors/legacy interactables.
## Fails when the file is missing, misconfigured, or the class cache has
## not built LevelDefinition (run --import first).

func _init() -> void:
	var lvl := load("res://data/levels/animation_production_lab.tres") as LevelDefinition
	if lvl == null or lvl.level_id != "animation_production_lab" \
		or not lvl.starts_unlocked \
		or lvl.reward_condition_ids.size() != 1 \
		or lvl.reward_condition_ids[0] != "animation_production_lab_complete":
		print("FAIL: animation level definition missing or misconfigured")
		quit(1)
		return
	print("PASS: animation_production_lab LevelDefinition is configured")
	quit(0)