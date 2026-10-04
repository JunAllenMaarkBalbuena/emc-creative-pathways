class_name PortfolioManager3D
extends RefCounted

signal portfolio_changed
signal model_opened(data: ModelData, path: String)

var _save_manager: SaveManager
var _entries: Array[Dictionary] = []

func _init(sm: SaveManager):
	_save_manager = sm

func refresh():
	_entries = _save_manager.list_saved()
	portfolio_changed.emit()

func get_entries() -> Array[Dictionary]:
	return _entries

func get_entry_count() -> int:
	return _entries.size()

func open_artifact(index: int) -> bool:
	if index < 0 or index >= _entries.size():
		return false
	var data := _save_manager.load_model(_entries[index].path)
	if data == null:
		return false
	model_opened.emit(data, _entries[index].path)
	return true

func delete_artwork(index: int) -> bool:
	if index < 0 or index >= _entries.size():
		return false
	var ok := _save_manager.delete_model(_entries[index].path)
	if ok:
		_entries.remove_at(index)
		portfolio_changed.emit()
	return ok

func rename_artwork(index: int, new_name: String) -> bool:
	if index < 0 or index >= _entries.size():
		return false
	var path: String = _entries[index].path
	var data := _save_manager.load_model(path)
	if data == null:
		return false
	data.model_name = new_name
	var new_path := _save_manager.save_model(data, new_name)
	if new_path.is_empty():
		return false
	if new_path != path:
		_save_manager.delete_model(path)
	refresh()
	return true
