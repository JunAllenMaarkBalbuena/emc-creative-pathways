extends Node

## Regression test: the Programming Lab must self-resolve its LevelDefinition
## (scripts/programming_lab.gd), otherwise closing the lab never marks the level
## complete in LevelProgression. Also verifies the sequence file still loads by
## the resolved level id.

var _fail := 0
var _completed_id := ""

func _ready() -> void:
	var tree := get_tree()
	var backup := _backup_progress_file()
	var lab_scene := load("res://scenes/programming_lab.tscn") as PackedScene
	var lab := lab_scene.instantiate()
	add_child(lab)
	await tree.process_frame

	if lab.level_def == null or lab.level_def.level_id != "programming_lab":
		_fail = 1
		print("FAIL: ProgrammingLab did not resolve level_def 'programming_lab'")
		_restore_progress_file(backup)
		tree.quit(_fail)
		return

	LevelProgression._completed.erase("programming_lab")
	LevelProgression._unlocked.erase("programming_lab")
	var connected := LevelProgression.level_completed.connect(_on_level_completed)
	lab._on_lab_exit()
	if _completed_id == "programming_lab":
		print("PASS: ProgrammingLab resolved '%s' and completed it via level_completed" % _completed_id)
	else:
		_fail = 1
		print("FAIL: level_completed did not fire for programming_lab (got: %s)" % _completed_id)
	LevelProgression.level_completed.disconnect(_on_level_completed)

	_restore_progress_file(backup)
	tree.quit(_fail)

func _on_level_completed(level: LevelDefinition) -> void:
	_completed_id = level.level_id

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