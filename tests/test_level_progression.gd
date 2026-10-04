extends SceneTree

## Regression test: LevelProgression must load the GameSequence ordering.
## Root cause of bug: SEQUENCE_PATH pointed at res://data/levels/game_sequence.tres,
## but the file lives in res://data/sequences/. Same wrong path was duplicated
## in flowchart_editor.gd's _sequence_path.

func _init() -> void:
	var code := _run()
	quit(code)

func _run() -> int:
	var expect_path := "res://data/sequences/game_sequence.tres"
	if not ResourceLoader.exists(expect_path):
		print("FAIL: GameSequence file missing at %s" % expect_path)
		return 1

	var lp_script := load("res://scripts/level_progression.gd") as GDScript
	if lp_script == null:
		print("FAIL: cannot load level_progression.gd")
		return 1
	var lp: Node = lp_script.new()
	lp._ready()
	if lp._level_sequence == null:
		print("FAIL: LevelProgression._level_sequence is null (SEQUENCE_PATH wrong)")
		lp.free()
		return 1
	if lp._level_sequence.level_order_ids.is_empty():
		print("FAIL: GameSequence loaded but has no level_order_ids")
		lp.free()
		return 1

	var src := FileAccess.get_file_as_string("res://scripts/programming_lab/flowchart_editor.gd")
	if src.is_empty():
		print("FAIL: cannot read flowchart_editor.gd")
		lp.free()
		return 1
	if not src.contains("res://data/sequences/game_sequence.tres"):
		print("FAIL: flowchart_editor.gd does not reference the correct sequence path")
		lp.free()
		return 1

	print("PASS: LevelProgression loaded GameSequence: ", lp._level_sequence.level_order_ids)
	lp.free()
	return 0