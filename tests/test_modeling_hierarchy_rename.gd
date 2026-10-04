extends Node

## Regression test: the hierarchy Rename button must open inline editing of
## the selected row, and committing a typed name must rename the object to
## exactly that name. It must NOT append "_renamed" to the object's name.
## Covers: rename appending a suffix instead of editing, non-editable rows,
## and empty/whitespace commits leaving the name unchanged.

var _fail := 0
var _tree: Tree

func _ready() -> void:
	var tree := get_tree()
	var lab: ModelingLab = (load("res://scenes/modeling_lab/modeling_lab.tscn") as PackedScene).instantiate()
	add_child(lab)
	tree.create_timer(30.0).timeout.connect(_on_watchdog)
	await tree.process_frame
	await tree.process_frame
	_tree = lab.get_node("%Tree")

	# 1) Enter Creative Studio and spawn one object.
	lab._enter_creative_studio()
	if not await _await_rows(0):
		_fail += 1
		print("FAIL: creative studio should start empty")
	lab._on_spawn_selected(PrimitiveDef.Type.CUBE)
	if not await _await_rows(1):
		_fail += 1
		print("FAIL: spawn should add a hierarchy row")

	var row := _first_row()
	var node := row.get_metadata(0) as MeshInstance3D
	if not is_instance_valid(node):
		_fail += 1
		print("FAIL: spawned row metadata is invalid")
		_quit()
		return
	var original_name := String(node.name)

	# 2) The row's name column must be editable so it can be renamed inline.
	if not row.is_editable(0):
		_fail += 1
		print("FAIL: hierarchy name column is not editable")

	# 3) Renaming via the Rename button must keep the object name untouched
	#    (the button only starts inline editing).
	row.select(0)
	lab._on_hierarchy_rename()
	if String(node.name) != original_name:
		_fail += 1
		print("FAIL: rename button changed the object name to '%s' instead of opening inline editing" % node.name)

	# 4) Committing a typed name renames the object to exactly that text.
	if lab.has_method("_on_tree_item_edited"):
		row.set_text(0, "MyCube")
		lab._on_tree_item_edited()
		if String(node.name) != "MyCube":
			_fail += 1
			print("FAIL: committed name should rename object to 'MyCube', got '%s'" % node.name)

		# 5) An empty/whitespace commit must leave the name unchanged.
		row.set_text(0, "   ")
		lab._on_tree_item_edited()
		if String(node.name) != "MyCube":
			_fail += 1
			print("FAIL: empty commit should leave name unchanged, got '%s'" % node.name)
	else:
		_fail += 1
		print("FAIL: _on_tree_item_edited handler is missing")

	if _fail == 0:
		print("PASS: hierarchy rename opens inline editing and renames to typed name")
	_quit()

func _await_rows(expected: int, max_frames := 40) -> bool:
	for i in max_frames:
		await get_tree().process_frame
		if _row_count() == expected:
			return true
	return false

func _row_count() -> int:
	var root := _tree.get_root()
	if root == null:
		return 0
	return root.get_child_count()

func _first_row() -> TreeItem:
	return _tree.get_root().get_first_child()

func _on_watchdog():
	get_tree().quit(2)

func _quit():
	get_tree().quit(1 if _fail > 0 else 0)