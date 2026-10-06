extends Node

## Regression test for the FlowchartEditor canvas slot-clear.
##
## flowchart_editor.gd declares `canvas` as `Control` while the node is a
## flowchart_editor_canvas.gd instance, whose `puzzle_slots` is typed
## `Array[Dictionary]`. Assigning an untyped `[]` to that typed property through
## the Control-typed receiver fails at runtime:
##   "Invalid assignment of property or key 'puzzle_slots' with value of type
##    'Array' ..." (flowchart_editor.gd:487 @ _clear, called from load_puzzle)
## That is the editor hard-error observed in a live run when a puzzle loads.
##
## The gate's error-grep only matches SCRIPT ERROR / Parse Error / Compile
## Error / Failed to load script, so a bare `ERROR:` line would NOT fail the
## suite. This test detects the decay through state instead: `_clear()` after a
## real puzzle load must leave `canvas.puzzle_slots` empty. With the bug the
## assignment is rejected and the previous (non-empty) slots survive the clear.

var _fail := 0

func _ready() -> void:
	var tree := get_tree()
	_fail = await _run()
	tree.quit(_fail)

func _run() -> int:
	var editor_scene := load("res://scenes/flowchart_editor.tscn") as PackedScene
	var editor := editor_scene.instantiate() as FlowchartEditor
	add_child(editor)
	await get_tree().process_frame

	if editor.canvas == null:
		print("FAIL: FlowchartEditor has no canvas after ready")
		return 1

	editor.load_puzzle("res://data/puzzles/puzzle_1.tres")
	if editor.canvas.puzzle_slots.is_empty():
		print("FAIL: load_puzzle left canvas.puzzle_slots empty (puzzle_1 has slots)")
		return 1

	editor._clear()
	if not editor.canvas.puzzle_slots.is_empty():
		print("FAIL: _clear did not empty canvas.puzzle_slots - stale slots survived the clear")
		return 1

	print("PASS: _clear empties canvas.puzzle_slots after a puzzle load")
	return 0