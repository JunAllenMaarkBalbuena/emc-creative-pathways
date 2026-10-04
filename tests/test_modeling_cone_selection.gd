extends SceneTree

## Regression test: cone meshes in the 3D modeling lab must be click-selectable.
## Root cause (original): a cone is built as a CylinderMesh with top_radius = 0, but
## PrimitiveSpawner._shape_for_mesh() built its collision as a CylinderShape3D
## using mesh.top_radius, producing radius 0 -> a degenerate shape that raycasts
## (used by SelectionManager.select_from_click) can never hit. Lesson 2
## ("traffic_cone") is the first assignment to spawn a CONE.
## Pickers are now trimeshes (ConcavePolygonShape3D) because the SelectArea
## inherits the mesh's per-axis scale, which Jolt rejects on primitive shapes.

func _initialize() -> void:
	_run()

func _run() -> void:
	var fail := 0
	var spawner := PrimitiveSpawner.new()

	# 1. The cone's picker must be a non-null trimesh so Jolt can apply the
	#    mesh's per-axis scale without spamming _try_build_shape errors.
	var root3d := Node3D.new()
	root.add_child(root3d)
	var cone := spawner.spawn(PrimitiveDef.Type.CONE, root3d)
	var select_area := cone.get_node_or_null("SelectArea") as Area3D
	if select_area == null or select_area.get_child_count() == 0:
		fail += 1
		print("FAIL: spawned cone has no SelectArea with a collision child")
	else:
		var cs := select_area.get_child(0) as CollisionShape3D
		var shape := cs.shape as ConcavePolygonShape3D
		if shape == null:
			fail += 1
			print("FAIL: cone collision shape is not a ConcavePolygonShape3D (trimesh picker required)")

	# 2. A camera ray aimed at the cone's side must actually hit the SelectArea,
	#    replicating SelectionManager.select_from_click().
	var cam := Camera3D.new()
	root3d.add_child(cam)
	await process_frame
	cam.look_at_from_position(Vector3(0.6, 0.0, 3.0), Vector3.ZERO)
	await process_frame
	var space := cam.get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.new()
	params.from = cam.global_position
	params.to = Vector3.ZERO
	params.collision_mask = 1
	params.collide_with_areas = true
	var result := space.intersect_ray(params)
	if result.is_empty():
		fail += 1
		print("FAIL: camera ray did not hit the cone (click cannot select the cone)")
	elif not result.collider is Area3D:
		fail += 1
		print("FAIL: camera ray hit %s, not the cone SelectArea" % result.collider.get_class())

	if fail == 0:
		print("PASS: cone collision is non-degenerate and click-selectable")
	quit(1 if fail > 0 else 0)