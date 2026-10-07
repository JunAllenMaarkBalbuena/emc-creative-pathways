class_name EditorHistory
extends RefCounted

## Two-stack undo/redo for WorldController mutations (plan Task 4). Each op
## pushes a pair of closures that restore exact prior state. Entries are
## plain Dictionaries holding Callables, so the stacks stay flat and cheap;
## the world's closures capture only ids + registry snapshots (never live
## nodes), which is why clear()/drop never leaks scene objects.
##
## Linear-history contract: undo pops to the redo stack, redo returns it, and
## any fresh push drops the whole redo stack ("branch the past, not the
## future"). history_changed fires on every push/undo/redo/clear so UI
## (TopBar undo/redo buttons) can re-read can_undo()/can_redo().

signal history_changed

var _undo_stack: Array[Dictionary] = []
var _redo_stack: Array[Dictionary] = []


## Record an operation. `undo` and `redo` are Callables that restore the
## pre-op state and re-apply it respectively; `label` is a human name for
## future menus/debug (not surfaced yet).
func push(undo: Callable, redo: Callable, label: String) -> void:
	_undo_stack.append({"undo": undo, "redo": redo, "label": label})
	_redo_stack.clear()
	history_changed.emit()


## Pop the newest entry and run its undo closure. Returns false when the
## stack is empty (the caller treats false as "nothing to do", never error).
func undo() -> bool:
	if _undo_stack.is_empty():
		return false
	var entry: Dictionary = _undo_stack.pop_back()
	entry["undo"].call()
	_redo_stack.append(entry)
	history_changed.emit()
	return true


## Pop the redo stack and re-apply the undone operation. Returns false when
## empty.
func redo() -> bool:
	if _redo_stack.is_empty():
		return false
	var entry: Dictionary = _redo_stack.pop_back()
	entry["redo"].call()
	_undo_stack.append(entry)
	history_changed.emit()
	return true


func can_undo() -> bool:
	return not _undo_stack.is_empty()


func can_redo() -> bool:
	return not _redo_stack.is_empty()


## Drop all history. Called after a project load rebuilds the world — stale
## undo entries must never resurrect objects the load removed (Review-Focus
## #3).
func clear() -> void:
	_undo_stack.clear()
	_redo_stack.clear()
	history_changed.emit()