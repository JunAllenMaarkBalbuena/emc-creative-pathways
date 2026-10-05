extends Node

## Persistent, platform-friendly level state. Use LevelDefinition resources to
## configure levels and this service to query, unlock, or complete them.
signal level_unlocked(level_id: String)
signal level_completed(level: LevelDefinition)
signal progress_reset

const SAVE_PATH := "user://level_progression.json"
const SEQUENCE_PATH := "res://data/sequences/game_sequence.tres"

## _completed and _unlocked are deliberately untyped: they are assigned wholesale
## from JSON.parse_string() in _load_progress(). A Dictionary[String, bool] would
## hard-fail on a hand-edited save holding 1 instead of true.
var _completed: Dictionary = {}
var _unlocked: Dictionary = {}
var _spawn_positions: Dictionary[String, Dictionary] = {}
var _level_sequence: GameSequence

func _ready() -> void:
	_load_progress()
	if ResourceLoader.exists(SEQUENCE_PATH):
		_level_sequence = ResourceLoader.load(SEQUENCE_PATH) as GameSequence

func register_level(level: LevelDefinition) -> void:
	if level == null or level.level_id.is_empty():
		return
	if level.starts_unlocked and not _unlocked.has(level.level_id):
		_unlocked[level.level_id] = true
		_save_progress()

func is_level_unlocked(level_id: String) -> bool:
	return _unlocked.get(level_id, false)

func is_level_completed(level_id: String) -> bool:
	return _completed.get(level_id, false)

func unlock_level(level_id: String) -> bool:
	if level_id.is_empty() or is_level_unlocked(level_id):
		return false
	_unlocked[level_id] = true
	_save_progress()
	level_unlocked.emit(level_id)
	return true

func complete_level(level: LevelDefinition) -> bool:
	if level == null or level.level_id.is_empty() or is_level_completed(level.level_id):
		return false
	_completed[level.level_id] = true
	_unlocked[level.level_id] = true
	for condition_id in level.reward_condition_ids:
		if not condition_id.is_empty():
			GameConditions.set_flag(condition_id, true)
	var next_id := _get_next_level_id(level)
	if not next_id.is_empty():
		unlock_level(next_id)
	_save_progress()
	level_completed.emit(level)
	return true

func _get_next_level_id(level: LevelDefinition) -> String:
	if _level_sequence != null and not _level_sequence.level_order_ids.is_empty():
		var idx := _level_sequence.level_order_ids.find(level.level_id)
		if idx >= 0 and idx < _level_sequence.level_order_ids.size() - 1:
			return _level_sequence.level_order_ids[idx + 1]
	return level.next_level_id

func reset_progress() -> void:
	_completed.clear()
	_unlocked.clear()
	clear_all_memory()
	_skin_index = -1
	GameConditions.clear_all()
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	progress_reset.emit()

func _load_progress() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_warning("Level progression save is invalid and will be ignored.")
		return
	_completed = parsed.get("completed", {})
	_unlocked = parsed.get("unlocked", {})
	for condition_id in parsed.get("reward_conditions", []):
		GameConditions.set_flag(String(condition_id), true)

func _save_progress() -> void:
	var reward_conditions := GameConditions.get_true_flag_ids()
	var data := {
		"completed": _completed,
		"unlocked": _unlocked,
		"reward_conditions": reward_conditions,
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Level progression could not be saved.")
		return
	file.store_string(JSON.stringify(data))

# --- Skin index (in-memory only, persists across scene transitions) ---

var _skin_index := -1

func save_skin_index(index: int) -> void:
	_skin_index = index

func get_skin_index(default_index: int) -> int:
	return _skin_index if _skin_index >= 0 else default_index

func reset_skin_index() -> void:
	_skin_index = -1

# --- Spawn positions (in-memory only, not persisted) ---

func clear_all_memory() -> void:
	_spawn_positions.clear()
	clear_resume_state()
	clear_lab_resume_state()

func save_spawn_position(scene_path: String, player_pos: Vector3, camera_offset: Vector3) -> void:
	_spawn_positions[scene_path] = {"player": player_pos, "camera_offset": camera_offset}

func get_spawn_position(scene_path: String) -> Variant:
	return _spawn_positions.get(scene_path)

func clear_spawn_position(scene_path: String) -> void:
	_spawn_positions.erase(scene_path)

# --- Resume game state (in-memory only) ---

var _resume_scene := ""
var _resume_spawn: Dictionary[String, Vector3] = {}

func save_resume_state(scene_path: String, player_pos: Vector3, camera_offset: Vector3) -> void:
	_resume_scene = scene_path
	_resume_spawn = {"player": player_pos, "camera_offset": camera_offset}

func has_resume_state() -> bool:
	return not _resume_scene.is_empty()

func get_resume_scene() -> String:
	return _resume_scene

func get_resume_spawn() -> Dictionary:
	return _resume_spawn

func clear_resume_state() -> void:
	_resume_scene = ""
	_resume_spawn = {}

# --- Lab resume (in-memory only) ---
# When returning to main menu from inside a lab, we save the lab as
# "lab resume" so Continue restores the lab. The main resume (world
# scene) is preserved so the lab exit can still restore the world position.

var _lab_resume_scene := ""
var _lab_resume_spawn: Dictionary[String, Vector3] = {}

func save_lab_resume_state(scene_path: String, player_pos: Vector3, camera_offset: Vector3) -> void:
	_lab_resume_scene = scene_path
	_lab_resume_spawn = {"player": player_pos, "camera_offset": camera_offset}

func has_lab_resume_state() -> bool:
	return not _lab_resume_scene.is_empty()

func get_lab_resume_scene() -> String:
	return _lab_resume_scene

func get_lab_resume_spawn() -> Dictionary:
	return _lab_resume_spawn

func clear_lab_resume_state() -> void:
	_lab_resume_scene = ""
	_lab_resume_spawn = {}
