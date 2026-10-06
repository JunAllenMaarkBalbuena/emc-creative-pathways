extends Node

## Gate: the main menu must expose the 2.5D Animation Production Lab as a
## fourth tool-lab entry (button + exported scene path), and the button must
## be visible on every platform (it is not an editor-only entry). The lab
## scene file itself arrives in Task 2; here we verify the wiring points at
## the canonical scene path and the button exists and is interactive.

var _fail := 0

func _ready() -> void:
	var tree := get_tree()
	_fail = await _run()
	tree.quit(_fail)


func _run() -> int:
	var packed := load("res://scenes/main_menu.tscn") as PackedScene
	if packed == null:
		print("FAIL: main_menu.tscn failed to load")
		return 1
	var main := packed.instantiate()
	add_child(main)
	await get_tree().process_frame

	if main.get_node_or_null("AnimButton") == null:
		print("FAIL: main menu has no AnimButton")
		return 1
	var path: String = main.animation_production_lab_path
	if path.is_empty() or not path.ends_with("animation_production_lab.tscn"):
		print("FAIL: animation_production_lab_path not configured: ", path)
		return 1
	if not main.get_node("AnimButton").visible:
		print("FAIL: AnimButton is hidden")
		return 1
	print("PASS: main menu exposes the animation lab entry")
	return 0