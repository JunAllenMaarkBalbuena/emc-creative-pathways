extends Node

## Regression test: the GridToggle in the modeling lab toolbar must actually
## show/hide the grid. It previously only stored a flag on SnapSettings that
## nothing read, so the toggle did nothing.

var _fail := 0

func _ready() -> void:
	var tree := get_tree()
	var lab: ModelingLab = (load("res://scenes/modeling_lab/modeling_lab.tscn") as PackedScene).instantiate()
	add_child(lab)
	tree.create_timer(20.0).timeout.connect(_on_watchdog)
	await tree.process_frame
	await tree.process_frame

	var plane := lab.workspace.get_node_or_null("GridPlane") as MeshInstance3D
	if plane == null:
		_fail += 1
		print("FAIL: lab workspace has no GridPlane")
		_quit()
		return

	var toggle: CheckButton = lab.get_node("%GridToggle")
	if toggle == null or not toggle.button_pressed:
		_fail += 1
		print("FAIL: grid toggle should default to on")

	# Turn the grid OFF -> plane must hide and the flag must clear.
	toggle.button_pressed = false
	await tree.process_frame
	if plane.visible:
		_fail += 1
		print("FAIL: turning the grid toggle off left the grid visible")
	if lab.snap_settings.grid_visible:
		_fail += 1
		print("FAIL: turning the grid toggle off did not clear grid_visible")

	# Turn it back ON -> plane must show again.
	toggle.button_pressed = true
	await tree.process_frame
	if not plane.visible:
		_fail += 1
		print("FAIL: turning the grid toggle on did not show the grid")
	if not lab.snap_settings.grid_visible:
		_fail += 1
		print("FAIL: turning the grid toggle on did not set grid_visible")

	if _fail == 0:
		print("PASS: GridToggle shows and hides the workspace grid")
	_quit()

func _on_watchdog():
	get_tree().quit(2)

func _quit():
	get_tree().quit(1 if _fail > 0 else 0)