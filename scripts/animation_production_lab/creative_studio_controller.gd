class_name CreativeStudioController
extends Node

## Creative Studio project CRUD (Task 16, spec §5). A thin delegate over the
## Task 15 SaveController: project files live in base_dir/projects/ and every
## successful mutation refreshes `projects` — the {name, path} mirror the
## StudioPanel binds to. The pipeline itself (world/timeline/frames/etc.) is
## the lab's; this controller only manages project files and the current
## working snapshot.

var save: SaveController
var projects: Array[Dictionary] = []


func refresh() -> void:
	if save == null:
		projects = []
		return
	projects = save.list_projects()


## Blank, immediately playable project (Task 7's min-1 frame invariant), or
## false on empty / duplicate name. The new project file becomes the current
## working set when the root loads it.
func new_project(name: String) -> bool:
	var clean := name.strip_edges()
	if clean.is_empty() or save == null or save.project_exists(clean):
		return false
	var data := AnimationLabSaveData.new()
	data.fps = 12
	data.duration = 5.0
	data.frames = [{"texture": "", "duration": 0.1}]
	if not save.save_data(data, clean):
		return false
	refresh()
	return true


func load_project(name: String) -> AnimationLabSaveData:
	if save == null:
		return null
	return save.load_data(name)


func save_current(data: AnimationLabSaveData, name: String) -> bool:
	if data == null or save == null:
		return false
	var ok := save.save_data(data, name)
	if ok:
		refresh()
	return ok


func rename_project(old_name: String, new_name: String) -> bool:
	if save == null:
		return false
	var ok := save.rename_project(old_name, new_name)
	if ok:
		refresh()
	return ok


## Copies the project file to "<name> (copy)"; refuses when a duplicate-name
## collision exists (both source missing and copy-name taken).
func duplicate_project(name: String) -> bool:
	if save == null or not save.project_exists(name):
		return false
	var copy_name := name + " (copy)"
	if save.project_exists(copy_name):
		return false
	var data := save.load_data(name)
	if data == null:
		return false
	var ok := save.save_data(data, copy_name)
	if ok:
		refresh()
	return ok


func delete_project(name: String) -> bool:
	if save == null:
		return false
	var ok := save.delete_project(name)
	if ok:
		refresh()
	return ok


func list_projects() -> Array[String]:
	if save == null:
		return []
	var out: Array[String] = []
	for entry in save.list_projects():
		out.append(str(entry.get("name", "")))
	return out