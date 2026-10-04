class_name CreativeStudioManager
extends RefCounted

var _unlocked: bool = false

signal studio_unlocked

func unlock():
	if not _unlocked:
		_unlocked = true
		studio_unlocked.emit()

func is_unlocked() -> bool:
	return _unlocked

func set_unlocked(val: bool):
	if val and not _unlocked:
		_unlocked = true
		studio_unlocked.emit()
	else:
		_unlocked = val
