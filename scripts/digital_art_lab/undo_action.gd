class_name UndoAction
extends RefCounted

## Unified action record for undo/redo. Every user action (stroke, fill,
## layer add/delete/merge/property change) produces one UndoAction that
## stores enough data to fully reverse and re-apply itself.
##
## Efficiency notes:
##  - Pixel actions (STROKE, FILL, CLEAR) store region-based snapshots.
##  - Structural actions (ADD/DELETE/DUPLICATE/MERGE) store LayerData
##    references so the data stays alive without serialization cost.
##  - Property actions (visibility, lock, opacity, name) store only the
##    changed values in the `aux` dictionary.

enum Type {
	STROKE,          # Brush / erase stroke (region snapshot)
	FILL,            # Flood fill (full-layer snapshot)
	CLEAR_LAYER,     # Clear layer pixels (full-layer snapshot)
	ADD_LAYER,       # Add new empty layer
	DELETE_LAYER,    # Delete an existing layer
	MOVE_LAYER,      # Reorder a layer up/down
	DUPLICATE_LAYER, # Duplicate a layer
	MERGE_DOWN,      # Merge a layer into the one below
	MODIFY_VISIBILITY,
	MODIFY_LOCK,
	MODIFY_OPACITY,
	MODIFY_NAME,
}

var type: Type
var layer_index: int          # Primary affected layer index (at time of action)
var region: Rect2i            # Bound box for pixel snapshots
var before_pixels: PackedByteArray  # Pixel state before the action
var after_pixels: PackedByteArray   # Pixel state after the action (for redo)
var aux: Dictionary           # Extra data: layer refs, indices, old property values

func _init(t: Type, li: int = -1):
	type = t
	layer_index = li
	aux = {}
