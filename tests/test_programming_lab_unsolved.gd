extends Node

## Regression test: exiting the Programming Lab with nothing solved must NOT
## complete the level in LevelProgression.
##
## This is the other half of test_programming_lab.gd, and it needs its own
## process rather than a second case in that file. `_on_lab_exit` ends in
## change_scene_to_file, which frees the current scene - the harness the test
## runs in - so an exit can only be driven once per process and any code after
## it sees a null tree. Asserting both directions from one harness silently
## cannot work.
##
## That matters here: with both halves in one file, deleting the `all_solved`
## check in _on_lab_exit (so every exit completes the level) left the suite
## green. Completing levels the player never finished is the worse bug of the
## two, and it now has a guard.

var _fail := 0
var _fires := 0

func _ready() -> void:
	# Captured before the exit, which frees this node.
	var tree := get_tree()
	var backup := _backup_progress_file()
	_fail = await _run()
	_restore_progress_file(backup)
	tree.quit(_fail)

func _run() -> int:
	var lab_scene := load("res://scenes/programming_lab.tscn") as PackedScene
	var lab := lab_scene.instantiate() as ProgrammingLab
	add_child(lab)
	await get_tree().process_frame

	if lab.level_def == null or lab.level_def.level_id != "programming_lab":
		print("FAIL: ProgrammingLab did not resolve level_def 'programming_lab'")
		return 1
	if lab.puzzle_scores.is_empty():
		print("FAIL: lab loaded no puzzles, so this assertion is vacuous")
		return 1

	# Deliberately left unsolved - the fresh-load scores are all zero.
	LevelProgression._completed.erase("programming_lab")
	LevelProgression._unlocked.erase("programming_lab")
	LevelProgression.level_completed.connect(_on_level_completed)

	# No reads of this node after this call: it ends in change_scene_to_file,
	# which frees the harness. LevelProgression is an autoload and survives.
	lab._on_lab_exit()

	if _fires != 0:
		print("FAIL: exiting an unsolved lab completed the level %d time(s)" % _fires)
		return 1
	if LevelProgression.is_level_completed("programming_lab"):
		print("FAIL: level marked completed despite unsolved puzzles")
		return 1
	LevelProgression.level_completed.disconnect(_on_level_completed)
	print("PASS: exiting an unsolved ProgrammingLab does not complete the level")
	return 0

func _on_level_completed(_level: LevelDefinition) -> void:
	_fires += 1

func _backup_progress_file() -> String:
	var path := "user://level_progression.json"
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)

func _restore_progress_file(backup: String) -> void:
	var path := "user://level_progression.json"
	if backup.is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(backup)