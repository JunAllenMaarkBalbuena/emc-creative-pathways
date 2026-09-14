extends Node

## Regression test: clicking a hierarchy row whose object was already freed
## (the lesson-switch / Creative-Studio path wipes objects without previously
## rebuilding the tree) triggered "Trying to cast a freed object" inside
## _on_hierarchy_selected(), aborting the handler and freezing the lab.
## Also verifies switching modes leaves no stale rows behind.

var _fail := 0

func _ready() -> void:
	var tree := get_tree()
	var lab_scene := load("res://scenes/modeling_lab/modeling_lab.tscn") as PackedScene
	var lab := lab_scene.instantiate()
	add_child(lab)
	await tree.process_frame
	await tree.process_frame

	var test_obj: MeshInstance3D = null
	if lab._player_objects.size() > 0:
		test_obj = lab._player_objects[0]
	else:
		test_obj = lab.spawner.spawn(PrimitiveDef.Type.CUBE, lab.object_container)

	lab._rebuild_hierarchy()
	var tree_ui: Tree = lab.get_node("%Tree")
	var row := _find_row_for(tree_ui, test_obj)
	if row == null:
		_fail += 1
		print("FAIL: hierarchy rebuild did not list the test object")
		_quit()
		return

	row.select(0)
	test_obj.queue_free()
	await tree.process_frame

	# The stale row is still in the tree at this point (the bug scenario).
	lab._on_hierarchy_selected()
	if lab.selection_manager.get_selected() != null:
		_fail += 1
		print("FAIL: selecting a stale hierarchy row selected a freed object")

	# Switching to Creative Studio must leave no stale rows behind.
	lab._enter_creative_studio()
	var remaining := await _await_row_count(tree_ui, 0)
	if remaining != 0:
		_fail += 1
		print("FAIL: creative studio left %d stale hierarchy rows" % remaining)

	if _fail == 0:
		print("PASS: stale hierarchy rows cannot crash selection and are cleared on studio switch")
	_quit()

func _await_row_count(tree_ui: Tree, expected: int) -> int:
	var root := tree_ui.get_root()
	for i in 40:
		if root == null or root.get_child_count() == expected:
			return root.get_child_count() if root else 0
		await get_tree().process_frame
	return root.get_child_count() if root else 0

func _find_row_for(tree_ui: Tree, node: Node) -> TreeItem:
	var root_item := tree_ui.get_root()
	if root_item == null:
		return null
	var item := root_item.get_first_child()
	while item:
		if item.get_metadata(0) == node:
			return item
		item = item.get_next()
	return null

func _quit():
	get_tree().quit(1 if _fail > 0 else 0)