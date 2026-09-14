extends Node

## Regression test: the hierarchy tree must reflect spawn and delete,
## and clicking a stale row (row whose object was freed) must self-heal
## without crashing or leaving ghost rows.
## Covers: spawn not appearing, delete/session-clear leaving ghost rows,
## and the "tree cleared during mouse selection" error class.

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

	# 1) Lesson assignment primitives populate the hierarchy.
	if _row_count() == 0:
		_fail += 1
		print("FAIL: lesson primitives should populate the hierarchy")

	# 2) Enter Creative Studio: starts empty (no ghost rows from the lesson).
	lab._enter_creative_studio()
	if not await _await_rows(0):
		_fail += 1
		print("FAIL: creative studio should start with an empty hierarchy, got %d" % _row_count())

	# 3) Spawning an object must add a row.
	lab._on_spawn_selected(PrimitiveDef.Type.CUBE)
	if not await _await_rows(1):
		_fail += 1
		print("FAIL: spawn should add a hierarchy row, got %d" % _row_count())
	else:
		var meta: Variant = _first_row().get_metadata(0)
		if not is_instance_valid(meta):
			_fail += 1
			print("FAIL: spawned row metadata is invalid")

	# 4) Deleting the object must remove its row.
	lab._on_delete()
	if not await _await_rows(0):
		_fail += 1
		print("FAIL: delete should remove the hierarchy row, got %d" % _row_count())

	# 5) Clicking a stale row (object freed underneath it) self-heals.
	lab._on_spawn_selected(PrimitiveDef.Type.CUBE)
	if not await _await_rows(1):
		_fail += 1
		print("FAIL: spawn #2 should add a hierarchy row")
	else:
		var stale_row := _first_row()
		var freed_node := stale_row.get_metadata(0) as MeshInstance3D
		freed_node.queue_free()
		await tree.process_frame
		stale_row.select(0)
		lab._on_hierarchy_selected()
		if not await _await_rows(0):
			_fail += 1
			print("FAIL: stale row click left %d ghost row(s)" % _row_count())
	var sel := lab.selection_manager.get_selected()
	if sel != null and not is_instance_valid(sel):
		_fail += 1
		print("FAIL: selection manager holds a freed object")

	if _fail == 0:
		print("PASS: hierarchy reflects spawn/delete and stale clicks self-heal")
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