class_name GameConditions
extends RefCounted

static var _flags: Dictionary[String, bool] = {}

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

static func get_true_flag_ids() -> Array[String]:
	var result: Array[String] = []
	for flag_id in _flags:
		if _flags[flag_id]:
			result.append(flag_id)
	return result
