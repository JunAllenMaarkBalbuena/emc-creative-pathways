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
	elif _type == "transform":
		_apply_transform(_after)
	elif _type == "reparent":
		_apply_reparent(_after)
	elif _type == "rename":
		_apply_rename(_after)
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
	elif _type == "transform":
		_apply_transform(_before)
	elif _type == "reparent":
		_apply_reparent(_before)
	elif _type == "rename":
		_apply_rename(_before)
	else:
		_apply(_undo_remove_ids, _before, _after)
		_remove_after_ids = _last_created_ids.duplicate()


func get_type() -> String:
	return _type


func get_created_node() -> Node3D:
	return _created_node


## Instance IDs of every node touched by the most recent apply (execute, undo,
## or redo). Callers that cache a selection use this to re-point at live nodes.
##
## Identity is preserved for the mutating action types (transform, rename,
## material): they write properties onto the existing node, so the ID returned
## is the one they already held. Only the creating/destroying types (spawn,
## delete, duplicate, group, ungroup) free the old node and materialise a
## replacement — those are the ones where a caller MUST re-read this list.
func get_last_created_ids() -> Array[int]:
	return _last_created_ids.duplicate()


# ── In-place property writes ──────────────────────────────────
## transform and rename do not change which nodes exist, so they deliberately
## bypass the generic _apply() rebuild. That rebuild frees the live node and
## materialises a fresh instance, which silently invalidates every reference the
## lab holds to it — the selection, _primitive_locked, and any signal
## connection made against that instance.
##
## Undo semantics are unchanged: undo still replays the same snapshot, it just
## writes it onto the surviving node instead of onto a replacement.

func _apply_transform(snapshot: Array) -> void:
	if snapshot.is_empty():
		return
	_created_node = null
	_last_created_ids.clear()
	var applied := 0
	for i in snapshot.size():
		var entry: Dictionary = snapshot[i]
		var node := _resolve_live_node(i, entry)
		if node == null:
			continue
		node.position = entry.get("position", Vector3.ZERO)
		node.rotation_degrees = entry.get("rotation_degrees", Vector3.ZERO)
		node.scale = entry.get("scale", Vector3.ONE)
		if not _created_node:
			_created_node = node
		_last_created_ids.append(node.get_instance_id())
		applied += 1
	_log("apply_transform applied=%d/%d ids=%s" % [applied, snapshot.size(), str(_last_created_ids)])


## Detach these nodes from their current parent, or attach them to the one
## named by each entry. reparent_preserve() restores the world transform, so
## reparenting is not a transform change and _apply_transform() is not used.
## Undo replays the `before` snapshot, which carries the original parent_path -
## the same operation pointed the other way, not a rebuild.
func _apply_reparent(snapshot: Array) -> void:
	if snapshot.is_empty() or not is_instance_valid(_container):
		return
	_created_node = null
	_last_created_ids.clear()
	var moved := 0
	for i in snapshot.size():
		var entry: Dictionary = snapshot[i]
		var node := _resolve_live_node(i, entry)
		if node == null:
			continue
		var pp: NodePath = entry.get("parent_path", NodePath())
		var target: Node3D = _container
		if pp != NodePath():
			target = _container.get_node_or_null(pp) as Node3D
			if target == null:
				# The named parent is gone - another action dissolved it. Leaving
				# the node where it is beats reparenting it somewhere arbitrary.
				_log("apply_reparent SKIPPED parent '%s' no longer exists" % String(pp))
				continue
		if node.get_parent() != target and _hierarchy_mgr.reparent_preserve(node, target):
			moved += 1
		if not _created_node:
			_created_node = node
		_last_created_ids.append(node.get_instance_id())
	_log("apply_reparent moved=%d/%d" % [moved, snapshot.size()])


## Only the display name moves; the mesh, material and transform are untouched.
## set_blender_name keeps node.name as the engine-sanitized twin of the
## Blender-style display name, which is the contract the rest of the lab reads.
func _apply_rename(snapshot: Array) -> void:
	if snapshot.is_empty():
		return
	var entry: Dictionary = snapshot[0]
	var display: String = entry.get("display_name", "")
	if display == "":
		return
	var node := _resolve_live_node(0, entry)
	if node == null:
		_log("apply_rename SKIPPED - no resolvable node (display=%s ids=%s)" % [display, str(_remove_after_ids)])
		return
	HierarchyManager.set_blender_name(node, display)
	_created_node = node
	_last_created_ids.clear()
	_last_created_ids.append(node.get_instance_id())
	_log("apply_rename -> '%s' id=%d" % [display, node.get_instance_id()])


## Resolve snapshot slot `index` to its live node. _remove_after_ids was captured
## when the command was built and, because nothing is freed here, still points at
## the same instances. The display-name lookup is a fallback for the case where
## something outside the command system freed and recreated the node.
func _resolve_live_node(index: int, entry: Dictionary) -> Node3D:
	if index < _remove_after_ids.size():
		var by_id := instance_from_id(_remove_after_ids[index]) as Node3D
		if is_instance_valid(by_id):
			return by_id
	var display: String = entry.get("display_name", "")
	if display != "":
		var by_display := _find_by_display_deep(_container, display)
		if is_instance_valid(by_display):
			return by_display
	_log("resolve_live_node MISS index=%d display='%s'" % [index, display])
	return null


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
	# Resolve by the ID this action created, not by position in the container.
	# The previous lookup took the first non-mesh child, which is the WRONG group
	# as soon as a second group exists - undoing "group.001" dissolved "group".
	var group := _resolve_group_node(_before)
	if group == null:
		_log("undo_group SKIPPED - group node no longer resolvable")
		return
	_promote_children(group)
	group.free()


func _execute_ungroup() -> void:
	# The group this command was built for, not "whichever group comes first".
	# _find_ungroup_target() returned the first non-mesh child, so with two
	# groups present every ungroup dissolved the wrong one.
	var group := _resolve_group_node(_before)
	if group == null:
		_log("execute_ungroup SKIPPED - group node no longer resolvable")
		return
	_promote_children(group)
	group.free()


## Dissolving a group means every child goes back to the container. Collected
## first because reparenting mutates the child list we would be iterating.
func _promote_children(group: Node3D) -> void:
	var children: Array[Node] = []
	for child in group.get_children():
		children.append(child)
	for child in children:
		if child is Node3D:
			_hierarchy_mgr.reparent_preserve(child, _container)


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


## Find the group node a group/ungroup command is about.
##
## Preference order matters. The instance ID recorded when the action ran is
## authoritative. Snapshot slot 0 carries the group's Blender display name,
## which is uniquely allocated, so it is a safe fallback when the ID has gone
## stale. Neither depends on the group's position among its siblings, which is
## what made "first non-mesh child" resolve to the wrong group.
func _resolve_group_node(snapshot: Array) -> Node3D:
	if not _undo_remove_ids.is_empty():
		var by_id := instance_from_id(_undo_remove_ids[0]) as Node3D
		if is_instance_valid(by_id):
			return by_id
	if not snapshot.is_empty():
		var display: String = snapshot[0].get("display_name", "")
		if display != "":
			var by_name := _find_by_display(display)
			if is_instance_valid(by_name):
				return by_name
	return null


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
