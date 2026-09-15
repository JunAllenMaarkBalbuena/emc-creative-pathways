extends SceneTree

## Regression test: the modeling workspace must render real, good-looking drop
## shadows. Objects cast shadows onto each other and onto the floor grid. The
## directional light must cast soft shadows and spawned primitives must be
## opaque casters/receivers (a transparent or unshaded surfaces cannot take a
## light-pass shadow).

func _initialize() -> void:
	_run()

func _run() -> void:
	var fail := 0
	var ws: Node3D = (load("res://scenes/modeling_lab/workspace.tscn") as PackedScene).instantiate()
	root.add_child(ws)
	await process_frame

	var light := ws.get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	if light == null:
		fail += 1
		print("FAIL: no directional light in workspace")
	elif not light.shadow_enabled:
		fail += 1
		print("FAIL: directional light does not cast shadows")
	else:
		if light.shadow_blur <= 0.0:
			fail += 1
			print("FAIL: shadow blur should be > 0 for soft edges")
		if light.shadow_normal_bias >= 2.0:
			fail += 1
			print("FAIL: shadow_normal_bias too high causes shadow-panning (detached shadows)")
		if not light.directional_shadow_blend_splits:
			fail += 1
			print("FAIL: directional shadow split blending should be on for smooth splits")

	var spawner := PrimitiveSpawner.new()
	var container := Node3D.new()
	root.add_child(container)
	var cube: MeshInstance3D = spawner.spawn(PrimitiveDef.Type.CUBE, container)
	if cube.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_ON:
		fail += 1
		print("FAIL: spawned objects must cast shadows")

	var mat := cube.get_surface_override_material(0) as StandardMaterial3D
	if mat != null and mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		fail += 1
		print("FAIL: spawned cube material is transparent; it cannot receive/render shadows cleanly")

	# Floor: the grid must be an opaque, lit surface so the drop shadow shows
	# under objects instead of falling on a shadow-ignoring overlay.
	var grid_mesh := ws.get_node_or_null("GridPlane") as MeshInstance3D
	if grid_mesh == null:
		fail += 1
		print("FAIL: no grid plane (shadow receiver floor)")
	else:
		var gm := grid_mesh.material_override as ShaderMaterial
		if gm == null or gm.shader == null:
			fail += 1
			print("FAIL: grid has no shader material")
		else:
			var col: Color = gm.get_shader_parameter("base_color")
			if col.a < 1.0:
				fail += 1
				print("FAIL: grid base is translucent; it cannot receive floor shadows")
			if gm.shader.code.contains("unshaded"):
				fail += 1
				print("FAIL: grid shader is unshaded; it cannot receive light-pass shadows")

	if fail == 0:
		print("PASS: real soft drop shadows from objects onto the floor grid")
	quit(1 if fail > 0 else 0)