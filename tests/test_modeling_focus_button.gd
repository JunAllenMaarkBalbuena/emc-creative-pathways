extends Node

## Regression test: the modeling lab toolbar must have a Focus button that
## swings the camera to look at the selected object (same behavior as the F
## shortcut). The button was missing from the 3D lab UI entirely.

var _fail := 0

func _ready() -> void:
	var tree := get_tree()
	var lab: ModelingLab = (load("res://scenes/modeling_lab/modeling_lab.tscn") as PackedScene).instantiate()
	add_child(lab)
	tree.create_timer(20.0).timeout.connect(_on_watchdog)
	await tree.process_frame
	await tree.process_frame

	lab._enter_creative_studio()
	await tree.process_frame
	lab._on_spawn_selected(PrimitiveDef.Type.CUBE)
	await tree.process_frame
	var cube: MeshInstance3D = lab.selection_manager.get_selected() as MeshInstance3D
	if cube == null:
		_fail += 1
		print("FAIL: no cube spawned/selected")
		_quit()
		return
	cube.position = Vector3(2, 1, 3)
	await tree.process_frame

	# The Focus button must actually exist in the lab UI.
	var focus_btn: Button = lab.get_node_or_null("%FocusBtn")
	if focus_btn == null:
		_fail += 1
		print("FAIL: no Focus button in the modeling lab UI")
		_quit()
		return

	# Normalize camera, then press exactly what pressing the button does.
	lab.camera_controller.reset_view()
	await tree.process_frame
	var cam: Camera3D = lab.camera_controller.camera
	var cam_before: Vector3 = cam.global_position

	focus_btn.emit_signal("pressed")
	await tree.process_frame

	if cam.global_position.distance_to(cam_before) < 0.01:
		_fail += 1
		print("FAIL: pressing Focus did not move the camera to the selected object")

	var to_cube: Vector3 = (cube.global_position - cam.global_position).normalized()
	var forward: Vector3 = -cam.global_transform.basis.z
	if to_cube.angle_to(forward) > 0.3:
		_fail += 1
		print("FAIL: camera is not looking at the selected cube after Focus (angle %.3f)" % to_cube.angle_to(forward))

	if _fail == 0:
		print("PASS: Focus button swings the camera to the selected object")
	_quit()

func _on_watchdog():
	get_tree().quit(2)

func _quit():
	get_tree().quit(1 if _fail > 0 else 0)