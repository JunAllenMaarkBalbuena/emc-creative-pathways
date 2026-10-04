extends SceneTree

## Regression test: transform gizmo handles must render on top of occluding
## objects (no_depth_test = true) so they stay visible even when the selected
## object is under/behind another one. Handles must NOT cast shadows:
## translucent arrows/rings casting opaque shadows onto the workspace floor
## ruins the selected objects' soft drop shadow and, from certain camera
## angles, reads as the grid overlapping the object.
##
## The selection highlight material must keep depth testing ENABLED: disabling
## it drops the selected object from the shadow pass, so its soft drop shadow
## disappears on selection. The highlight tints the albedo instead.

func _initialize() -> void:
	_run()

func _collect_mesh_instances(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		_collect_mesh_instances(child, out)

func _run() -> void:
	var fail := 0
	var gizmo := Gizmo3D.new()
	gizmo.name = "Gizmo3D"
	root.add_child(gizmo)
	await process_frame

	for mode in [Gizmo3D.Mode.TRANSLATE, Gizmo3D.Mode.ROTATE, Gizmo3D.Mode.SCALE]:
		gizmo.set_mode(mode)
		gizmo._build_handles()
		var meshes: Array[MeshInstance3D] = []
		_collect_mesh_instances(gizmo.get_node("Handles"), meshes)
		if meshes.is_empty():
			fail += 1
			print("FAIL: no handle meshes built for mode %d" % mode)
			continue
		for mi in meshes:
			var mat := mi.material_override as StandardMaterial3D
			if mat == null or not mat.no_depth_test:
				fail += 1
				print("FAIL: handle '%s' (mode %d) does not render on top" % [mi.name, mode])
			if mat == null or mat.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA or mat.albedo_color.a < 0.85:
				fail += 1
				print("FAIL: handle '%s' (mode %d) is too translucent; bright grid lines bleed through its body and read as the grid overlapping the gizmo (alpha=%.2f)" % [mi.name, mode, mat.albedo_color.a if mat else -1.0])
			if mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				fail += 1
				print("FAIL: handle '%s' (mode %d) casts shadows on the workspace floor; it destroys the object's soft drop shadow on selection" % [mi.name, mode])
			if mi.mesh is TorusMesh:
				var torus := mi.mesh as TorusMesh
				if torus.outer_radius - torus.inner_radius > 0.25:
					fail += 1
					print("FAIL: rotate ring '%s' (mode %d) band too thick (%.2f); it reads as a flat plane laid over the object" % [mi.name, mode, torus.outer_radius - torus.inner_radius])

	var container := Node3D.new()
	root.add_child(container)
	var spawner := PrimitiveSpawner.new()
	var selection := SelectionManager.new(container)
	var cube := spawner.spawn(PrimitiveDef.Type.CUBE, container)
	var base_surface_mat: Material = cube.get_surface_override_material(0)
	selection.select(cube)
	# The selection highlight is a separate indicator layer on material_overlay;
	# it must keep depth test ON (no drawing through occluders) and must NOT
	# replace or modify the object's own surface material.
	var highlight := cube.material_overlay as StandardMaterial3D
	if highlight != null and highlight.no_depth_test:
		fail += 1
		print("FAIL: selection highlight overlay disables depth test; the tint renders through other objects")
	if highlight == null:
		fail += 1
		print("FAIL: selection did not apply a highlight overlay (material_overlay)")
	if cube.get_surface_override_material(0) != base_surface_mat:
		fail += 1
		print("FAIL: selection must not replace the object's base material")

	if fail == 0:
		print("PASS: gizmo handles render on top without casting shadows; highlight keeps depth test on")
	quit(1 if fail > 0 else 0)