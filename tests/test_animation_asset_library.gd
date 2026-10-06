extends SceneTree

## EMC Asset Library test: built-in starters must always be present (the lab
## boots with an empty user:// and keeps working), user output directories
## must be scanned read-only and defensively (missing dirs -> skip, dead
## texture paths -> null, never a crash or an engine error), and prop
## starters come from metadata shapes rather than files.

const MISSING_PNG := "res://does_not_exist.png"

func _init() -> void:
	var failures := _run()
	if failures.is_empty():
		print("PASS: asset library falls back to starters and stays safe on missing user data")
		quit(0)
	else:
		for f in failures:
			print("FAIL: ", f)
		quit(1)


func _run() -> Array[String]:
	var failures: Array[String] = []

	var lib := EMCAssetLibrary.new()
	lib.refresh()
	if lib.list().is_empty():
		failures.append("list() is empty after refresh")
	if lib.list("character").is_empty():
		failures.append("no starter characters")
	var bgs := lib.list("background")
	if bgs.is_empty() or bgs[0].path.is_empty():
		failures.append("no starter background with a path")
	if lib.list("prop").size() != 2:
		failures.append("expected 2 starter props, got %d" % lib.list("prop").size())
	if lib.get_asset("definitely-missing") != null:
		failures.append("get_asset returned an asset for an unknown id")

	if lib.load_texture(bgs[0]) == null:
		failures.append("backdrop texture failed to load")
	var dead := EMCAssetData.new()
	dead.asset_id = "dead"
	dead.category = "user_art"
	dead.path = MISSING_PNG
	if lib.load_texture(dead) != null:
		failures.append("load_texture returned a texture for a dead path")

	# Review Focus 1: missing user directories must never crash, and the
	# starter inventory must survive with the exact same entry count.
	var rg := EMCAssetLibrary.new()
	rg.user_roots = ["user://no_such_dir_a", "user://no_such_dir_b"]
	rg.refresh()
	if rg.list("character").is_empty():
		failures.append("starters lost when user dirs missing")
	if rg.list().size() != StarterAssets.build().size():
		failures.append("entry count changed for missing user dirs")

	# Review Focus 2: user-art entry pointing at a dead file -> null texture.
	var dead_user := EMCAssetData.new()
	dead_user.asset_id = "user_x"
	dead_user.category = "user_art"
	dead_user.path = MISSING_PNG
	if rg.load_texture(dead_user) != null:
		failures.append("user-art load_texture returned a texture for a dead path")

	return failures