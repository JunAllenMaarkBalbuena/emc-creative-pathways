class_name PrimitiveSpawner
extends RefCounted

static func type_for_mesh(mesh: Mesh) -> int:
	if mesh is BoxMesh:
		return PrimitiveDef.Type.CUBE
	if mesh is SphereMesh:
		return PrimitiveDef.Type.SPHERE
	if mesh is CapsuleMesh:
		return PrimitiveDef.Type.CAPSULE
	if mesh is PlaneMesh:
		return PrimitiveDef.Type.PLANE
	if mesh is CylinderMesh:
		if is_zero_approx(mesh.top_radius):
			return PrimitiveDef.Type.CONE
		return PrimitiveDef.Type.CYLINDER
	return PrimitiveDef.Type.CUBE

func get_mesh_for_type(type: int) -> Mesh:
	match type:
		PrimitiveDef.Type.CUBE:
			return BoxMesh.new()
		PrimitiveDef.Type.SPHERE:
			return SphereMesh.new()
		PrimitiveDef.Type.CYLINDER:
			return CylinderMesh.new()
		PrimitiveDef.Type.CONE:
			var cone := CylinderMesh.new()
			cone.top_radius = 0
			return cone
		PrimitiveDef.Type.CAPSULE:
			return CapsuleMesh.new()
		PrimitiveDef.Type.PLANE:
			return PlaneMesh.new()
		PrimitiveDef.Type.TORUS:
			var torus := CylinderMesh.new()
			torus.top_radius = 0.5
			return torus
	return BoxMesh.new()

func spawn(type: int, parent: Node3D, with_collision: bool = true) -> MeshInstance3D:
	var mesh := get_mesh_for_type(type)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.name = PrimitiveDef.Type.keys()[type] + "_" + str(Time.get_ticks_msec())
	parent.add_child(mi)
	mi.owner = parent.owner if parent.owner else parent
	if with_collision:
		_add_collision(mi)
	return mi

func _add_collision(mi: MeshInstance3D):
	var area := Area3D.new()
	area.name = "SelectArea"
	area.collision_layer = 1
	area.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = _shape_for_mesh(mi.mesh)
	area.add_child(cs)
	mi.add_child(area)
	area.owner = mi.owner if mi.owner else mi

func _shape_for_mesh(mesh: Mesh) -> Shape3D:
	if mesh is BoxMesh:
		var s := BoxShape3D.new()
		s.size = mesh.size
		return s
	if mesh is SphereMesh:
		var s := SphereShape3D.new()
		s.radius = mesh.radius
		return s
	if mesh is CylinderMesh:
		var s := CylinderShape3D.new()
		s.radius = mesh.top_radius
		s.height = mesh.height
		return s
	if mesh is CapsuleMesh:
		var s := CapsuleShape3D.new()
		s.radius = mesh.radius
		s.height = mesh.height
		return s
	if mesh is PlaneMesh:
		var s := BoxShape3D.new()
		s.size = Vector3(mesh.size.x, 0.01, mesh.size.y)
		return s
	return BoxShape3D.new()

func spawn_named(type: int, parent: Node3D, node_name: String) -> MeshInstance3D:
	var mi := spawn(type, parent)
	mi.name = node_name
	return mi
