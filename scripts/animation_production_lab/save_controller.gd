class_name SaveController
extends RefCounted

## Safe round-trip for AnimationLabSaveData under base_dir (spec §3, RF1/RF5).
## The guided autosave lives at base_dir/guided.tres; Creative Studio projects
## live at base_dir/projects/<sanitized_name>.tres. Every load path returns a
## fully sanitized data or a fresh default — it never crashes on a missing,
## corrupt, or hand-tainted file.

const GUIDED_FILE := "guided.tres"

var base_dir := "user://animation_lab/"


func save_data(data: AnimationLabSaveData, project_name: String = "") -> bool:
	_ensure_dirs()
	if data == null:
		return false
	var err := ResourceSaver.save(data, _path_for(project_name))
	return err == OK


## Missing file -> defaults. Wrong-type / parse failure -> one push_warning +
## defaults. Successful load -> per-key type sanitize (RF5). Corrupt files are
## detected textually first so ResourceLoader (whose parse-error prints would
## trip the verify gate) is never handed garbage.
func load_data(project_name: String = "") -> AnimationLabSaveData:
	var path := _path_for(project_name)
	if not ResourceLoader.exists(path):
		return AnimationLabSaveData.new()
	if not _looks_like_lab_save(path):
		push_warning("animation_lab: corrupt or wrong-type save at %s — using defaults" % path)
		return AnimationLabSaveData.new()
	var loaded := ResourceLoader.load(path)
	if not loaded is AnimationLabSaveData:
		push_warning("animation_lab: corrupt or wrong-type save at %s — using defaults" % path)
		return AnimationLabSaveData.new()
	return _sanitize(loaded as AnimationLabSaveData)


## Cheap textual gate: a real AnimationLabSaveData .tres starts with
## [gd_resource and references the save-data script/script_class.
func _looks_like_lab_save(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var head := f.get_as_text()
	f.close()
	if not head.begins_with("[gd_resource"):
		return false
	return (
		head.contains("script_class=\"AnimationLabSaveData\"")
		or head.contains("animation_lab_save_data.gd")
	)


func list_projects() -> Array[Dictionary]:
	_ensure_dirs()
	var out: Array[Dictionary] = []
	var dir := DirAccess.open(_projects_dir())
	if dir == null:
		return out
	for file in dir.get_files():
		if not file.ends_with(".tres"):
			continue
		out.append({"name": file.get_basename(), "path": _projects_dir() + "/" + file})
	out.sort_custom(_by_project_name)
	return out


func project_exists(name: String) -> bool:
	return ResourceLoader.exists(_project_path(name))


func delete_project(name: String) -> bool:
	var path := _project_path(name)
	if not ResourceLoader.exists(path):
		return false
	var err := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return err == OK


func rename_project(old_name: String, new_name: String) -> bool:
	if old_name == new_name:
		return true
	if not project_exists(old_name) or project_exists(new_name):
		return false
	var old_abs := ProjectSettings.globalize_path(_project_path(old_name))
	var new_abs := ProjectSettings.globalize_path(_project_path(new_name))
	var err := DirAccess.rename_absolute(old_abs, new_abs)
	return err == OK


## RF5: every field is validated and coerced to its declared type; invalid or
## missing keys fall back to defaults. Fields are read through Variant
## intermediates so the type analyzer cannot narrow them (typed @export vars
## would make the is-checks infallible-false and trip warnings-as-errors).
## Array fields pass through with `is Array` (RF4 keeps ghost-target
## keyframes verbatim — evaluation stays safe because
## KeyframeController.evaluate() returns null for unknown targets).
func _sanitize(data: AnimationLabSaveData) -> AnimationLabSaveData:
	var out := AnimationLabSaveData.new()
	out.guided_completed = bool(data.guided_completed)
	out.current_assignment_id = str(data.current_assignment_id)
	if data.scene_objects is Array:
		out.scene_objects.assign(data.scene_objects)
	## Task 7: layer_order passthrough. String-filtered: a hand-edited save
	## could hold anything; the reorder pass only accepts real ids anyway.
	if data.layer_order is Array:
		for raw in data.layer_order:
			if raw is String:
				out.layer_order.append(raw)
	if data.camera_data is Dictionary:
		out.camera_data = data.camera_data.duplicate()
	if data.lighting_data is Dictionary:
		out.lighting_data = data.lighting_data.duplicate()
	if data.frames is Array:
		out.frames.assign(data.frames)
	if data.keyframes is Array:
		out.keyframes.assign(data.keyframes)
	var raw_fps: Variant = data.fps
	if raw_fps is int or raw_fps is String:
		out.fps = int(raw_fps)
	var raw_duration: Variant = data.duration
	if raw_duration is float or raw_duration is int:
		out.duration = float(raw_duration)
	if data.score_data is Dictionary:
		out.score_data = data.score_data.duplicate()
	var raw_hints: Variant = data.hints_used
	if raw_hints is int:
		out.hints_used = int(raw_hints)
	if data.creative_projects is Array:
		out.creative_projects.assign(data.creative_projects)
	return out


## Plan-S15 rule: every character outside [A-Za-z0-9_] becomes '_', so
## "a/b:c d" collides into "a_b_c_d" (the FileManager rule keeps alnum +
## underscore, but drops / and : — the plan's project test requires replace).
func _sanitize_filename(name: String) -> String:
	const KEEP := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"
	var result := ""
	for c in name:
		result += c if c in KEEP else "_"
	return result


func _path_for(project_name: String) -> String:
	if project_name.is_empty():
		return _base_dir() + GUIDED_FILE
	return _project_path(project_name)


func _project_path(name: String) -> String:
	return _projects_dir() + "/" + _sanitize_filename(name) + ".tres"


func _projects_dir() -> String:
	return _base_dir() + "projects"


func _base_dir() -> String:
	if base_dir.ends_with("/"):
		return base_dir
	return base_dir + "/"


func _ensure_dirs() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_base_dir()))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_projects_dir()))


func _by_project_name(a: Dictionary, b: Dictionary) -> bool:
	return str(a.get("name", "")) < str(b.get("name", ""))