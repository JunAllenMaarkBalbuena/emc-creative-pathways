extends Control

## Creative Studio panel (Task 16): project name field, CRUD buttons, and a
## project list bound by the root to CreativeStudioController. Class_name-less
## on purpose (the root types it via a preload const, like every other panel).

signal new_requested(name: String)
signal save_requested(name: String)
signal load_requested(name: String)
signal rename_requested(name: String, new_name: String)
signal duplicate_requested(name: String)
signal delete_requested(name: String)

@onready var name_edit: LineEdit = %NameEdit
@onready var project_list: ItemList = %ProjectList
@onready var status_label: Label = %StatusLabel


func set_projects(names: Array[String]) -> void:
	project_list.clear()
	for name in names:
		project_list.add_item(name)


func selected() -> String:
	var items := project_list.get_selected_items()
	if items.is_empty():
		return ""
	return project_list.get_item_text(items[0])


func set_status(text: String) -> void:
	status_label.text = text


func _on_new_pressed() -> void:
	new_requested.emit(name_edit.text)


func _on_save_pressed() -> void:
	var name := name_edit.text.strip_edges()
	if name.is_empty():
		name = selected()
	save_requested.emit(name)


func _on_load_pressed() -> void:
	var name := selected()
	if name != "":
		load_requested.emit(name)


func _on_rename_pressed() -> void:
	var name := selected()
	var new_name := name_edit.text.strip_edges()
	if name != "" and new_name != "":
		rename_requested.emit(name, new_name)


func _on_duplicate_pressed() -> void:
	var name := selected()
	if name != "":
		duplicate_requested.emit(name)


func _on_delete_pressed() -> void:
	var name := selected()
	if name != "":
		delete_requested.emit(name)