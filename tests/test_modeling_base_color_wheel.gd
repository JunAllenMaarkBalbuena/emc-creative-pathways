extends SceneTree

## RGBA base-color wheel guard for the modeling-lab Materials panel.
## Covers what the guard can't see on screen:
##   - clicking %ColorSwatch must expand the shared ColorPickerControl (not randomize)
##   - the wheel must round-trip alpha so the RGBA color stays honest
##   - material_manager still applies RGBA honestly (existing alpha guard)

const SCENE := "res://scenes/modeling_lab/modeling_lab.tscn"
const ANIMATED_ONLY := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	var fail := 0

	var scene: Node = load(SCENE).instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	var swatch := scene.get_node_or_null("%ColorSwatch")
	if swatch == null:
		print("FAIL: %ColorSwatch not found in loaded scene")
		quit(1)
		return
	var wheel_parent := swatch.get_parent()
	var wheel := wheel_parent.find_child("BaseColorWheel", true, false)
	if wheel == null:
		print("FAIL: base-color wheel was not added to the Materials panel")
		quit(1)
		return
	if wheel.visible:
		fail += 1
		print("FAIL: base-color wheel should start collapsed (visible=false)")

	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	var lab: Node = scene
	lab._on_color_swatch_clicked(click)
	if not wheel.visible:
		fail += 1
		print("FAIL: clicking %ColorSwatch did not expand the base-color wheel")

	wheel.set_color(Color(0.2, 0.5, 0.9, 0.4))
	if not is_equal_approx(wheel.get_color().a, 0.4):
		fail += 1
		print("FAIL: wheel did not round-trip alpha (got a=",
			wheel.get_color().a, ")")

	var echoed: Color = Color.WHITE
	wheel.color_changed.connect(func(c): echoed = c)
	wheel._pick_alpha(Vector2(wheel.wheel_radius * 2 + 20.0, 8.0), Vector2(wheel.wheel_radius * 2 + 20.0, 8.0))
	if not is_equal_approx(echoed.a, 1.0):
		fail += 1
		print("FAIL: alpha pick did not emit color_changed with alpha (got=", echoed.a, ")")

	# Preset selection must reflect in the color wheel (its RGBA setup).
	var target := scene.get_node_or_null(
		"SubViewportContainer/SubViewport/Workspace/ObjectContainer")
	var mesh: MeshInstance3D = null
	if target:
		for child in target.get_children():
			if child is MeshInstance3D:
				mesh = child
				break
	if mesh == null:
		mesh = MeshInstance3D.new()
		mesh.name = "GuardCube"
		mesh.mesh = BoxMesh.new()
		root.call_deferred("add_child", mesh)
		await process_frame
		await process_frame
	var lab_sel: Node = scene
	lab_sel.selection_manager.select_node(mesh)
	await process_frame
	await process_frame
	lab_sel._on_preset_pressed("glass")
	if not is_equal_approx(wheel.get_color().a, 0.3):
		fail += 1
		print("FAIL: glass preset did not reflect in wheel (expected a=0.3, got=",
			wheel.get_color().a, ")")
	var want_hue := Color(0.85, 0.9, 1.0, 0.3).h
	if absf(wheel.get_color().h - want_hue) > 0.01:
		fail += 1
		print("FAIL: glass preset did not reflect albedo hue in wheel (got=",
			wheel.get_color().h, " expected=", want_hue, ")")

	if fail == 0:
		print("PASS: base-color wheel expands on click, honors alpha, and mirrors presets")
	quit(1 if fail > 0 else 0)