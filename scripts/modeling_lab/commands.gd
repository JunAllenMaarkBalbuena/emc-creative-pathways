class_name ModelingAction
extends RefCounted

## Snapshot-based undo action. Uses instance IDs for precise node removal,
## avoiding name collisions when two objects share the same display name.

var _type: String
var _before: Array
var _after: Array
var _remove_after_ids: Array[int]   # instance IDs to remove on execute
var _undo_remove_ids: Array[int]    # instance IDs to remove on undo (captured after execute)
var _last_created_ids: Array[int]   # IDs of nodes created by last _apply call
var _container: Node3D
var _spawner: PrimitiveSpawner
var _material_mgr  # MaterialManager
var _hierarchy_mgr: HierarchyManager
var _created_node: Node3D
var _applied: bool = false
var _node: Node3D
var _material_display: String = ""
static var debug_actions: bool = true

func _init(p_type: String, p_before: Array, p_after: Array,
		p_remove_after_ids: Array[int],
		p_container: Node3D, p_spawner: PrimitiveSpawner,
		p_material_mgr, p_hierarchy_mgr: HierarchyManager) -> void:
	_type = p_type
	_before = p_before
	_after = p_after
	_remove_after_ids = p_remove_after_ids
	_container = p_container
	_spawner = p_spawner
	_material_mgr = p_material_mgr
	_hierarchy_mgr = p_hierarchy_mgr


func _log(msg: String) -> void:
	if debug_actions:
		print("[ACTION] ", _type, " | ", msg)


func execute() -> void:
	_log("execute")
	if _type == "group":
		_execute_group()
	elif _type == "ungroup":
		_execute_ungroup()
	elif _type == "duplicate_group":
		_execute_duplicate_group()
	elif _type == "material":
		_apply_material(_after)
	else:
		_apply(_remove_after_ids, _after, _before)
		_undo_remove_ids = _last_created_ids.duplicate()
	_applied = true


func undo() -> void:
	_log("undo")
	if _type == "group":
		_undo_group()
	elif _type == "ungroup":
		_undo_ungroup()
	elif _type == "duplicate_group":
		_undo_duplicate_group()
	elif _type == "material":
		_apply_material(_before)
	else:
		_apply(_undo_remove_ids, _before, _after)
		_remove_after_ids = _last_created_ids.duplicate()


func get_type() -> String:
	return _type


func get_created_node() -> Node3D:
	return _created_node


## Instance IDs of every node materialized by the most recent _apply() call
## (execute, undo, or redo). The snapshot-based command system FREES the original
## nodes and REBUILDS fresh instances, so callers must re-point any cached
## selection at these new IDs or the selection silently goes stale.
func get_last_created_ids() -> Array[int]:
	return _last_created_ids.duplicate()


# ── Generic snapshot apply ─────────────────────────────────────

func _apply(remove_ids: Array[int], snapshot: Array, other_snapshot: Array) -> void:
	if not is_instance_valid(_container):
		return
	# Phase 1: Remove by instance ID (precise, no name collision)
	var freed := 0
	for id in remove_ids:
		var node := instance_from_id(id) as Node3D
		if is_instance_valid(node):
			node.free()
			freed += 1
	# Phase 2: Fallback — remove any existing node whose display name
	# matches a snapshot entry from either snapshot. Handles stale IDs
	# where a later action freed and recreated the node.
	# Only runs when IDs were provided but stale (skip for pure creates like spawn).
	if not remove_ids.is_empty():
		var seen_names: Array[String] = []
		for entry in snapshot:
			var display: String = entry.get("display_name", "")
			if display != "" and display not in seen_names:
				seen_names.append(display)
		for entry in other_snapshot:
			var display: String = entry.get("display_name", "")
			if display != "" and display not in seen_names:
				seen_names.append(display)
		for display in seen_names:
			var existing := _find_by_display_deep(_container, display)
			if existing and is_instance_valid(existing):
				existing.free()
				freed += 1
	_log("freed=%d remove_ids=%s target_names=%s" % [freed, str(remove_ids), str(_snapshot_names(snapshot))])
	# Phase 3: Create from snapshot
	_created_node = null
	_last_created_ids.clear()
	for entry in snapshot:
		var node := _rebuild_node(entry)
		_last_created_ids.append(node.get_instance_id())
		if not _created_node:
			_created_node = node
	_log("created_ids=%s" % str(_last_created_ids))


# ── Group: explicit reparenting ────────────────────────────────

func _execute_group() -> void:
	if _after.is_empty():
		return
	var group_data: Dictionary = _after[0]
	var group := Node3D.new()
	group.name = group_data.name
	group.position = group_data.get("position", Vector3.ZERO)
	group.rotation_degrees = group_data.get("rotation_degrees", Vector3.ZERO)
	group.scale = group_data.get("scale", Vector3.ONE)
	group.set_meta(&"blender_display", group_data.get("display_name", group_data.name))
	_container.add_child(group)
	group.owner = _container.owner if _container.owner else _container
	_created_node = group
	_last_created_ids.clear()
	_last_created_ids.append(group.get_instance_id())
	_undo_remove_ids.clear()
	_undo_remove_ids.append(group.get_instance_id())

	for i in range(1, _after.size()):
		var member_data: Dictionary = _after[i]
		var member_name: String = member_data.get("display_name", member_data.get("name", ""))
		var member := _find_by_display(member_name)
		if member and member != group:
			_hierarchy_mgr.reparent_preserve(member, group)


func _undo_group() -> void:
	var group_name: String = ""
	for c in _container.get_children():
		if c is Node3D and c not in _collect_meshes(_container):
			group_name = HierarchyManager.display_of(c)
			break

	var group := _find_by_display(group_name) if group_name else null
	if group:
		var children: Array[Node] = []
		for child in group.get_children():
			children.append(child)
		for child in children:
			if child is Node3D:
				_hierarchy_mgr.reparent_preserve(child, _container)
		group.free()


func _execute_ungroup() -> void:
	var group := _find_ungroup_target()
	if not group:
		return
	var children: Array[Node] = []
	for child in group.get_children():
		children.append(child)
	for child in children:
		if child is Node3D:
			_hierarchy_mgr.reparent_preserve(child, _container)
	group.free()


func _undo_ungroup() -> void:
	if _before.is_empty():
		return
	var group_data: Dictionary = _before[0]
	var group := Node3D.new()
	group.name = group_data.name
	group.position = group_data.get("position", Vector3.ZERO)
	group.rotation_degrees = group_data.get("rotation_degrees", Vector3.ZERO)
	group.scale = group_data.get("scale", Vector3.ONE)
	group.set_meta(&"blender_display", group_data.get("display_name", group_data.name))
	_container.add_child(group)
	group.owner = _container.owner if _container.owner else _container

	for i in range(1, _before.size()):
		var member_data: Dictionary = _before[i]
		var member_name: String = member_data.get("display_name", member_data.get("name", ""))
		var member := _find_by_display(member_name)
		if member and member != group:
			_hierarchy_mgr.reparent_preserve(member, group)


# ── Duplicate group: pure-create custom path ────────────────────
## The `after` snapshot is [group_data, member_data…] (see
## CommandFactory.duplicate_group). The group slot carries is_group=true; each
## member slot is a _serialize_node snapshot. We build the group node and spawn
## member copies under it directly — deliberately NOT the generic _apply path,
## because parenting into a brand-new group requires ordered creation (group
## first, then members as its children).

func _execute_duplicate_group() -> void:
	if _after.is_empty():
		return
	var group_data: Dictionary = _after[0]
	var group := Node3D.new()
	group.name = group_data.get("name", "group")
	group.position = group_data.get("position", Vector3(0.5, 0.5, 0.5))
	group.rotation_degrees = group_data.get("rotation_degrees", Vector3.ZERO)
	group.scale = group_data.get("scale", Vector3.ONE)
	group.set_meta(&"blender_display", group_data.get("display_name", group_data.get("name", "group")))
	_container.add_child(group)
	group.owner = _container.owner if _container.owner else _container
	_created_node = group
	_last_created_ids.clear()
	_last_created_ids.append(group.get_instance_id())

	for i in range(1, _after.size()):
		var member_data: Dictionary = _after[i]
		var mi: MeshInstance3D = _spawner.spawn(
			member_data.get("type", PrimitiveDef.Type.CUBE), group)
		mi.name = member_data.get("name", mi.name)
		mi.position = member_data.get("position", Vector3.ZERO)
		mi.rotation_degrees = member_data.get("rotation_degrees", Vector3.ZERO)
		mi.scale = member_data.get("scale", Vector3.ONE)
		if member_data.get("display_name", ""):
			mi.set_meta(&"blender_display", member_data.display_name)
		_material_mgr.apply_to(mi, {
			albedo = member_data.get("material_albedo", Color.WHITE),
			metallic = member_data.get("material_metallic", 0.0),
			roughness = member_data.get("material_roughness", 1.0),
		})
		_last_created_ids.append(mi.get_instance_id())
	_undo_remove_ids = _last_created_ids.duplicate()


func _undo_duplicate_group() -> void:
	# The whole subtree (group node + spawned member copies + their collision
	# areas) is freshly created by this action, so freeing the group cascades.
	if _last_created_ids.is_empty():
		return
	var group := instance_from_id(_last_created_ids[0]) as Node3D
	if group and is_instance_valid(group):
		group.free()
	_remove_after_ids = _last_created_ids.duplicate()


# ── Material ─────────────────────────────────────────────────

func _apply_material(props: Array) -> void:
	if props.is_empty():
		return
	var props_dict: Dictionary = props[0]
	var node := _resolve_material_node()
	if node and is_instance_valid(node):
		_material_mgr.apply_to(node, props_dict)
		_log("apply_material node=%s id=%d albedo=%s" % [node.name, node.get_instance_id(), str(props_dict.get("albedo", Color.WHITE))])
	else:
		_log("apply_material SKIPPED - no resolvable node (display=%s ids=%s)" % [_material_display, str(_remove_after_ids)])


func _resolve_material_node() -> Node3D:
	if is_instance_valid(_node):
		_log("resolve -> direct node %s" % _node.name)
		return _node
	if not _remove_after_ids.is_empty():
		var by_id := instance_from_id(_remove_after_ids[0]) as Node3D
		if is_instance_valid(by_id):
			_log("resolve -> instance id %s" % by_id.name)
			return by_id
	if _material_display != "":
		var by_display := _find_by_display_deep(_container, _material_display)
		if is_instance_valid(by_display):
			_log("resolve -> display fallback %s" % by_display.name)
			return by_display
	return null


# ── Helpers ────────────────────────────────────────────────────

func _snapshot_names(snapshot: Array) -> Array[String]:
	var names: Array[String] = []
	for entry in snapshot:
		var display: String = entry.get("display_name", "")
		if display != "":
			names.append(display)
	return names


func _find_by_display(display: String) -> Node3D:
	for c in _container.get_children():
		if c is Node3D and HierarchyManager.display_of(c) == display:
			return c
	return null


func _find_by_display_deep(root: Node, display: String) -> Node3D:
	if root is Node3D and HierarchyManager.display_of(root) == display:
		return root as Node3D
	for child in root.get_children():
		var found := _find_by_display_deep(child, display)
		if found:
			return found
	return null


func _find_ungroup_target() -> Node3D:
	for c in _container.get_children():
		if c is Node3D and not c is MeshInstance3D:
			return c
	return null


func _collect_meshes(root: Node) -> Array[Node]:
	var result: Array[Node] = []
	for c in root.get_children():
		if c is MeshInstance3D:
			result.append(c)
	return result


func _rebuild_node(data: Dictionary) -> Node3D:
	var parent: Node3D = _container
	var pp = data.get("parent_path", NodePath())
	if pp != NodePath():
		parent = _container.get_node_or_null(pp)
		if not parent:
			parent = _container

	var is_group: bool = data.get("is_group", false)
	var mi: Node3D

	if is_group:
		mi = Node3D.new()
		mi.name = data.get("name", "group")
		parent.add_child(mi)
		mi.owner = _container.owner if _container.owner else _container
	else:
		mi = _spawner.spawn(data.get("type", PrimitiveDef.Type.CUBE), parent)
		if data.has("name"):
			mi.name = data.name

	mi.position = data.get("position", Vector3.ZERO)
	mi.rotation_degrees = data.get("rotation_degrees", Vector3.ZERO)
	mi.scale = data.get("scale", Vector3.ONE)

	if data.get("display_name", ""):
		mi.set_meta(&"blender_display", data.display_name)

	if not is_group and data.get("material_albedo", Color.WHITE) != Color.WHITE:
		_material_mgr.apply_to(mi, {
			albedo = data.material_albedo,
			metallic = data.get("material_metallic", 0.0),
			roughness = data.get("material_roughness", 1.0),
		})

	return mi
