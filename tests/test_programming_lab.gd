extends Node

## Regression test: the Programming Lab must self-resolve its LevelDefinition
## (scripts/programming_lab/programming_lab.gd), otherwise closing the lab never
## marks the level complete in LevelProgression. Also verifies the sequence file
## still loads by the resolved level id.
##
## Completion is conditional, and this test used to get that wrong. `_on_lab_exit`
## calls complete_level only when every entry in puzzle_scores is non-zero, so
## exiting a freshly-loaded lab correctly does NOT complete the level. The old
## assertion fired unconditionally and so failed for the entire time it sat in
## the gate, failing for a correct reason.
##
## So the exit is exercised with the scores a finished sequence leaves behind.
##
## The opposite direction lives in test_programming_lab_unsolved.gd, and needs a
## separate harness on purpose: `_on_lab_exit` ends in change_scene_to_file,
## which frees the current scene - the harness this test runs in - so an exit can
## only be driven once per process. With both directions in one file, deleting
## the `all_solved` check left the suite green while every lab exit completed
## the level.

var _fail := 0

## Set by _on_level_completed. A member rather than a local because GDScript
## lambdas capture locals by value: a counter incremented inside a lambda would
## never be visible here.
var _fires := 0

func _ready() -> void:
	# Captured before the exit below, which ends in change_scene_to_file and
	# frees this node - so get_tree() returns null from then on and the process
	# would never quit.
	var tree := get_tree()
	var backup := _backup_progress_file()
	_fail = await _run()
	_restore_progress_file(backup)
	tree.quit(_fail)

func _run() -> int:
	var tree := get_tree()
	var lab := _make_lab()
	await tree.process_frame

	if lab.level_def == null or lab.level_def.level_id != "programming_lab":
		print("FAIL: ProgrammingLab did not resolve level_def 'programming_lab'")
		return 1

	# Guarding against a vacuous test: with no puzzles there is nothing to score,
	# so the completion check below would pass for the wrong reason.
	if lab.puzzle_scores.is_empty():
		print("FAIL: lab loaded no puzzles, so the solved-exit check below is vacuous")
		return 1

	_reset_progression()
	for i in range(lab.puzzle_scores.size()):
		lab.puzzle_scores[i] = 100
	_fires = 0
	LevelProgression.level_completed.connect(_on_level_completed)
	# Everything that reads this node must happen before the call, not after.
	var exit_code := _exit_and_verify(lab)
	LevelProgression.level_completed.disconnect(_on_level_completed)
	return exit_code

func _on_level_completed(_level: LevelDefinition) -> void:
	_fires += 1

## Checks the completion state that `_on_lab_exit` just produced.
##
## Deliberately takes no `self` reach-through after the exit: that call ends in
## change_scene_to_file, which frees the harness this test runs in, so anything
## that touches this node afterwards sees a null tree. LevelProgression is an
## autoload and survives.
func _exit_and_verify(lab: ProgrammingLab) -> int:
	lab._on_lab_exit()
	if _fires != 1:
		print("FAIL: level_completed should fire once for a solved lab, got %d" % _fires)
		return 1
	if not LevelProgression.is_level_completed("programming_lab"):
		print("FAIL: level_completed fired but the level was not marked completed")
		return 1
	print("PASS: ProgrammingLab completed 'programming_lab' via level_completed")
	return 0

func _make_lab() -> ProgrammingLab:
	var lab_scene := load("res://scenes/programming_lab.tscn") as PackedScene
	var lab := lab_scene.instantiate() as ProgrammingLab
	add_child(lab)
	return lab

func _reset_progression() -> void:
	LevelProgression._completed.erase("programming_lab")
	LevelProgression._unlocked.erase("programming_lab")

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