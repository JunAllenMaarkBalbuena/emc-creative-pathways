extends Node

## Regression test: selecting an object must refresh the material panel
## (base-color swatch, metallic, roughness) to show THAT object's actual
## material values.
## Root cause: _on_selection_changed() only wired the transform gizmo. The
## material panel was refreshed exclusively inside _update_inspector(), which
## runs after transform drags / reset / center — never on selection, so the
## panel kept showing the previous (or default) object's color until the user
## moved the selected object.

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

	var swatch: ColorRect = lab.get_node("%ColorSwatch")
	var metallic: HSlider = lab.get_node("%MetallicSlider")
	var roughness: HSlider = lab.get_node("%RoughnessSlider")

	# Two objects with very different materials.
	var cube_a: MeshInstance3D = lab.spawner.spawn(PrimitiveDef.Type.CUBE, lab.object_container)
	cube_a.position = Vector3(-2, 0.5, 0)
	lab.material_manager.apply_to(cube_a, {albedo = Color(0.9, 0.1, 0.1), metallic = 0.9, roughness = 0.3})
	lab.selection_manager.select(cube_a)
	await tree.process_frame
	# After selecting A the panel must already show A's material (no drag yet).
	var a_ok := swatch.color.is_equal_approx(Color(0.9, 0.1, 0.1)) \
		and is_equal_approx(metallic.value, 0.9) \
		and is_equal_approx(roughness.value, 0.3)
	if not a_ok:
		_fail += 1
		print("FAIL: selecting cube A did not show its base color/material "
				+ "(swatch=%s metallic=%.2f roughness=%.2f)" % [swatch.color, metallic.value, roughness.value])

	# Select a SECOND object with a different material: the panel must now show B.
	var cube_b: MeshInstance3D = lab.spawner.spawn(PrimitiveDef.Type.CYLINDER, lab.object_container)
	cube_b.position = Vector3(2, 0.5, 0)
	lab.material_manager.apply_to(cube_b, {albedo = Color(0.1, 0.3, 0.9), metallic = 0.0, roughness = 0.9})
	lab.selection_manager.select(cube_b)
	await tree.process_frame
	var b_ok := swatch.color.is_equal_approx(Color(0.1, 0.3, 0.9)) \
		and is_equal_approx(metallic.value, 0.0) \
		and is_equal_approx(roughness.value, 0.9)
	if not b_ok:
		_fail += 1
		print("FAIL: switching selection to cube B must update the panel to B's material "
				+ "(swatch=%s metallic=%.2f roughness=%.2f, want 0.1,0.3,0.9 / 0.0 / 0.9)"
				% [swatch.color, metallic.value, roughness.value])

	# Deselect must reset the panel to defaults (nothing selected = no material).
	lab.selection_manager.deselect_all()
	await tree.process_frame
	if swatch.color != Color.WHITE or not is_equal_approx(metallic.value, 0.0) or not is_equal_approx(roughness.value, 0.5):
		_fail += 1
		print("FAIL: deselect must reset the material panel to defaults "
				+ "(swatch=%s metallic=%.2f roughness=%.2f)" % [swatch.color, metallic.value, roughness.value])

	if _fail == 0:
		print("PASS: selecting an object immediately shows its base color and material in the panel")
	_quit()

func _on_watchdog():
	get_tree().quit(2)

func _quit():
	get_tree().quit(1 if _fail > 0 else 0)