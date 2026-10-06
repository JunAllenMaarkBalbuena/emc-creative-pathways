class_name EMCAssetLibrary
extends RefCounted

## Read-only adapter over the EMC Asset Library for the animation lab:
## committed starter assets (always present — the lab must boot with an
## empty user://) plus a defensive scan of the other labs' user output:
##   - user://exports/*.png  -> user_art sprite entries (illustration output)
##   - user://drawings/*.tres -> user_art drawing entries (DigitalArtData)
## Missing directories are skipped without error; assets whose path is dead
## load as null textures. This adapter never writes anything.

const CATEGORY_USER := "user_art"

## Injectable for tests: point these at scratch or bogus roots.
var user_roots: Array[String] = ["user://exports", "user://drawings"]

var _assets: Array[EMCAssetData] = []
var _by_id: Dictionary = {}
var _user_next := 1


func _init() -> void:
	refresh()


func refresh() -> void:
	_assets.clear()
	_by_id.clear()
	_user_next = 1
	for starter in StarterAssets.build():
		_register(starter)
	for root_path in user_roots:
		_scan_user_root(root_path)


func list(category: String = "") -> Array[EMCAssetData]:
	var out: Array[EMCAssetData] = []
	for a in _assets:
		if category.is_empty() or a.category == category:
			out.append(a)
	return out


func get_asset(asset_id: String) -> EMCAssetData:
	return _by_id.get(asset_id, null) as EMCAssetData


func load_texture(data: EMCAssetData) -> Texture2D:
	if data == null or data.path.is_empty() or not ResourceLoader.exists(data.path):
		return null
	return ResourceLoader.load(data.path, "Texture2D") as Texture2D


func _register(a: EMCAssetData) -> void:
	_assets.append(a)
	if not a.asset_id.is_empty():
		_by_id[a.asset_id] = a


func _scan_user_root(root_path: String) -> void:
	if not DirAccess.dir_exists_absolute(root_path):
		return
	var dir := DirAccess.open(root_path)
	if dir == null:
		return
	var pngs: Array[String] = []
	var tress: Array[String] = []
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir():
			if name.ends_with(".png"):
				pngs.append(name)
			elif name.ends_with(".tres"):
				tress.append(name)
		name = dir.get_next()
	dir.list_dir_end()
	pngs.sort()
	tress.sort()
	for file in pngs:
		_register(_sprite_entry(root_path + "/" + file, file.get_basename()))
	for file in tress:
		_register(_drawing_entry(root_path + "/" + file, file.get_basename()))


func _sprite_entry(path: String, stem: String) -> EMCAssetData:
	var a := EMCAssetData.new()
	a.asset_id = "user_%d" % _user_next
	_user_next += 1
	a.display_name = stem
	a.category = CATEGORY_USER
	a.asset_type = "sprite"
	a.source_lab = "illustration"
	a.path = path
	return a


func _drawing_entry(path: String, stem: String) -> EMCAssetData:
	# The illustration lab saves DigitalArtData resources; anything else that
	# happens to live in that folder (corrupt saves, index files) is skipped.
	if not ResourceLoader.exists(path):
		return null
	var res := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
	if res == null or not res is DigitalArtData:
		return null
	var a := EMCAssetData.new()
	a.asset_id = "user_%d" % _user_next
	_user_next += 1
	var art := res as DigitalArtData
	a.display_name = art.artwork_name if not art.artwork_name.is_empty() else stem
	a.category = CATEGORY_USER
	a.asset_type = "drawing"
	a.source_lab = "illustration"
	a.path = path
	return a