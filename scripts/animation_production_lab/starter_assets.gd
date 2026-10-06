class_name StarterAssets
extends RefCounted

## Code-built index of the committed starter assets (design spec §12):
## character frame sets (idle + run), the lab backdrop, and two primitive
## props. The assets are referenced IN PLACE — these are the files the
## project already ships — rather than copied to res://data/asset_library/.
## This is a declared deviation from the spec's wording ("copied to
## res://data/asset_library/"): copying would duplicate art; referencing the
## committed paths keeps the identical built-in inventory with zero copies.

const IDLE_DIR := "res://assets/char_animation/idle"
const RUN_DIR := "res://assets/char_animation/run"
const BACKDROP_PATH := "res://assets/Scene_BG/Menu_Bg_image.png"


static func build() -> Array[EMCAssetData]:
	var out: Array[EMCAssetData] = []
	_append_frames(out, IDLE_DIR, "idle")
	_append_frames(out, RUN_DIR, "run")
	out.append(_backdrop())
	out.append(_prop("starter_prop_box", "Workstation Box", "box", Color(0.35, 0.45, 0.6)))
	out.append(_prop("starter_prop_cylinder", "Storage Cylinder", "cylinder", Color(0.5, 0.3, 0.2)))
	return out


static func _append_frames(out: Array[EMCAssetData], dir_path: String, pose: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	var names: Array[String] = []
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.ends_with(".png"):
			names.append(name)
		name = dir.get_next()
	dir.list_dir_end()
	names.sort()
	for i in names.size():
		var a := EMCAssetData.new()
		a.asset_id = "starter_char_%s_%d" % [pose, i]
		a.display_name = names[i].get_basename()
		a.category = "character"
		a.asset_type = "sprite"
		a.source_lab = "starter"
		a.path = dir_path + "/" + names[i]
		a.metadata = {"pose": pose}
		out.append(a)


static func _backdrop() -> EMCAssetData:
	var a := EMCAssetData.new()
	a.asset_id = "starter_bg_lab_backdrop"
	a.display_name = "Lab Backdrop"
	a.category = "background"
	a.asset_type = "sprite"
	a.source_lab = "starter"
	a.path = BACKDROP_PATH
	return a


static func _prop(id: String, display_name: String, shape: String, color: Color) -> EMCAssetData:
	var a := EMCAssetData.new()
	a.asset_id = id
	a.display_name = display_name
	a.category = "prop"
	a.asset_type = "primitive"
	a.source_lab = "starter"
	a.path = ""
	a.metadata = {"shape": shape, "color": color}
	return a