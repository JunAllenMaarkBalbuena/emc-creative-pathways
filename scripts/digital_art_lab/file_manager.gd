class_name FileManager
extends RefCounted

const PLAYER_DIR := "res://data/player_drawings/"
const EXPORT_DIR := "res://data/Exported_drawings/"


func save_artwork(data: DigitalArtData, file_name: String = "") -> String:
	_ensure_dirs()
	if file_name.is_empty():
		file_name = _sanitize_filename(data.artwork_name)
		if file_name.is_empty():
			file_name = "untitled"
	var path := PLAYER_DIR + file_name + ".tres"
	data.last_modified = _timestamp()
	if data.creation_date.is_empty():
		data.creation_date = data.last_modified
	data.resource_path = path
	var err := ResourceSaver.save(data, path)
	if err != OK:
		push_error("FileManager: Failed to save artwork: ", err)
		return ""
	return path


func load_artwork(path: String) -> DigitalArtData:
	if not ResourceLoader.exists(path):
		return null
	var data := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as DigitalArtData
	return data


func list_artworks() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var dir := DirAccess.open(PLAYER_DIR)
	if dir == null:
		return result

	dir.list_dir_begin()
	var fname := dir.get_next()
	while not fname.is_empty():
		if fname.ends_with(".tres") or fname.ends_with(".res"):
			var path := PLAYER_DIR + fname
			result.append({
				path = path,
				name = fname.trim_suffix(".tres").trim_suffix(".res"),
				date = "",
			})
		fname = dir.get_next()
	dir.list_dir_end()

	result.sort_custom(func(a, b): return a.name < b.name)
	return result


func delete_artwork(path: String) -> bool:
	var dir := DirAccess.open(PLAYER_DIR)
	if dir == null:
		return false
	var err := dir.remove(path.trim_prefix(PLAYER_DIR))
	return err == OK


func artwork_exists(name: String) -> bool:
	var path := PLAYER_DIR + _sanitize_filename(name) + ".tres"
	return ResourceLoader.exists(path)


func _ensure_dirs():
	var dir := DirAccess.open("res://")
	if dir == null:
		push_error("FileManager: Cannot open res://")
		return
	var err1 := dir.make_dir_recursive("data/player_drawings")
	var err2 := dir.make_dir_recursive("data/Exported_drawings")
	if err1 != OK:
		push_error("FileManager: Failed to create data/player_drawings: ", err1)
	if err2 != OK:
		push_error("FileManager: Failed to create data/Exported_drawings: ", err2)


func export_png(image: Image, file_name: String) -> String:
	_ensure_dirs()
	if file_name.is_empty():
		file_name = "untitled"
	var path := EXPORT_DIR + _sanitize_filename(file_name) + ".png"
	var err := image.save_png(path)
	if err != OK:
		push_error("FileManager: Failed to export PNG: ", err)
		return ""
	return path


func _sanitize_filename(name: String) -> String:
	const KEEP := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"
	var result := ""
	for c in name:
		if c in KEEP:
			result += c
		elif c == " ":
			result += "_"
	return result


func _timestamp() -> String:
	var dt := Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d %02d:%02d" % [dt.year, dt.month, dt.day, dt.hour, dt.minute]
