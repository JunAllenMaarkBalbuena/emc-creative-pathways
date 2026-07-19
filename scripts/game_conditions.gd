class_name GameConditions
extends RefCounted

static var _flags: Dictionary = {}

static func set_flag(flag_id: String, value: bool) -> void:
	_flags[flag_id] = value

static func get_flag(flag_id: String) -> bool:
	return _flags.get(flag_id, false)

static func has_flag(flag_id: String) -> bool:
	return _flags.has(flag_id)

static func clear_flag(flag_id: String) -> void:
	_flags.erase(flag_id)

static func clear_all() -> void:
	_flags.clear()
