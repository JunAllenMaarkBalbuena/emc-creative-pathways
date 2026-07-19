class_name DialogueDatabase
extends RefCounted

const DIALOGUE_PATH := "res://data/dialogue.json"
static var _entries: Dictionary = {}
static var _is_loaded := false

static func get_text(dialogue_id: String, fallback := "") -> String:
	_load_if_needed()
	var entry: Dictionary = _entries.get(dialogue_id, {})
	if entry.is_empty():
		return fallback
	var speaker := String(entry.get("speaker", ""))
	var text := String(entry.get("text", fallback))
	return (speaker + ": " if not speaker.is_empty() else "") + text

static func get_prompt_title(dialogue_id: String, fallback := "") -> String:
	_load_if_needed()
	var entry: Dictionary = _entries.get(dialogue_id, {})
	return String(entry.get("prompt_title", fallback))

static func get_prompt_content(dialogue_id: String, fallback := "") -> String:
	_load_if_needed()
	var entry: Dictionary = _entries.get(dialogue_id, {})
	return String(entry.get("prompt_content", fallback))

static func get_dialogue_lines(dialogue_id: String) -> Array:
	_load_if_needed()
	var entry: Dictionary = _entries.get(dialogue_id, {})
	return entry.get("dialogue", [])

static func get_portrait(dialogue_id: String, side: String) -> Texture2D:
	_load_if_needed()
	var entry: Dictionary = _entries.get(dialogue_id, {})
	var path := String(entry.get("portrait_" + side, ""))
	if path.is_empty():
		return null
	return load(path) as Texture2D

static func get_choices(line: Dictionary) -> Array:
	return line.get("choices", [])

static func _load_if_needed() -> void:
	if _is_loaded:
		return
	_is_loaded = true
	var file := FileAccess.open(DIALOGUE_PATH, FileAccess.READ)
	if file == null:
		push_warning("Dialogue file could not be opened: " + DIALOGUE_PATH)
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		_entries = parsed
	else:
		push_warning("Dialogue JSON is invalid: " + DIALOGUE_PATH)
