class_name CommandFactory
extends RefCounted

## Snapshot-based command factories. Callers do NOT pre-apply effects.
## Each factory captures instance IDs of nodes to remove, so undo/redo
## never collides when two objects share the same display name.


# ── Helpers ────────────────────────────────────────────────────

static func _serialize_node(mi: Node3D, container: Node3D) -> Dictionary:
	var parent_path := NodePath()
	if mi.get_parent() and mi.get_parent() != container:
		parent_path = container.get_path_to(mi.get_parent())

	var mat: StandardMaterial3D = mi.get_surface_override_material(0) as StandardMaterial3D
	return {
		name = mi.name,
		display_name = HierarchyManager.display_of(mi),
		type = PrimitiveSpawner.type_for_mesh(mi.mesh) if mi.mesh else PrimitiveDef.Type.CUBE,
		position = mi.position,
		rotation_degrees = mi.rotation_degrees,
		scale = mi.scale,
		material_albedo = mat.albedo_color if mat else Color.WHITE,
		material_metallic = mat.metallic if mat else 0.0,
		material_roughness = mat.roughness if mat else 1.0,
		parent_path = parent_path,
	}

static func _serialize_group_node(group_node: Node3D) -> Dictionary:
	return {
		name = group_node.name,
		display_name = HierarchyManager.display_of(group_node),
		position = group_node.position,
		rotation_degrees = group_node.rotation_degrees,
		scale = group_node.scale,
		parent_path = NodePath(),
		is_group = true,
	}


# ── Spawn ──────────────────────────────────────────────────────

static func spawn(data: Dictionary, container: Node3D,
		spawner: PrimitiveSpawner, material_mgr,
		hierarchy_mgr: HierarchyManager) -> ModelingAction:
	return ModelingAction.new("spawn",
		[],                           # before: nothing
		[data],                        # after: the new node
		[],                           # remove_after: nothing (fresh create)
		container, spawner, material_mgr, hierarchy_mgr)


# ── Delete ─────────────────────────────────────────────────────

static func delete(nodes: Array[Node3D], container: Node3D,
		spawner: PrimitiveSpawner, material_mgr,
		hierarchy_mgr: HierarchyManager) -> ModelingAction:
	var before: Array[Dictionary] = []
	var remove_ids: Array[int] = []
	for n in nodes:
		if is_instance_valid(n):
			before.append(_serialize_node(n, container))
			remove_ids.append(n.get_instance_id())
	return ModelingAction.new("delete",
		before,                        # before: recreate the deleted nodes
		[],                           # after: nothing
		remove_ids,                   # remove_after: execute removes the nodes by instance ID
		container, spawner, material_mgr, hierarchy_mgr)


# ── Transform ──────────────────────────────────────────────────

static func transform(paths: Array, befores: Array, afters: Array,
		container: Node3D, spawner: PrimitiveSpawner,
		material_mgr, hierarchy_mgr: HierarchyManager) -> ModelingAction:
	var before_snap: Array[Dictionary] = []
	var after_snap: Array[Dictionary] = []
	var remove_ids: Array[int] = []
	for i in paths.size():
		var node := container.get_node_or_null(paths[i])
		if not node:
			continue
		var b_data := _serialize_node(node, container)
		var b_t: Transform3D = befores[i]
		b_data.position = b_t.origin
		var b_euler := b_t.basis.get_euler()
		b_data.rotation_degrees = Vector3(rad_to_deg(b_euler.x), rad_to_deg(b_euler.y), rad_to_deg(b_euler.z))
		b_data.scale = b_t.basis.get_scale()
		before_snap.append(b_data)
		var a_data := _serialize_node(node, container)
		var a_t: Transform3D = afters[i]
		a_data.position = a_t.origin
		var a_euler := a_t.basis.get_euler()
		a_data.rotation_degrees = Vector3(rad_to_deg(a_euler.x), rad_to_deg(a_euler.y), rad_to_deg(a_euler.z))
		a_data.scale = a_t.basis.get_scale()
		after_snap.append(a_data)
		remove_ids.append(node.get_instance_id())
	return ModelingAction.new("transform",
		before_snap, after_snap,
		remove_ids,
		container, spawner, material_mgr, hierarchy_mgr)


# ── Duplicate ──────────────────────────────────────────────────

static func duplicate_node(original: Node3D, container: Node3D,
		spawner: PrimitiveSpawner, material_mgr,
		hierarchy_mgr: HierarchyManager) -> ModelingAction:
	var data := _serialize_node(original, container)
	data.position = original.position + Vector3(0.5, 0.5, 0.5)
	var base := HierarchyManager.base_of(data.display_name)
	data.display_name = HierarchyManager.allocate_name(container, base)
	data.name = data.display_name
	return ModelingAction.new("duplicate",
		[],                           # before: nothing
		[data],                        # after: the copy
		[],                           # remove_after: nothing (fresh create)
		container, spawner, material_mgr, hierarchy_mgr)


## Duplicate an entire group node: creates a brand-new group Node3D (fresh
## name, group origin offset +0.5) whose members are spawned copies of the
## original group's members (fresh per-member names, same transforms/materials).
## The action is a pure create: `before` is empty and `after` carries the member
## snapshots; commands.gd executes it via a dedicated branch that mirrors the
## proven custom group/ungroup handlers instead of the generic _apply path.
static func duplicate_group(group_node: Node3D, container: Node3D,
		spawner: PrimitiveSpawner, material_mgr,
		hierarchy_mgr: HierarchyManager) -> ModelingAction:
	var reserved := {}
	var group_base := HierarchyManager.base_of(HierarchyManager.display_of(group_node))
	var group_name: String = HierarchyManager.allocate_name(container, group_base, reserved)
	reserved[group_name] = true

	var after: Array[Dictionary] = []
	after.append({
		name = group_name,
		display_name = group_name,
		position = group_node.position + Vector3(0.5, 0.5, 0.5),
		rotation_degrees = group_node.rotation_degrees,
		scale = group_node.scale,
		parent_path = NodePath(),
		is_group = true,
	})

	for child in group_node.get_children():
		if child is MeshInstance3D and not child.is_in_group("ghost_guides"):
			var data := _serialize_node(child, container)
			var base := HierarchyManager.base_of(data.display_name)
			data.display_name = HierarchyManager.allocate_name(container, base, reserved)
			reserved[data.display_name] = true
			data.name = data.display_name
			after.append(data)

	return ModelingAction.new("duplicate_group",
		[],                           # before: nothing (pure create)
		after,                        # after: group + member copies
		[],                           # remove_after: nothing (fresh create)
		container, spawner, material_mgr, hierarchy_mgr)


# ── Group ──────────────────────────────────────────────────────

static func group(group_name: String, members: Array[Node3D], container: Node3D,
		spawner: PrimitiveSpawner, material_mgr,
		hierarchy_mgr: HierarchyManager) -> ModelingAction:
	var before: Array[Dictionary] = []
	for m in members:
		if is_instance_valid(m):
			before.append(_serialize_node(m, container))

	var after: Array[Dictionary] = []
	after.append({
		name = group_name,
		display_name = group_name,
		position = Vector3.ZERO,
		rotation_degrees = Vector3.ZERO,
		scale = Vector3.ONE,
		parent_path = NodePath(),
		is_group = true,
	})
	for m in members:
		if is_instance_valid(m):
			var data := _serialize_node(m, container)
			data.parent_path = group_name
			after.append(data)

	return ModelingAction.new("group",
		before, after,
		[],                           # remove_after: handled by custom _execute_group
		container, spawner, material_mgr, hierarchy_mgr)


# ── Ungroup ────────────────────────────────────────────────────

static func ungroup(group_node: Node3D, container: Node3D,
		spawner: PrimitiveSpawner, material_mgr,
		hierarchy_mgr: HierarchyManager) -> ModelingAction:
	var before: Array[Dictionary] = []
	before.append(_serialize_group_node(group_node))
	for child in group_node.get_children():
		if child is Node3D:
			var data := _serialize_node(child, container)
			data.parent_path = container.get_path_to(group_node)
			before.append(data)

	var after: Array[Dictionary] = []
	for child in group_node.get_children():
		if child is Node3D:
			after.append(_serialize_node(child, container))

	return ModelingAction.new("ungroup",
		before, after,
		[],                           # remove_after: handled by custom _execute_ungroup
		container, spawner, material_mgr, hierarchy_mgr)


# ── Rename ─────────────────────────────────────────────────────

static func rename(node: Node3D, old_name: String, new_name: String, container: Node3D,
		spawner: PrimitiveSpawner, material_mgr,
		hierarchy_mgr: HierarchyManager) -> ModelingAction:
	var before := _serialize_node(node, container)
	before.display_name = old_name
	var after := _serialize_node(node, container)
	after.display_name = new_name
	return ModelingAction.new("rename",
		[before], [after],
		[node.get_instance_id()],      # remove_after: remove old node by instance ID
		container, spawner, material_mgr, hierarchy_mgr)


# ── Material ─────────────────────────────────────────────────

static func _serialize_material(node: Node3D) -> Dictionary:
	var mat: StandardMaterial3D = node.get_surface_override_material(0) as StandardMaterial3D
	return {
		albedo = mat.albedo_color if mat else Color.WHITE,
		metallic = mat.metallic if mat else 0.0,
		roughness = mat.roughness if mat else 1.0,
	}


static func material(node: Node3D, before_props: Dictionary, after_props: Dictionary,
		container: Node3D, spawner: PrimitiveSpawner,
		material_mgr, hierarchy_mgr: HierarchyManager) -> ModelingAction:
	var action := ModelingAction.new("material",
		[before_props],
		[after_props],
		[node.get_instance_id()],
		container, spawner, material_mgr, hierarchy_mgr)
	action._node = node
	action._material_display = HierarchyManager.display_of(node)
	return action
