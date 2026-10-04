extends SceneTree

## Comprehensive undo/redo test suite for the snapshot-based command system.

var container: Node3D
var spawner: PrimitiveSpawner
var material_mgr: MaterialManager
var hierarchy_mgr: HierarchyManager
var cmd_mgr: CommandManager
var errors: int = 0


func _init() -> void:
	_run()
	quit(errors)


func _run() -> void:
	container = Node3D.new()
	container.name = "TestContainer"
	root.add_child(container)

	spawner = PrimitiveSpawner.new()
	material_mgr = MaterialManager.new()
	hierarchy_mgr = HierarchyManager.new(container)
	cmd_mgr = CommandManager.new()
	cmd_mgr.max_steps = 15

	_test_spawn_undo_redo()
	_test_delete_undo_redo()
	_test_transform_undo_redo()
	_test_duplicate_undo_redo()
	_test_group_undo_redo()
	_test_ungroup_undo_redo()
	_test_rename_undo_redo()
	_test_undo_stack_limit()
	_test_empty_undo_redo()
	_test_chain_undo_redo()
	_test_duplicate_name_no_collision()
	_test_material_undo_redo()

	container.free()


func _fail(msg: String) -> void:
	print("FAIL: " + msg)
	errors += 1


func _pass(msg: String) -> void:
	print("PASS: " + msg)


func _child_count() -> int:
	return container.get_child_count()


func _find_display(display: String) -> Node3D:
	for c in container.get_children():
		if c is Node3D and HierarchyManager.display_of(c) == display:
			return c
		for gc in c.get_children():
			if gc is Node3D and HierarchyManager.display_of(gc) == display:
				return gc
	return null


# ── Spawn ──────────────────────────────────────────────────────

func _test_spawn_undo_redo() -> void:
	_clear()
	var data := {
		name = "cube", display_name = "cube",
		type = PrimitiveDef.Type.CUBE,
		position = Vector3(1, 0, 0),
		rotation_degrees = Vector3.ZERO, scale = Vector3.ONE,
		material_albedo = Color.WHITE, material_metallic = 0.0, material_roughness = 1.0,
	}
	cmd_mgr.execute_command(CommandFactory.spawn(data, container, spawner, material_mgr, hierarchy_mgr))

	if _child_count() != 1:
		_fail("spawn: expected 1 child, got %d" % _child_count()); return
	var node := _find_display("cube")
	if not node or node.position != Vector3(1, 0, 0):
		_fail("spawn: node missing or wrong position"); return

	cmd_mgr.undo()
	if _child_count() != 0:
		_fail("spawn undo: expected 0 children, got %d" % _child_count()); return

	cmd_mgr.redo()
	if _child_count() != 1:
		_fail("spawn redo: expected 1 child, got %d" % _child_count()); return
	node = _find_display("cube")
	if not node or node.position != Vector3(1, 0, 0):
		_fail("spawn redo: node missing or wrong position"); return

	_pass("spawn undo/redo")


# ── Delete ─────────────────────────────────────────────────────

func _test_delete_undo_redo() -> void:
	_clear()
	var mi1 := spawner.spawn(PrimitiveDef.Type.CUBE, container, false)
	HierarchyManager.assign_blender_name(container, mi1, "cube")
	mi1.position = Vector3(0, 0, 0)
	var mi2 := spawner.spawn(PrimitiveDef.Type.SPHERE, container, false)
	HierarchyManager.assign_blender_name(container, mi2, "sphere")
	mi2.position = Vector3(2, 0, 0)

	var nodes: Array[Node3D] = [mi1, mi2]
	cmd_mgr.execute_command(CommandFactory.delete(nodes, container, spawner, material_mgr, hierarchy_mgr))

	if _child_count() != 0:
		_fail("delete: expected 0, got %d" % _child_count()); return

	cmd_mgr.undo()
	if _child_count() != 2:
		_fail("delete undo: expected 2, got %d" % _child_count()); return
	var r1 := _find_display("cube")
	var r2 := _find_display("sphere")
	if not r1 or not r2:
		_fail("delete undo: nodes not restored"); return
	if r1.position != Vector3(0, 0, 0) or r2.position != Vector3(2, 0, 0):
		_fail("delete undo: positions wrong"); return

	cmd_mgr.redo()
	if _child_count() != 0:
		_fail("delete redo: expected 0, got %d" % _child_count()); return

	_pass("delete undo/redo")


# ── Transform ──────────────────────────────────────────────────

func _test_transform_undo_redo() -> void:
	_clear()
	var mi := spawner.spawn(PrimitiveDef.Type.CUBE, container, false)
	HierarchyManager.assign_blender_name(container, mi, "cube")
	mi.position = Vector3(0, 0, 0)

	var before_t := Transform3D(mi.basis, Vector3(0, 0, 0))
	var after_t := Transform3D(mi.basis, Vector3(5, 3, 0))

	cmd_mgr.execute_command(CommandFactory.transform(
		[container.get_path_to(mi)], [before_t], [after_t],
		container, spawner, material_mgr, hierarchy_mgr
	))

	mi = _find_display("cube")
	if not mi:
		_fail("transform: node missing after execute"); return
	if mi.position.distance_to(Vector3(5, 3, 0)) > 0.01:
		_fail("transform: position wrong, got %s" % str(mi.position)); return

	cmd_mgr.undo()
	mi = _find_display("cube")
	if not mi:
		_fail("transform undo: node missing"); return
	if mi.position.distance_to(Vector3(0, 0, 0)) > 0.01:
		_fail("transform undo: position wrong, got %s" % str(mi.position)); return

	cmd_mgr.redo()
	mi = _find_display("cube")
	if not mi:
		_fail("transform redo: node missing"); return
	if mi.position.distance_to(Vector3(5, 3, 0)) > 0.01:
		_fail("transform redo: position wrong, got %s" % str(mi.position)); return

	_pass("transform undo/redo")


# ── Duplicate ──────────────────────────────────────────────────

func _test_duplicate_undo_redo() -> void:
	_clear()
	var original := spawner.spawn(PrimitiveDef.Type.CUBE, container, false)
	HierarchyManager.assign_blender_name(container, original, "cube")
	original.position = Vector3(0, 0, 0)

	cmd_mgr.execute_command(CommandFactory.duplicate_node(original, container, spawner, material_mgr, hierarchy_mgr))

	if _child_count() != 2:
		_fail("duplicate: expected 2, got %d" % _child_count()); return

	cmd_mgr.undo()
	if _child_count() != 1:
		_fail("duplicate undo: expected 1, got %d" % _child_count()); return
	var orig := _find_display("cube")
	if not orig:
		_fail("duplicate undo: original missing"); return

	cmd_mgr.redo()
	if _child_count() != 2:
		_fail("duplicate redo: expected 2, got %d" % _child_count()); return

	_pass("duplicate undo/redo")


# ── Group ──────────────────────────────────────────────────────

func _test_group_undo_redo() -> void:
	_clear()
	var mi1 := spawner.spawn(PrimitiveDef.Type.CUBE, container, false)
	HierarchyManager.assign_blender_name(container, mi1, "cube")
	mi1.position = Vector3(0, 0, 0)
	var mi2 := spawner.spawn(PrimitiveDef.Type.SPHERE, container, false)
	HierarchyManager.assign_blender_name(container, mi2, "sphere")
	mi2.position = Vector3(2, 0, 0)

	cmd_mgr.execute_command(CommandFactory.group(
		"group", [mi1, mi2], container, spawner, material_mgr, hierarchy_mgr
	))

	if _child_count() != 1:
		_fail("group: expected 1 group, got %d" % _child_count()); return
	var group := _find_display("group")
	if not group:
		_fail("group: group not found"); return
	if group.get_child_count() != 2:
		_fail("group: expected 2 members, got %d" % group.get_child_count()); return

	cmd_mgr.undo()
	if _child_count() != 2:
		_fail("group undo: expected 2, got %d" % _child_count()); return

	cmd_mgr.redo()
	if _child_count() != 1:
		_fail("group redo: expected 1, got %d" % _child_count()); return
	group = _find_display("group")
	if not group or group.get_child_count() != 2:
		_fail("group redo: wrong state"); return

	_pass("group undo/redo")


# ── Ungroup ────────────────────────────────────────────────────

func _test_ungroup_undo_redo() -> void:
	_clear()
	var group := Node3D.new()
	HierarchyManager.assign_blender_name(container, group, "group")
	container.add_child(group)
	group.owner = container

	var mi1 := spawner.spawn(PrimitiveDef.Type.CUBE, group, false)
	HierarchyManager.assign_blender_name(container, mi1, "cube")
	mi1.position = Vector3(0, 0, 0)
	var mi2 := spawner.spawn(PrimitiveDef.Type.SPHERE, group, false)
	HierarchyManager.assign_blender_name(container, mi2, "sphere")
	mi2.position = Vector3(1, 0, 0)

	if _child_count() != 1:
		_fail("ungroup setup: expected 1, got %d" % _child_count()); return

	cmd_mgr.execute_command(CommandFactory.ungroup(group, container, spawner, material_mgr, hierarchy_mgr))

	if _child_count() != 2:
		_fail("ungroup: expected 2, got %d" % _child_count()); return

	cmd_mgr.undo()
	if _child_count() != 1:
		_fail("ungroup undo: expected 1, got %d" % _child_count()); return
	group = _find_display("group")
	if not group or group.get_child_count() != 2:
		_fail("ungroup undo: wrong state"); return

	cmd_mgr.redo()
	if _child_count() != 2:
		_fail("ungroup redo: expected 2, got %d" % _child_count()); return

	_pass("ungroup undo/redo")


# ── Rename ─────────────────────────────────────────────────────

func _test_rename_undo_redo() -> void:
	_clear()
	var mi := spawner.spawn(PrimitiveDef.Type.CUBE, container, false)
	HierarchyManager.assign_blender_name(container, mi, "cube")

	cmd_mgr.execute_command(CommandFactory.rename(mi, "cube", "renamed_cube", container, spawner, material_mgr, hierarchy_mgr))

	var renamed := _find_display("renamed_cube")
	if not renamed:
		_fail("rename: display name not changed"); return

	cmd_mgr.undo()
	var restored := _find_display("cube")
	if not restored:
		_fail("rename undo: node with 'cube' not found"); return

	cmd_mgr.redo()
	renamed = _find_display("renamed_cube")
	if not renamed:
		_fail("rename redo: node with 'renamed_cube' not found"); return

	_pass("rename undo/redo")


# ── Undo stack limit ──────────────────────────────────────────

func _test_undo_stack_limit() -> void:
	cmd_mgr.clear_history()
	cmd_mgr.max_steps = 3

	for i in 5:
		cmd_mgr.execute_command(CommandFactory.spawn({
			name = "obj_%d" % i, display_name = "obj_%d" % i,
			type = PrimitiveDef.Type.CUBE,
			position = Vector3(i, 0, 0),
			rotation_degrees = Vector3.ZERO, scale = Vector3.ONE,
			material_albedo = Color.WHITE, material_metallic = 0.0, material_roughness = 1.0,
		}, container, spawner, material_mgr, hierarchy_mgr))

	if cmd_mgr.undo_stack.size() != 3:
		_fail("stack limit: expected 3, got %d" % cmd_mgr.undo_stack.size()); return

	for i in 3:
		cmd_mgr.undo()

	if cmd_mgr.can_undo():
		_fail("stack limit: can_undo should be false"); return

	_pass("undo stack limit (max_steps=3)")


# ── Empty undo/redo ───────────────────────────────────────────

func _test_empty_undo_redo() -> void:
	cmd_mgr.clear_history()
	if cmd_mgr.undo() != null:
		_fail("empty undo: should return null"); return
	if cmd_mgr.redo() != null:
		_fail("empty redo: should return null"); return
	if cmd_mgr.can_undo() or cmd_mgr.can_redo():
		_fail("empty: can_undo/can_redo should be false"); return
	_pass("empty undo/redo")


# ── Chain ──────────────────────────────────────────────────────

func _test_chain_undo_redo() -> void:
	cmd_mgr.clear_history()
	_clear()

	cmd_mgr.execute_command(CommandFactory.spawn({
		name = "chain_cube", display_name = "chain_cube",
		type = PrimitiveDef.Type.CUBE,
		position = Vector3(0, 0, 0),
		rotation_degrees = Vector3.ZERO, scale = Vector3.ONE,
		material_albedo = Color.WHITE, material_metallic = 0.0, material_roughness = 1.0,
	}, container, spawner, material_mgr, hierarchy_mgr))
	if _child_count() != 1:
		_fail("chain: spawn failed"); return

	var node := _find_display("chain_cube")
	if not node:
		_fail("chain: node not found after spawn"); return
	var path := container.get_path_to(node)
	var before_t := Transform3D(node.basis, Vector3(0, 0, 0))
	var after_t := Transform3D(node.basis, Vector3(10, 0, 0))
	cmd_mgr.execute_command(CommandFactory.transform(
		[path], [before_t], [after_t], container, spawner, material_mgr, hierarchy_mgr
	))

	node = _find_display("chain_cube")
	if not node:
		_fail("chain: node not found after transform"); return
	cmd_mgr.execute_command(CommandFactory.delete(
		[node], container, spawner, material_mgr, hierarchy_mgr
	))
	if _child_count() != 0:
		_fail("chain: delete failed, got %d" % _child_count()); return

	cmd_mgr.undo()
	if _child_count() != 1:
		_fail("chain undo delete: expected 1, got %d" % _child_count()); return
	node = _find_display("chain_cube")
	if not node:
		_fail("chain undo delete: node not found"); return
	if node.position.distance_to(Vector3(10, 0, 0)) > 0.01:
		_fail("chain undo delete: position wrong, got %s" % str(node.position)); return

	cmd_mgr.undo()
	node = _find_display("chain_cube")
	if not node:
		_fail("chain undo transform: node not found"); return
	if node.position.distance_to(Vector3(0, 0, 0)) > 0.01:
		_fail("chain undo transform: position wrong, got %s" % str(node.position)); return

	cmd_mgr.undo()
	if _child_count() != 0:
		_fail("chain undo spawn: expected 0, got %d" % _child_count()); return

	_pass("chain: spawn -> transform -> delete -> undo x3")


# ── Duplicate name collision test ─────────────────────────────

func _test_duplicate_name_no_collision() -> void:
	_clear()
	# Spawn two cubes — Godot auto-renames the second to "CUBE_XXX"
	var mi1 := spawner.spawn(PrimitiveDef.Type.CUBE, container, false)
	HierarchyManager.assign_blender_name(container, mi1, "cube")
	mi1.position = Vector3(0, 0, 0)
	var mi2 := spawner.spawn(PrimitiveDef.Type.CUBE, container, false)
	HierarchyManager.assign_blender_name(container, mi2, "cube")
	mi2.position = Vector3(5, 0, 0)

	if _child_count() != 2:
		_fail("collision setup: expected 2, got %d" % _child_count()); return

	# Transform only the second cube
	var before_t := Transform3D(mi2.basis, Vector3(5, 0, 0))
	var after_t := Transform3D(mi2.basis, Vector3(5, 10, 0))
	cmd_mgr.execute_command(CommandFactory.transform(
		[container.get_path_to(mi2)], [before_t], [after_t],
		container, spawner, material_mgr, hierarchy_mgr
	))

	if _child_count() != 2:
		_fail("collision execute: expected 2, got %d" % _child_count()); return

	# Find both cubes — they should both still exist
	var c1 := _find_display("cube")
	if not c1:
		_fail("collision: first cube missing"); return
	if c1.position.distance_to(Vector3(0, 0, 0)) > 0.01:
		_fail("collision: first cube moved! got %s" % str(c1.position)); return

	# Undo — both cubes should still exist, second one back at original position
	cmd_mgr.undo()
	if _child_count() != 2:
		_fail("collision undo: expected 2, got %d" % _child_count()); return

	c1 = _find_display("cube")
	if not c1:
		_fail("collision undo: first cube missing"); return
	if c1.position.distance_to(Vector3(0, 0, 0)) > 0.01:
		_fail("collision undo: first cube moved! got %s" % str(c1.position)); return

	_pass("duplicate name: no collision on transform undo")


# ── Material ─────────────────────────────────────────────────

func _test_material_undo_redo() -> void:
	_clear()
	var data := {
		name = "cube", display_name = "cube",
		type = PrimitiveDef.Type.CUBE,
		position = Vector3.ZERO,
		rotation_degrees = Vector3.ZERO, scale = Vector3.ONE,
		material_albedo = Color.WHITE, material_metallic = 0.0, material_roughness = 1.0,
	}
	cmd_mgr.execute_command(CommandFactory.spawn(data, container, spawner, material_mgr, hierarchy_mgr))
	var node := _find_display("cube")
	if not node:
		_fail("material: spawn failed"); return

	# Apply red color
	var before_props := {albedo = Color.WHITE, metallic = 0.0, roughness = 0.5}
	var red_props := {albedo = Color.RED, metallic = 0.5, roughness = 0.3}
	cmd_mgr.execute_command(CommandFactory.material(node, before_props, red_props, container, spawner, material_mgr, hierarchy_mgr))

	var mat: StandardMaterial3D = node.get_surface_override_material(0) as StandardMaterial3D
	if not mat:
		_fail("material: no material after apply"); return
	if mat.albedo_color != Color.RED:
		_fail("material: wrong color after apply, got %s" % str(mat.albedo_color)); return
	if abs(mat.metallic - 0.5) > 0.01:
		_fail("material: wrong metallic after apply"); return

	# Undo — should restore white
	cmd_mgr.undo()
	mat = node.get_surface_override_material(0) as StandardMaterial3D
	if not mat:
		_fail("material: no material after undo"); return
	if mat.albedo_color != Color.WHITE:
		_fail("material: wrong color after undo, got %s" % str(mat.albedo_color)); return
	if abs(mat.metallic - 0.0) > 0.01:
		_fail("material: wrong metallic after undo"); return

	# Redo — should be red again
	cmd_mgr.redo()
	mat = node.get_surface_override_material(0) as StandardMaterial3D
	if not mat:
		_fail("material: no material after redo"); return
	if mat.albedo_color != Color.RED:
		_fail("material: wrong color after redo, got %s" % str(mat.albedo_color)); return
	if abs(mat.metallic - 0.5) > 0.01:
		_fail("material: wrong metallic after redo"); return

	_pass("material undo/redo")


func _clear() -> void:
	for c in container.get_children():
		c.free()
	cmd_mgr.clear_history()
