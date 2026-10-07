extends Control

## Dock resize strip (plan Task 6): a thin 6px divider that drags the
## attached panel's edge. `axis` selects orientation — 0 = a vertical strip
## that resizes left/right edges, 1 = a horizontal strip that resizes
## top/bottom edges. `side` picks which edge moves: +1 = right/bottom,
## -1 = left/top. `_apply(delta)` (also called from _gui_input while
## dragging) moves the target's offset_* by delta, clamped so the panel
## never collapses below MIN_WIDTH and never leaves the window, then the
## strip re-glues itself to the moved edge so the divider always sits on
## (just outside) the panel boundary.
##
## Deltas are pixel offsets, not anchor fractions: the editor-authored
## anchor layout (LayersPanel 0..0.45, Inspector 0.55..1.0) is preserved,
## so resizing one docker never disturbs its neighbours. No class_name on
## purpose — the root and tests hold plain Control references.

const MIN_WIDTH := 120.0
const EDGE_MARGIN := 32.0
const STRIP_GAP := 2.0
const STRIP_THICKNESS := 6.0

@export var target: NodePath
@export var axis := 0  # 0 = vertical strip (moves left/right edges), 1 = horizontal strip (moves top/bottom)
@export var side := 1  # +1 = right/bottom edge, -1 = left/top edge

var _dragging := false


func _gui_input(event: InputEvent) -> void:
	var mouse := event as InputEventMouseButton
	if mouse != null and mouse.button_index == MOUSE_BUTTON_LEFT:
		_dragging = mouse.pressed
		accept_event()
		return
	var motion := event as InputEventMouseMotion
	if motion != null and _dragging:
		var raw: float = motion.relative.x if axis == 0 else motion.relative.y
		_apply(raw * float(side))
		accept_event()


## Move the target's edge by `delta` pixels (deltas clamp). Public on
## purpose: the structural test simulates drags by calling it directly.
func _apply(delta: float) -> void:
	var t := get_node_or_null(target) as Control
	if t == null:
		return
	var parent_c := get_parent() as Control
	if parent_c == null:
		return
	if axis == 0:
		if side > 0:
			var max_d := parent_c.size.x - EDGE_MARGIN - t.size.x - t.position.x
			t.offset_right += clampf(delta, MIN_WIDTH - t.size.x, max_d)
		else:
			var max_d2 := t.position.x - EDGE_MARGIN
			t.offset_left -= clampf(delta, MIN_WIDTH - t.size.x, max_d2)
	else:
		if side > 0:
			var max_d3 := parent_c.size.y - EDGE_MARGIN - t.size.y - t.position.y
			t.offset_bottom += clampf(delta, MIN_WIDTH - t.size.y, max_d3)
		else:
			var max_d4 := t.position.y - EDGE_MARGIN
			t.offset_top -= clampf(delta, MIN_WIDTH - t.size.y, max_d4)
	_glue()


## Slide the strip against the target's moved edge (absolute offsets: the
## strip's anchors on the move axis are 0, so offset_* == pixel position).
func _glue() -> void:
	var t := get_node_or_null(target) as Control
	if t == null:
		return
	if axis == 0:
		var edge: float = t.position.x + t.size.x if side > 0 else t.position.x
		offset_left = edge + STRIP_GAP
		offset_right = edge + STRIP_GAP + STRIP_THICKNESS
	else:
		var edge2: float = t.position.y + t.size.y if side > 0 else t.position.y
		offset_top = edge2 + STRIP_GAP
		offset_bottom = edge2 + STRIP_GAP + STRIP_THICKNESS