class_name CommandManager
extends RefCounted

## Snapshot-based undo/redo. Two stacks of ModelingActions.

var undo_stack: Array[ModelingAction] = []
var redo_stack: Array[ModelingAction] = []
var max_steps: int = 15
## When set, every execute/undo/redo re-points the selection onto the action's
## freshly materialized node instances (snapshot rebuilds free + recreate).
## Prevents the cached selection — and therefore the gizmo — from silently
## going stale after any command. If the action created nothing (material,
## delete, group where the group node is not a mesh), reselect no-ops.
var selection_manager: SelectionManager = null


## Execute a command. Returns the primary node affected (for post-execution work).
func execute_command(action: ModelingAction) -> Node3D:
	_log("push type=%s" % action.get_type())
	action.execute()
	undo_stack.push_back(action)
	if undo_stack.size() > max_steps:
		var _discarded: ModelingAction = undo_stack.pop_front()
	redo_stack.clear()
	_log("push done type=%s undo=%d redo=%d" % [action.get_type(), undo_stack.size(), redo_stack.size()])
	_repoint_selection(action)
	return action.get_created_node()


func undo() -> ModelingAction:
	if undo_stack.is_empty():
		return null
	var action: ModelingAction = undo_stack.pop_back()
	action.undo()
	redo_stack.push_back(action)
	_log("undo popped type=%s undo=%d redo=%d" % [action.get_type(), undo_stack.size(), redo_stack.size()])
	_repoint_selection(action)
	return action


func redo() -> ModelingAction:
	if redo_stack.is_empty():
		return null
	var action: ModelingAction = redo_stack.pop_back()
	action.execute()
	undo_stack.push_back(action)
	_log("redo popped type=%s undo=%d redo=%d" % [action.get_type(), undo_stack.size(), redo_stack.size()])
	_repoint_selection(action)
	return action


func _repoint_selection(action: ModelingAction) -> void:
	if selection_manager:
		selection_manager.reselect_from_ids(action.get_last_created_ids())


func _log(msg: String) -> void:
	if ModelingAction.debug_actions:
		print("[CMD] ", msg)


func can_undo() -> bool:
	return not undo_stack.is_empty()


func can_redo() -> bool:
	return not redo_stack.is_empty()


func clear_history() -> void:
	undo_stack.clear()
	redo_stack.clear()
