extends Node

## Post-task-17 review regression: depth and layer must survive a
## collect -> apply round trip through the root snapshot path (spec §3 puts
## both in scene_objects). A studio Load rebuilds the world with
## _apply_project_data; this harness drives collect_save_data() ->
## _apply_project_data(data) directly and asserts the restored object keeps
## its z-depth offset and layer ordering.
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
		print("PASS: depth and layer survive the collect -> apply round trip")
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

	# Stage a library-backed object with a real depth and layer.
	var char_assets := lab.library.list("character")
	if char_assets.is_empty():
		failures.append("no character starter to stage")
		return failures
	var asset := char_assets[0]
	var obj_id := lab.world.add_asset(asset, Vector3(0, 0.5, 0))
	lab.world.set_object_depth(obj_id, 2.0)
	lab.world.set_object_layer(obj_id, 1)

	# The serialized scene_objects entries must carry both fields.
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

	# Restore: the world is rebuilt exactly as a studio Load does.
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

	lab.queue_free()
	await get_tree().process_frame
	return failures


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