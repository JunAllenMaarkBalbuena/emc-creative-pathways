extends Node

## RED guard: parenting ("group") + Blender-style naming in the modeling lab.
## User-facing behaviors under test (approved in brainstorming):
##   1. Spawn names use Blender-style per-type counters: cube, cube.001,
##      cube.002 … (sphere is independent: sphere, sphere.001 …).
##   2. Duplicate allocates the next Blender name (cube.002 -> cube.003),
##      no Godot "@" collisions.
##   3. Parent (with 2+ objects selected) creates a "group" Node3D (then
##      group.001, group.002 …) and reparents the members under it,
##      preserving their world transforms.
##   4. Parent with a single selection is a no-op.
##   5. Unparent detaches selected members back to the top-level
##      ObjectContainer, preserving world position. Empty groups stay behind.
##   6. The hierarchy tree data reports nesting: group rows at depth 0,
##      members at depth 1.

var _fail := 0

func _ready() -> void:
	var tree := get_tree()
	var lab: ModelingLab = (load("res://scenes/modeling_lab/modeling_lab.tscn") as PackedScene).instantiate()
	add_child(lab)
	tree.create_timer(30.0).timeout.connect(_on_watchdog)
	await tree.process_frame
	await tree.process_frame
	lab._enter_creative_studio()
	await tree.process_frame

	var container: Node3D = lab.object_container

	# ── 1) Blender-style spawn names ──────────────────────────────
	lab._on_spawn_selected(PrimitiveDef.Type.CUBE)
	lab._on_spawn_selected(PrimitiveDef.Type.CUBE)
	lab._on_spawn_selected(PrimitiveDef.Type.SPHERE)
	lab._on_spawn_selected(PrimitiveDef.Type.CUBE)
	await tree.process_frame

	var a: MeshInstance3D = _mesh_child(container, 0)
	var b: MeshInstance3D = _mesh_child(container, 1)
	var s: MeshInstance3D = _mesh_child(container, 2)
	var c: MeshInstance3D = _mesh_child(container, 3)
	if not a or not b or not s or not c:
		_fail += 1
		print("FAIL: expected 4 spawned objects, got none usable")
		_quit()
		return
	_check("cube" == HierarchyManager.display_of(a), "first cube named 'cube', got '%s'" % HierarchyManager.display_of(a))
	_check("cube.001" == HierarchyManager.display_of(b), "second cube named 'cube.001', got '%s'" % HierarchyManager.display_of(b))
	_check("sphere" == HierarchyManager.display_of(s), "sphere named 'sphere', got '%s'" % HierarchyManager.display_of(s))
	_check("cube.002" == HierarchyManager.display_of(c), "third cube named 'cube.002', got '%s'" % HierarchyManager.display_of(c))

	a.position = Vector3(-2, 0.5, 0)
	b.position = Vector3(-0.5, 0.5, 0)
	s.position = Vector3(1, 0.5, 0)
	c.position = Vector3(2.5, 0.5, 0)
	await tree.process_frame

	# ── 2) Duplicate allocates the next name ──────────────────────
	lab.selection_manager.select(c)
	lab._on_duplicate()
	await tree.process_frame
	var d: MeshInstance3D = _by_name(container, "cube.003")
	if d:
		_check(d.global_position.is_equal_approx(c.global_position + Vector3(0.5, 0.5, 0.5)),
				"duplicate offset from source")
	else:
		_fail += 1
		print("FAIL: duplicate should be named 'cube.003', got no such sibling")

	# ── 3) Parent groups 2+ selected members, preserving position ─
	var wpos_a: Vector3 = a.global_position
	var wpos_b: Vector3 = b.global_position
	lab.selection_manager.select_multi([a, b])
	lab._on_hierarchy_parent()
	await tree.process_frame

	var group1 := _group_named(container, "group")
	if group1 == null:
		_fail += 1
		print("FAIL: Parent (2 selected) should create a 'group' Node3D")
	else:
		_check(a.get_parent() == group1, "cube a parented under group")
		_check(b.get_parent() == group1, "cube b parented under group")
		_check(a.global_position.is_equal_approx(wpos_a),
				"a world position preserved on parent (got %s want %s)" % [a.global_position, wpos_a])
		_check(b.global_position.is_equal_approx(wpos_b),
				"b world position preserved on parent (got %s want %s)" % [b.global_position, wpos_b])

	# ── 6) Tree data reports nesting ──────────────────────────────
	var tree_data := lab.hierarchy_manager.get_tree_data()
	var group_row := tree_data.filter(func(e): return e.node == group1)
	var a_row := tree_data.filter(func(e): return e.node == a)
	var b_row := tree_data.filter(func(e): return e.node == b)
	if group_row.is_empty():
		_fail += 1
		print("FAIL: tree data should include the group row")
	else:
		_check(group_row[0].depth == 0, "group row at depth 0")
	if not a_row.is_empty() and not b_row.is_empty():
		_check(a_row[0].depth == 1, "member a row at depth 1 (got %d)" % a_row[0].depth)
		_check(b_row[0].depth == 1, "member b row at depth 1 (got %d)" % b_row[0].depth)

	# ── 7) Clicking a group row selects all members ───────────────
	# The hierarchy Tree uses SELECT_MULTI, which emits multi_selected (NOT
	# item_selected) on click. Emit the real signal Godot fires for the group
	# row and assert every member becomes selected.
	var hierarchy_tree: Tree = lab.get_node("%Tree")
	var group_item := _tree_item_by_meta(hierarchy_tree.get_root(), group1)
	lab.selection_manager.deselect_all()
	if group_item == null:
		_fail += 1
		print("FAIL: group row TreeItem not found")
	else:
		group_item.select(0)
		hierarchy_tree.multi_selected.emit(group_item, 0, true)
		await tree.process_frame
		var sel_after_group_click := lab.selection_manager.selected_nodes()
		var want := [a, b]
		if sel_after_group_click.size() != want.size():
			_fail += 1
			print("FAIL: group row click selected %d members, expected %d" % [sel_after_group_click.size(), want.size()])
		else:
			var all_members := true
			for m in want:
				if not m in sel_after_group_click:
					all_members = false
			_check(all_members, "group row click selects every member")

	# ── 5) Unparent detaches to top level, position preserved ────
	var wpos_a2: Vector3 = a.global_position
	lab.selection_manager.select_multi([a])
	lab._on_hierarchy_unparent()
	await tree.process_frame
	_check(a.get_parent() == container, "unparent detaches a to ObjectContainer")
	_check(a.global_position.is_equal_approx(wpos_a2),
			"a world position preserved on unparent (got %s want %s)" % [a.global_position, wpos_a2])
	_check(b.get_parent() == group1, "unparent leaves b in its group")

	# ── Second group gets group.001, fresh original names stay clear ──
	lab.selection_manager.select_multi([s, c])
	lab._on_hierarchy_parent()
	await tree.process_frame
	var group2 := _group_named(container, "group.001")
	if group2 == null:
		_fail += 1
		print("FAIL: second Parent should create 'group.001'")
	else:
		_check(s.get_parent() == group2, "sphere parented under group.001")
		_check(c.get_parent() == group2, "cube c parented under group.001")
	_check(_group_named(container, "group") == group1, "first group still named 'group'")

	# ── 4) Parent with a single selection is a no-op ──────────────
	var group_count := _group_count(container)
	lab.selection_manager.select(d)
	lab._on_hierarchy_parent()
	await tree.process_frame
	_check(_group_count(container) == group_count, "Parent with 1 selected creates no new group")

	# ── 8) Detaching the last member leaves the emptied group behind ──
	# Detach is a distinct command from ungroup, so its undo has to restore the
	# member to the group it left rather than merely to the top level. This is
	# also the extreme case of "empty groups stay behind": the group has no
	# members at all once b has left.
	lab.selection_manager.select_multi([b])
	lab._on_hierarchy_unparent()
	await tree.process_frame
	_check(b.get_parent() == container, "detaching last member returns b to ObjectContainer")
	_check(_group_named(container, "group") == group1, "group survives being emptied")

	lab.undo_redo.undo()
	await tree.process_frame
	_check(b.get_parent() == group1, "undo of Clear Parent returns b to its group (got %s)" % b.get_parent().name)
	_check(a.get_parent() == container, "undo of Clear Parent leaves a at the top level")

	if _fail == 0:
		print("PASS: parent/group + Blender naming")
	else:
		print("FAIL: %d assertion(s) failed" % _fail)
	_quit()


func _check(cond: bool, msg: String):
	if not cond:
		_fail += 1
		print("FAIL: " + msg)


func _mesh_child(container: Node3D, index: int) -> MeshInstance3D:
	var n := 0
	for child in container.get_children():
		if child is MeshInstance3D and not child.is_in_group("ghost_guides"):
			if n == index:
				return child
			n += 1
	return null


func _tree_item_by_meta(item: TreeItem, node: Node) -> TreeItem:
	if item == null:
		return null
	if is_instance_valid(item.get_metadata(0)) and item.get_metadata(0) == node:
		return item
	for i in item.get_child_count():
		var found := _tree_item_by_meta(item.get_child(i), node)
		if found:
			return found
	return null


func _by_name(container: Node3D, cname: String) -> MeshInstance3D:
	for child in container.get_children():
		if HierarchyManager.display_of(child) == cname and child is MeshInstance3D and not child.is_in_group("ghost_guides"):
			return child
	return null


func _group_named(container: Node3D, gname: String) -> Node3D:
	for child in container.get_children():
		if HierarchyManager.display_of(child) == gname and child is Node3D and not child is MeshInstance3D:
			return child
	return null


func _group_count(container: Node3D) -> int:
	var n := 0
	for child in container.get_children():
		if child is Node3D and not child is MeshInstance3D:
			n += 1
	return n


func _on_watchdog():
	print("FAIL: watchdog timeout")
	get_tree().quit(1)


func _quit():
	get_tree().quit(1 if _fail > 0 else 0)