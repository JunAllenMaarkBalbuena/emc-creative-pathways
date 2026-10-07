extends Node

## Post-task-17 review regression: depth and layer must survive a
## collect -> apply round trip through the root snapshot path (spec §3 puts
## both in scene_objects). A studio Load rebuilds the world with
## _apply_project_data; this harness drives collect_save_data() ->
## _apply_project_data(data) directly and asserts the restored object keeps
## its z-depth offset and layer ordering.
##
## Task 7 extends the round trip to the composition stack: layer_order
## serializes the ordered scene-object ids (from world.layer_order()), the
## entries carry display_name/element_type/locked, and _apply_project_data
## restores order (mapping old ids -> regenerated ids by traversal index,
## then a reorder pass), names and locks — with locks applied AFTER the
## reorder because reorder_layer refuses locked layers (the saved order must
## land even for locked entries). Back-compat (Review-Focus #4): a save
## written before this round has no layer_order and no display_name/locked
## keys; it must load in insertion order with every layer unlocked, no crash.
##
## The lab boots reading user://animation_lab/guided.tres (spec §15); the
## harness backs it up and restores it, mirroring test_animation_guided_flow.

const LAB := "res://scenes/animation_production_lab/animation_production_lab.tscn"
const SAVE_GUIDED := "user://animation_lab/guided.tres"

var _failures: Array[String] = []


func _ready() -> void:
	var tree := get_tree()
	var guided_backup := _backup_guided_file()
	_failures = await _run()
	_restore_guided_file(guided_backup)
	if _failures.is_empty():
		print("PASS: depth/layer/order/names/locks survive the collect -> apply round trip")
		tree.quit(0)
	else:
		for f in _failures:
			print("FAIL: ", f)
		tree.quit(1)


func _run() -> Array[String]:
	var failures: Array[String] = []
	var lab := load(LAB).instantiate() as AnimationProductionLab
	add_child(lab)
	await get_tree().process_frame

	# --- Part 1: depth + layer (pre-existing regression) ---------------------
	var char_assets := lab.library.list("character")
	if char_assets.is_empty():
		failures.append("no character starter to stage")
		return failures
	var asset := char_assets[0]
	var obj_id := lab.world.add_asset(asset, Vector3(0, 0.5, 0))
	lab.world.set_object_depth(obj_id, 2.0)
	lab.world.set_object_layer(obj_id, 1)

	var snapshot := lab.collect_save_data()
	var entry: Dictionary = {}
	for obj in snapshot.scene_objects:
		if str(obj.get("asset_id", "")) == asset.asset_id:
			entry = obj
			break
	if not entry.has("depth") or not entry.has("layer"):
		failures.append("collect should serialize depth and layer for scene objects")
		return failures
	if float(entry["depth"]) != 2.0 or int(entry["layer"]) != 1:
		failures.append("collect should carry the staged depth/layer")

	lab._apply_project_data(snapshot)
	var restored := ""
	for oid in lab.world.all_objects():
		if str(lab.world.get_object(oid).get("asset_id", "")) == asset.asset_id:
			restored = oid
			break
	if restored.is_empty():
		failures.append("apply should rebuild the library-backed object")
		return failures
	var data := lab.world.get_object(restored)
	if float(data.get("depth", 0.0)) != 2.0:
		failures.append("depth should survive the round trip")
	if int(data.get("layer", 0)) != 1:
		failures.append("layer should survive the round trip")

	# --- Part 2: the composition stack round-trips (Task 7) ------------------
	lab._apply_project_data(AnimationLabSaveData.new())  # wipe the world
	await get_tree().process_frame
	var bg_asset := lab.library.list("background")[0]
	var prop_asset := lab.library.list("prop")[0]
	var id_char := lab.world.add_asset(asset, Vector3(0, 0.5, 0))
	var id_bg := lab.world.add_asset(bg_asset, Vector3(0, 0, -1))
	var id_prop := lab.world.add_asset(prop_asset, Vector3(1, 0, 0))
	if not lab.world.layer_to_front(id_char):
		failures.append("part 2 setup: char should reach the front")
	lab.world.rename_layer(id_char, "Hero")
	lab.world.set_layer_locked(id_char, true)

	var snap2 := lab.collect_save_data()
	if snap2.layer_order != [id_bg, id_prop, id_char]:
		failures.append("collect should serialize the stack order, got %s" % [snap2.layer_order])
	var char_entry: Dictionary = {}
	var prop_entry: Dictionary = {}
	for obj in snap2.scene_objects:
		if str(obj.get("id", "")) == id_char:
			char_entry = obj
		if str(obj.get("id", "")) == id_prop:
			prop_entry = obj
	if str(char_entry.get("display_name", "")) != "Hero":
		failures.append("collect should serialize the renamed display_name")
	if not bool(char_entry.get("locked", false)):
		failures.append("collect should serialize locked")
	if str(prop_entry.get("element_type", "")) != "3d":
		failures.append("collect should serialize element_type (prop -> 3d)")

	lab._apply_project_data(snap2)
	var order2 := lab.world.layer_order()
	if order2.size() != 3:
		failures.append("apply should rebuild all 3 objects")
		return failures
	var by_name := {}
	for oid in order2:
		by_name[str(lab.world.get_object(oid).get("display_name", ""))] = oid
	if not by_name.has("Hero") or not by_name.has(bg_asset.display_name) \
			or not by_name.has(prop_asset.display_name):
		failures.append("apply should restore renamed + asset-named layers")
	else:
		var expected := [by_name[bg_asset.display_name], by_name[prop_asset.display_name], by_name["Hero"]]
		if expected != order2:
			failures.append("apply should restore the saved stack order, got %s" % [order2])
	var hero_data := lab.world.get_object(by_name.get("Hero", ""))
	if not bool(hero_data.get("locked", false)):
		failures.append("apply should restore locked")
	if str(hero_data.get("display_name", "")) != "Hero":
		failures.append("apply should restore the renamed label")

	# --- Part 3: back-compat (Review-Focus #4) ------------------------------
	# A save written before this round: scene_objects entries carry only the
	# pre-Task-7 fields (no display_name/element_type/locked), and no
	# layer_order at all. It must load in insertion order, all unlocked.
	var legacy := AnimationLabSaveData.new()
	legacy.scene_objects = [
		_entry("old_bg", bg_asset),
		_entry("old_char", asset),
		_entry("old_prop", prop_asset),
	]
	lab._apply_project_data(legacy)
	var order3 := lab.world.layer_order()
	if order3.size() != 3:
		failures.append("back-compat: apply should rebuild all 3 legacy objects")
		return failures
	var got_names: Array[String] = []
	for oid in order3:
		got_names.append(str(lab.world.get_object(oid).get("display_name", "")))
	var expected_names := [bg_asset.display_name, asset.display_name, prop_asset.display_name]
	if got_names != expected_names:
		failures.append("back-compat: expected insertion order %s, got %s" % [expected_names, got_names])
	for oid in order3:
		if bool(lab.world.get_object(oid).get("locked", false)):
			failures.append("back-compat: legacy layers must load unlocked")

	lab.queue_free()
	await get_tree().process_frame
	return failures


## A scene_objects entry exactly as the pre-Task-7 writer produced them.
func _entry(id: String, a: EMCAssetData) -> Dictionary:
	return {
		"id": id,
		"category": a.category,
		"asset_id": a.asset_id,
		"position": Vector3.ZERO,
		"rotation_degrees": Vector3.ZERO,
		"scale": Vector3.ONE,
		"visible": true,
		"depth": 0.0,
		"layer": 0,
	}


func _backup_guided_file() -> String:
	if not FileAccess.file_exists(SAVE_GUIDED):
		return ""
	return FileAccess.get_file_as_string(SAVE_GUIDED)


func _restore_guided_file(backup: String) -> void:
	if backup.is_empty():
		if FileAccess.file_exists(SAVE_GUIDED):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_GUIDED))
		return
	var f := FileAccess.open(SAVE_GUIDED, FileAccess.WRITE)
	if f != null:
		f.store_string(backup)