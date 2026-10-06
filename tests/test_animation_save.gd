extends SceneTree

## Task 15: SaveController + AnimationLabSaveData safe round-trip. Exercises
## the guided autosave + Creative Studio project CRUD under an injected test
## base_dir, corrupt-file fallback (RF1/RF5), name sanitization, and verbatim
## ghost-target keyframe arrays (RF4). The real user://animation_lab/ dir is
## never touched.

const BASE := "user://animation_lab_test/"

func _init() -> void:
	_wipe_dir(BASE)
	var failures := _run()
	_wipe_dir(BASE)
	if failures.is_empty():
		print("PASS: save/load round-trip with sanitization and corrupt fallback")
		quit(0)
	else:
		for f in failures:
			print("FAIL: ", f)
		quit(1)


func _run() -> Array[String]:
	var failures: Array[String] = []
	var save := SaveController.new()
	save.base_dir = BASE

	# --- guided round-trip -------------------------------------------------
	var data := AnimationLabSaveData.new()
	data.guided_completed = true
	data.current_assignment_id = "day_in_emc_lab"
	data.scene_objects = [
		{"id": "obj_1", "category": "character"},
		{"id": "obj_2", "category": "prop"},
	]
	data.camera_data = {
		"position": Vector3(0, 0.8, 4),
		"rotation_degrees": Vector3.ZERO,
		"fov": 60.0,
	}
	data.lighting_data = {"lights": [{"id": "starter_key", "kind": 0, "energy": 1.0}]}
	data.frames = [
		{"texture": "res://assets/Scene_BG/Menu_Bg_image.png", "duration": 0.1},
		{"texture": "", "duration": 0.2},
	]
	data.keyframes = [
		{
			"time": 0.0, "target_id": "obj_1", "target_type": 0,
			"property_path": "position", "value": Vector3(0, 0.5, 0),
			"interpolation": 0,
		},
	]
	data.fps = 12
	data.duration = 5.0
	data.score_data = {"total": 97.5, "creativity": 75.0}
	data.hints_used = 3
	data.creative_projects = [{"name": "proj"}]

	if not save.save_data(data):
		failures.append("guided save should succeed")
	var loaded := save.load_data()
	if loaded == null:
		failures.append("guided load should return a data object")
	elif _differs(loaded, data):
		failures.append("guided round-trip fields should equal the saved data")

	# --- Creative Studio projects -----------------------------------------
	if not save.save_data(data, "My Project"):
		failures.append("named project save should succeed")
	if not save.project_exists("My Project"):
		failures.append("saved project should exist")
	if not save.rename_project("My Project", "Renamed"):
		failures.append("rename should succeed")
	if not save.project_exists("Renamed") or save.project_exists("My Project"):
		failures.append("rename should move the project")
	if not save.delete_project("Renamed"):
		failures.append("delete should succeed")
	if save.project_exists("Renamed"):
		failures.append("deleted project should be gone")
	if not save.save_data(data, "a/b:c d"):
		failures.append("save with an awkward name should succeed")
	var names := _project_names(save.list_projects())
	if not names.has("a_b_c_d"):
		failures.append("sanitized project name should be a_b_c_d, got %s" % str(names))

	# --- RF1/RF5: missing, garbage, hand-tainted files --------------------
	var missing := save.load_data("nope")
	if missing.guided_completed or missing.frames.size() != 0:
		failures.append("missing save should load defaults")

	if not save.save_data(data, "tainted"):
		failures.append("tainted seed save should succeed")
	var gf := FileAccess.open(
		ProjectSettings.globalize_path(BASE + "projects/tainted.tres"), FileAccess.WRITE)
	gf.store_string("garbage not a resource")
	gf.close()
	var garbage := save.load_data("tainted")
	if garbage.guided_completed or garbage.frames.size() != 0:
		failures.append("garbage save should load defaults")

	var hf := FileAccess.open(
		ProjectSettings.globalize_path(BASE + "guided.tres"), FileAccess.WRITE)
	hf.store_string(_hand_tainted_guided_tres())
	hf.close()
	var hand := save.load_data()
	if not (hand.guided_completed is bool and hand.guided_completed):
		failures.append("int guided_completed should sanitize to bool true")
	if not (hand.fps is int and hand.fps == 12):
		failures.append("string fps should sanitize to int 12")

	# --- RF4: ghost-target keyframes load verbatim -------------------------
	var ghost := AnimationLabSaveData.new()
	ghost.keyframes = [
		{
			"time": 0.5, "target_id": "ghost", "target_type": 0,
			"property_path": "position", "value": Vector3.ZERO,
			"interpolation": 0,
		},
	]
	if not save.save_data(ghost, "GhostProj"):
		failures.append("ghost project save should succeed")
	var ghost_loaded := save.load_data("GhostProj")
	if ghost_loaded.keyframes.size() != 1:
		failures.append("ghost-target keyframes should round-trip verbatim")
	elif str(ghost_loaded.keyframes[0].get("target_id", "")) != "ghost":
		failures.append("ghost target id should survive")

	return failures


func _differs(a: AnimationLabSaveData, b: AnimationLabSaveData) -> bool:
	if a.guided_completed != b.guided_completed:
		return true
	if a.current_assignment_id != b.current_assignment_id:
		return true
	if a.fps != b.fps or a.duration != b.duration:
		return true
	if a.scene_objects != b.scene_objects:
		return true
	if a.camera_data != b.camera_data:
		return true
	if a.lighting_data != b.lighting_data:
		return true
	if a.frames != b.frames:
		return true
	if a.keyframes != b.keyframes:
		return true
	if a.score_data != b.score_data:
		return true
	if a.hints_used != b.hints_used:
		return true
	if a.creative_projects != b.creative_projects:
		return true
	return false


func _project_names(projects: Array[Dictionary]) -> Array[String]:
	var out: Array[String] = []
	for p in projects:
		out.append(str(p.get("name", "")))
	return out


func _hand_tainted_guided_tres() -> String:
	var txt := '[gd_resource type="Resource" script_class="AnimationLabSaveData" load_steps=2 format=3]'
	txt += "\n[ext_resource type=\"Script\" path=\"res://scripts/animation_production_lab/data/animation_lab_save_data.gd\" id=\"1_data\"]\n"
	txt += "[resource]\nscript = ExtResource(\"1_data\")\n"
	txt += "guided_completed = 1\nfps = \"12\"\nduration = 5.0\n"
	return txt


func _wipe_dir(path: String) -> void:
	var abs := ProjectSettings.globalize_path(path)
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file in dir.get_files():
		DirAccess.remove_absolute(abs + "/" + file)
	for sub in dir.get_directories():
		_wipe_dir(path + "/" + sub)
	dir = DirAccess.open(path)
	DirAccess.remove_absolute(abs)