extends SceneTree

## Regression test: save_manager.capture_model() hardcoded pd.type = 0 (CUBE),
## so spawned spheres/cylinders/etc. were saved and restored as cubes.
## Root cause: no reverse mapping from mesh -> PrimitiveDef.Type existed.

func _init() -> void:
	var code := _run()
	quit(code)

func _run() -> int:
	var spawner := PrimitiveSpawner.new()
	var container := Node3D.new()

	var sphere := MeshInstance3D.new()
	sphere.mesh = SphereMesh.new()
	sphere.name = "Sphere_1"
	container.add_child(sphere)

	var box := MeshInstance3D.new()
	box.mesh = BoxMesh.new()
	box.name = "CUBE_2"
	container.add_child(box)

	var cone := MeshInstance3D.new()
	cone.mesh = CylinderMesh.new()
	cone.mesh.top_radius = 0.0
	cone.name = "CONE_3"
	container.add_child(cone)

	var sm := SaveManager.new()
	if sm._sanitize("Model 2B") != "Model_2B":
		print("FAIL: SaveManager._sanitize('Model 2B') -> '%s' (expected 'Model_2B')" % sm._sanitize("Model 2B"))
		return 1
	var data := sm.capture_model(container, "test_model")
	for pd in data.primitives:
		print("DIAG: %s -> type %d" % [pd.node_name, pd.type])
	if data.primitives.is_empty():
		print("FAIL: capture_model returned no primitives")
		return 1
	if data.primitives[0].type != PrimitiveDef.Type.SPHERE:
		print("FAIL: sphere saved as type %d (expected SPHERE=%d)" % [data.primitives[0].type, PrimitiveDef.Type.SPHERE])
		return 1
	if data.primitives[1].type != PrimitiveDef.Type.CUBE:
		print("FAIL: box saved as type %d (expected CUBE=%d)" % [data.primitives[1].type, PrimitiveDef.Type.CUBE])
		return 1
	if data.primitives[2].type != PrimitiveDef.Type.CONE:
		print("FAIL: cone saved as type %d (expected CONE=%d)" % [data.primitives[2].type, PrimitiveDef.Type.CONE])
		return 1
	print("PASS: capture_model preserved primitive types (sphere/cube/cone)")
	container.free()
	return 0