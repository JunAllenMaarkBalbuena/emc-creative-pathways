extends SceneTree

## Task 16: Creative Studio project CRUD over the Task 15 save layer, using an
## injected temp base_dir. Exercises new (with duplicate refusal and a blank
## but immediately playable project), load, duplicate, rename, delete, list,
## and save_current round-trip. The real user://animation_lab/ dir is never
## touched.

const BASE := "user://animation_lab_studio_test/"


func _init() -> void:
	_wipe_dir(BASE)
	var failures := _run()
	_wipe_dir(BASE)
	if failures.is_empty():
		print("PASS: creative studio project CRUD over the save layer")
		quit(0)
	else:
		for f in failures:
			print("FAIL: ", f)
		quit(1)


func _run() -> Array[String]:
	var failures: Array[String] = []
	var studio := CreativeStudioController.new()
	var save := SaveController.new()
	save.base_dir = BASE
	studio.save = save

	# --- new_project: create + duplicate refusal + playable blank ----------
	if not studio.new_project("A"):
		failures.append("new_project(A) should succeed")
	if studio.new_project("A"):
		failures.append("duplicate name should be refused")

	var loaded := studio.load_project("A")
	if loaded == null:
		failures.append("load_project(A) should return data")
	else:
		if loaded.frames.size() != 1:
			failures.append("blank project must ship with exactly one frame (immediately playable)")
		if loaded.fps <= 0 or loaded.duration <= 0.0:
			failures.append("blank project must have default fps/duration")

	# --- duplicate / rename / delete ---------------------------------------
	if not studio.duplicate_project("A"):
		failures.append("duplicate_project(A) should succeed")
	if not studio.save.project_exists("A (copy)"):
		failures.append("duplicate should create a (copy) project")

	if not studio.rename_project("A (copy)", "B"):
		failures.append("rename should succeed")
	if not studio.list_projects().has("B") or studio.save.project_exists("A (copy)"):
		failures.append("rename should move the project")

	if not studio.delete_project("B"):
		failures.append("delete should succeed")
	if studio.list_projects().has("B"):
		failures.append("deleted project should be gone")

	# --- save_current round-trip through the controller --------------------
	var out := AnimationLabSaveData.new()
	out.guided_completed = true
	out.frames = [{"texture": "", "duration": 0.2}]
	out.fps = 24
	if not studio.save_current(out, "FromCtrl"):
		failures.append("save_current should succeed")
	var back := studio.load_project("FromCtrl")
	if back == null:
		failures.append("save_current round-trip should load")
	else:
		if not back.guided_completed or back.fps != 24 or back.frames.size() != 1:
			failures.append("save_current round-trip should preserve fields")

	# --- list_projects matches the files -----------------------------------
	var names := studio.list_projects()
	names.sort()
	if names != ["A", "FromCtrl"]:
		failures.append("list_projects should match the files, got %s" % str(names))
	return failures


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