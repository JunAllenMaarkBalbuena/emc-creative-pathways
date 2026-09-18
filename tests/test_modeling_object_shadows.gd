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

	# Selection must not wipe the object's lit/shadowed shading: the highlight
	# replaces the base material, so if it is strongly emissive the whole
	# surface goes flat-bright and the object's visible shadow is lost when
	# selected. It must stay a light tint that keeps per-face lighting.
	var base_surface_mat: Material = cube.get_surface_override_material(0)
	var sel := SelectionManager.new(container)
	sel.select(cube)
	var hl := cube.get_surface_override_material(0) as StandardMaterial3D
	# The highlight must NOT disable the depth test: that would drop the
	# selected object out of the shadow pass, making its soft drop shadow on
	# the floor vanish while selected (and return on deselect).
	if hl == null:
		fail += 1
		print("FAIL: selection did not apply a highlight material")
	elif hl.no_depth_test:
		fail += 1
		print("FAIL: selection highlight disables depth test; the selected object stops casting its drop shadow")
	if hl != null and hl.emission_enabled:
		fail += 1
		print("FAIL: selection highlight uses emission which destroys the object's per-face shading")
	sel.deselect_all()
	if cube.get_surface_override_material(0) != base_surface_mat:
		fail += 1
		print("FAIL: deselect must restore the object's base material (and its shading)")

	# Floor: the grid must be an opaque, lit surface so the drop shadow shows
	# under objects instead of falling on a shadow-ignoring overlay.
	var grid_mesh := ws.get_node_or_null("GridPlane") as MeshInstance3D
	if grid_mesh == null:
		fail += 1
		print("FAIL: no grid plane (shadow receiver floor)")
	else:
		# Overlap guard: the opaque grid surface must sit BELOW the object
		# resting line (objects spawn with their bottom at workspace y=0). If the
		# grid sits AT that line, a spawned object's bottom face is coplanar with
		# the opaque floor and the floor visibly overlaps the selected object.
		if grid_mesh.position.y > -0.001:
			fail += 1
			print("FAIL: opaque grid must sit below the object resting line so it cannot overlap spawned objects (grid y=%.4f)" % grid_mesh.position.y)
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