class_name PortfolioManager
extends RefCounted

## Manages the player's portfolio of saved artworks.
## Integrates with LevelProgression to mark the lab complete.

signal portfolio_changed
signal artwork_opened(data: DigitalArtData, path: String)

var _file_manager: FileManager
var _entries: Array[Dictionary] = []  # {path, name, date, data}

const PORTFOLIO_DIR := "res://data/portfolio/"


func _init(fm: FileManager):
	_file_manager = fm


func refresh():
	_entries = _file_manager.list_artworks()
	portfolio_changed.emit()


func get_entries() -> Array[Dictionary]:
	return _entries


func get_entry_count() -> int:
	return _entries.size()


func open_artwork(index: int) -> bool:
	if index < 0 or index >= _entries.size():
		return false
	var data := _file_manager.load_artwork(_entries[index].path)
	if data == null:
		return false
	artwork_opened.emit(data, _entries[index].path)
	return true


func delete_artwork(index: int) -> bool:
	if index < 0 or index >= _entries.size():
		return false
	var ok := _file_manager.delete_artwork(_entries[index].path)
	if ok:
		_entries.remove_at(index)
		portfolio_changed.emit()
	return ok


func rename_artwork(index: int, new_name: String) -> bool:
	if index < 0 or index >= _entries.size():
		return false
	var data := _file_manager.load_artwork(_entries[index].path)
	if data == null:
		return false
	data.artwork_name = new_name
	var new_path := _file_manager.save_artwork(data, new_name)
	if new_path.is_empty():
		return false
	# Delete old file if name changed
	var old_path: String = _entries[index].path
	
	if old_path != new_path:
		_file_manager.delete_artwork(old_path)
	refresh()
	return true
