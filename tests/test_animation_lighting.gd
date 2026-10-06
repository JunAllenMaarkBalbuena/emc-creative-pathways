extends SceneTree

## LightingController test: add/remove/select lights under lighting_root with
## a GL-Compat budget cap (at most 1 directional + 1 omni — adding a second
## of either kind returns "" and adds nothing), intensity clamped to
## [0.0, 5.0], shadows toggling, and the scoring measures the feedback layer
## reads: key_light_exists (directional with energy > 0) and the intensity
## floor. Unknown types and ids are silent no-ops.

func _init() -> void:
	var failures := _run()
	if failures.is_empty():
		print("PASS: lighting controller respects budget and exposes scoring measures")
		quit(0)
	else:
		for f in failures:
			print("FAIL: ", f)
		quit(1)


func _run() -> Array[String]:
	var failures: Array[String] = []
	var stage := Node3D.new()
	var lights_root := Node3D.new()
	lights_root.name = "Lights"
	stage.add_child(lights_root)
	var ctrl := LightingController.new()
	stage.add_child(ctrl)
	ctrl.lighting_root = NodePath("../Lights")

	var key := ctrl.add_light(LightingController.LIGHT_DIRECTIONAL, Vector3(0, 5, 2))
	if key == "":
		failures.append("add_light(DIRECTIONAL) failed")
	var fill := ctrl.add_light(LightingController.LIGHT_OMNI, Vector3(-2, 1, 0))
	if fill == "":
		failures.append("add_light(OMNI) failed")
	if ctrl.light_count() != 2:
		failures.append("expected 2 lights after the initial adds")
	if ctrl.add_light(LightingController.LIGHT_DIRECTIONAL, Vector3.ZERO) != "":
		failures.append("second directional exceeded the budget")
	if ctrl.add_light(LightingController.LIGHT_OMNI, Vector3.ZERO) != "":
		failures.append("second omni exceeded the budget")
	if ctrl.light_count() != 2:
		failures.append("budget-exceeded adds changed the count")

	if ctrl.set_intensity(key, 999.0) == false or absf((ctrl._lights[key] as Light3D).light_energy - 5.0) > 0.001:
		failures.append("set_intensity did not clamp to 5.0")
	if not ctrl.key_light_exists():
		failures.append("key_light_exists false with an energized key")
	if ctrl.set_intensity(key, 0.0) == false or ctrl.key_light_exists():
		failures.append("key_light_exists should be false when the key is dimmed to 0")
	if absf(ctrl.min_intensity() - 0.0) > 0.001:
		failures.append("min_intensity did not reflect the dimmed key")
	ctrl.set_intensity(key, 1.0)

	if ctrl.set_shadows(fill, true) == false or (ctrl._lights[fill] as Light3D).shadow_enabled != true:
		failures.append("set_shadows did not enable shadows")
	if ctrl.set_color(key, Color.RED) == false or (ctrl._lights[key] as Light3D).light_color != Color.RED:
		failures.append("set_color did not round-trip")
	ctrl.select(fill)
	if ctrl.selected() != fill:
		failures.append("select/selected did not round-trip")

	if not ctrl.remove_light(fill):
		failures.append("remove_light returned false")
	if ctrl.light_count() != 1 or lights_root.get_node_or_null(fill) != null:
		failures.append("remove_light did not free the node")

	# Unknown types and ids are silent no-ops.
	if ctrl.add_light(2, Vector3.ZERO) != "":
		failures.append("add_light with unknown type should return ''")
	if ctrl.set_intensity("nope", 1.0) != false:
		failures.append("set_intensity on unknown id should be false")

	stage.free()
	return failures