extends SceneTree

## Regression test: transform gizmo handles and the selection highlight must
## render on top of occluding objects (no_depth_test = true) so they stay
## visible even when the selected object is under/behind another one.

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
			if mat == null or mat.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA or mat.albedo_color.a >= 1.0:
				fail += 1
				print("FAIL: handle '%s' (mode %d) is not semi-transparent" % [mi.name, mode])

	var container := Node3D.new()
	root.add_child(container)
	var spawner := PrimitiveSpawner.new()
	var selection := SelectionManager.new(container)
	var cube := spawner.spawn(PrimitiveDef.Type.CUBE, container)
	selection.select(cube)
	var highlight := cube.get_surface_override_material(0) as StandardMaterial3D
	if highlight == null or not highlight.no_depth_test:
		fail += 1
		print("FAIL: selection highlight does not render on top")

	if fail == 0:
		print("PASS: all gizmo handles and the selection highlight render on top")
	quit(1 if fail > 0 else 0)