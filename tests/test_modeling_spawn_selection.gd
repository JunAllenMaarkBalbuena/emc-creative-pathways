extends SceneTree

## Regression test: spawning an object in the 3D modeling lab must not crash
## with "Invalid type in function '_deselect_highlight' ... argument 1
## (previously freed)". Root cause: _clear_objects() queue_free()s every
## non-ghost MeshInstance3D without clearing SelectionManager._selected. The
## next spawn (or click-select) then calls _deselect_highlight() with the freed
## node. Repro happens in Creative Studio (SpawnBtn) right after leaving a lesson.

func _initialize() -> void:
	_run()

func _run() -> void:
	var fail := 0
	var container := Node3D.new()
	root.add_child(container)
	var spawner := PrimitiveSpawner.new()
	var selection := SelectionManager.new(container)

	# Lesson flow: player primitives get spawned and the first one is selected.
	var first := spawner.spawn(PrimitiveDef.Type.CUBE, container)
	selection.select(first)

	# _clear_objects() replica: frees every non-ghost primitive.
	for child in container.get_children():
		if child is MeshInstance3D:
			child.queue_free()
	await process_frame

	# Selection must not be left dangling on a freed node after clearing.
	if selection.get_selected() != null:
		fail += 1
		print("FAIL: _clear_objects left a dangling selection on a freed node")

	# Creative Studio spawn replica: spawning selects the new primitive.
	var spawned := spawner.spawn(PrimitiveDef.Type.CONE, container)
	selection.select(spawned)
	if selection.get_selected() != spawned:
		fail += 1
		print("FAIL: spawned object was not selected")

	if fail == 0:
		print("PASS: spawning after clearing objects selects the new primitive without touching a freed node")
	quit(1 if fail > 0 else 0)