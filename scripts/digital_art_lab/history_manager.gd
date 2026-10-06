class_name HistoryManager
extends RefCounted

## Manages undo/redo for all user actions using typed UndoAction records.
##
## Three categories:
##   1. Pixel actions (STROKE, FILL, CLEAR) — region-based RGBA8 snapshots.
##   2. Structural actions (ADD/DELETE/DUPLICATE/MERGE/MOVE) — store
##      LayerData references and indices.
##   3. Property actions (visibility, lock, opacity, name) — store both
##      old and new values and swap on undo/redo.

var max_steps := 50

var _undo_stack: Array[UndoAction] = []
var _redo_stack: Array[UndoAction] = []

# Stroke recording state (for STROKE actions only)
var _recording := false
var _record_layer := -1
var _record_region: Rect2i
# Pre-stroke snapshots captured incrementally while the stroke grows. Each
# entry is one newly-exposed strip (rect -> RGBA8 bytes of the strip). Strips
# from successive grows are disjoint because regions nest, and every strip is
# captured *before* the new dab paints it, so they are true pre-stroke pixels.
var _stroke_strips: Dictionary[Rect2i, PackedByteArray] = {}


# ==============================================================
#  Stroke recording API (called from main.gd during a stroke)
# ==============================================================

func begin_stroke(layer_index: int, pos: Vector2i, brush_radius: int, image: Image):
	_recording = true
	_record_layer = layer_index
	_record_region = Rect2i(
		pos.x - brush_radius, pos.y - brush_radius,
		brush_radius * 2, brush_radius * 2
	)
	_stroke_strips.clear()
	_stroke_strips[_record_region] = _capture_region(image, _record_region)


func extend_stroke(pos: Vector2i, brush_radius: int, image: Image):
	if not _recording:
		return
	var dab_rect := Rect2i(
		pos.x - brush_radius, pos.y - brush_radius,
		brush_radius * 2, brush_radius * 2
	)
	var new_region := _record_region.merge(dab_rect)
	if new_region == _record_region:
		return

	# Capture each newly-exposed strip as its own pre-stroke snapshot instead
	# of re-laying out the whole captured region (which was O(region) per
	# grow - quadratic over a long stroke). Strips are disjoint across grows
	# and are captured before the new dab paints them.
	var nr := new_region
	var or_ := _record_region

	if or_.position.y > nr.position.y:
		var r := Rect2i(nr.position.x, nr.position.y, nr.size.x, or_.position.y - nr.position.y)
		_stroke_strips[r] = _capture_region(image, r)
	if or_.position.y + or_.size.y < nr.position.y + nr.size.y:
		var r := Rect2i(nr.position.x, or_.position.y + or_.size.y, nr.size.x,
			nr.position.y + nr.size.y - (or_.position.y + or_.size.y))
		_stroke_strips[r] = _capture_region(image, r)
	if or_.position.x > nr.position.x:
		var top_y := maxi(or_.position.y, nr.position.y)
		var bot_y := mini(or_.position.y + or_.size.y, nr.position.y + nr.size.y)
		if bot_y > top_y:
			var r := Rect2i(nr.position.x, top_y, or_.position.x - nr.position.x, bot_y - top_y)
			_stroke_strips[r] = _capture_region(image, r)
	if or_.position.x + or_.size.x < nr.position.x + nr.size.x:
		var top_y := maxi(or_.position.y, nr.position.y)
		var bot_y := mini(or_.position.y + or_.size.y, nr.position.y + nr.size.y)
		if bot_y > top_y:
			var r := Rect2i(or_.position.x + or_.size.x, top_y,
				nr.position.x + nr.size.x - (or_.position.x + or_.size.x), bot_y - top_y)
			_stroke_strips[r] = _capture_region(image, r)

	_record_region = new_region


func end_stroke(layer_manager: LayerManager):
	if not _recording:
		return
	_recording = false
	if _record_layer < 0 or _record_layer >= layer_manager.layers.size():
		return
	var layer: LayerData = layer_manager.layers[_record_layer]
	if layer == null or layer.image == null:
		return

	var r := _record_region
	var iw: int = layer.image.get_width()
	var ih: int = layer.image.get_height()
	# Clamp to the canvas with a real intersection. The previous hand-rolled
	# clamp (maxi the position, then mini the size against the canvas edge)
	# failed when the region started off-canvas: shifting the position to 0
	# was never deducted from the size, so r kept the off-canvas rows. Those
	# rows had no strip coverage, stayed transparent in `trimmed`, and undo
	# erased a full-width band of pre-stroke content (its thickness matched
	# the off-canvas part of the stroke box) - "random strips erased" when a
	# stroke went over a canvas edge and was then undone.
	r = r.intersection(Rect2i(0, 0, iw, ih))
	if r.size.x <= 0 or r.size.y <= 0:
		return

	# Assemble the pre-stroke bytes for the final (clamped) region from the
	# incremental strips. One O(region) pass per stroke instead of one per grow.
	var trimmed := PackedByteArray()
	trimmed.resize(r.size.x * r.size.y * 4)
	trimmed.fill(0)
	for strip_rect: Rect2i in _stroke_strips.keys():
		var inter := strip_rect.intersection(r)
		if inter.size.x <= 0 or inter.size.y <= 0:
			continue
		var strip: PackedByteArray = _stroke_strips[strip_rect]
		for y in range(inter.size.y):
			for x in range(inter.size.x):
				var src_x := inter.position.x - strip_rect.position.x + x
				var src_y := inter.position.y - strip_rect.position.y + y
				var src_idx := (src_y * strip_rect.size.x + src_x) * 4
				var dst_x := inter.position.x - r.position.x + x
				var dst_y := inter.position.y - r.position.y + y
				var dst_idx := (dst_y * r.size.x + dst_x) * 4
				for c in range(4):
					trimmed[dst_idx + c] = strip[src_idx + c]

	var a := UndoAction.new(UndoAction.Type.STROKE, _record_layer)
	a.region = r
	a.before_pixels = trimmed
	a.after_pixels = _capture_region(layer.image, r)
	_push(a)
	_stroke_strips.clear()


# ==============================================================
#  Public API: push predefined action types
# ==============================================================

func push_fill(layer_index: int, image: Image, region: Rect2i,
		before_pixels: PackedByteArray):
	var a := UndoAction.new(UndoAction.Type.FILL, layer_index)
	a.region = region
	a.before_pixels = before_pixels
	a.after_pixels = _capture_region(image, region)
	_push(a)


func push_add_layer(layer_index: int, layer_data: LayerData):
	var a := UndoAction.new(UndoAction.Type.ADD_LAYER, layer_index)
	a.aux.layer_data = layer_data
	a.aux.index = layer_index
	_push(a)


func push_delete_layer(layer_index: int, layer_data: LayerData):
	var a := UndoAction.new(UndoAction.Type.DELETE_LAYER, layer_index)
	a.aux.layer_data = layer_data
	a.aux.index = layer_index
	_push(a)


func push_move_layer(from_index: int, to_index: int):
	var a := UndoAction.new(UndoAction.Type.MOVE_LAYER)
	a.aux.from_index = from_index
	a.aux.to_index = to_index
	_push(a)


func push_duplicate_layer(layer_index: int, new_data: LayerData):
	var a := UndoAction.new(UndoAction.Type.DUPLICATE_LAYER, layer_index)
	a.aux.layer_data = new_data
	a.aux.index = layer_index + 1
	_push(a)


func push_merge_down(upper_index: int, upper_pre: LayerData, lower_pre: Image,
		lower_post: Image):
	var a := UndoAction.new(UndoAction.Type.MERGE_DOWN, upper_index)
	a.aux.upper_data = upper_pre
	a.aux.lower_pre_image = lower_pre
	a.aux.lower_post_image = lower_post
	a.aux.index = upper_index
	_push(a)


func push_modify_visibility(layer_index: int, old_val: bool):
	var a := UndoAction.new(UndoAction.Type.MODIFY_VISIBILITY, layer_index)
	a.aux.old = old_val
	_push(a)


func push_modify_lock(layer_index: int, old_val: bool):
	var a := UndoAction.new(UndoAction.Type.MODIFY_LOCK, layer_index)
	a.aux.old = old_val
	_push(a)


func push_modify_opacity(layer_index: int, old_val: float, new_val: float):
	var a := UndoAction.new(UndoAction.Type.MODIFY_OPACITY, layer_index)
	a.aux.old = old_val
	a.aux.new = new_val
	_push(a)


func push_modify_name(layer_index: int, old_name: String, new_name: String):
	var a := UndoAction.new(UndoAction.Type.MODIFY_NAME, layer_index)
	a.aux.old = old_name
	a.aux.new = new_name
	_push(a)


func push_clear_layer(layer_index: int, region: Rect2i,
		before_pixels: PackedByteArray, after_pixels: PackedByteArray):
	var a := UndoAction.new(UndoAction.Type.CLEAR_LAYER, layer_index)
	a.region = region
	a.before_pixels = before_pixels
	a.after_pixels = after_pixels
	_push(a)


# ==============================================================
#  Stack management
# ==============================================================

func _push(a: UndoAction):
	_undo_stack.append(a)
	if _undo_stack.size() > max_steps:
		_undo_stack.pop_front()
	_redo_stack.clear()


func clear():
	_undo_stack.clear()
	_redo_stack.clear()
	_recording = false
	_stroke_strips.clear()


func can_undo() -> bool:
	return _undo_stack.size() > 0


func can_redo() -> bool:
	return _redo_stack.size() > 0


# ==============================================================
#  Undo / Redo execution
# ==============================================================

func undo(layer_manager: LayerManager) -> bool:
	if _undo_stack.is_empty():
		return false
	var a: UndoAction = _undo_stack.pop_back()
	_execute(a, false, layer_manager)
	_redo_stack.append(a)
	return true


func redo(layer_manager: LayerManager) -> bool:
	if _redo_stack.is_empty():
		return false
	var a: UndoAction = _redo_stack.pop_back()
	_execute(a, true, layer_manager)
	_undo_stack.append(a)
	return true


func _execute(a: UndoAction, is_redo: bool, lm: LayerManager):
	match a.type:
		UndoAction.Type.STROKE, UndoAction.Type.FILL, UndoAction.Type.CLEAR_LAYER:
			_pixel_swap(a, is_redo, lm)
		UndoAction.Type.ADD_LAYER:
			_undo_add_layer(a, is_redo, lm)
		UndoAction.Type.DELETE_LAYER:
			_undo_delete_layer(a, is_redo, lm)
		UndoAction.Type.MOVE_LAYER:
			_undo_move_layer(a, is_redo, lm)
		UndoAction.Type.DUPLICATE_LAYER:
			_undo_duplicate_layer(a, is_redo, lm)
		UndoAction.Type.MERGE_DOWN:
			_undo_merge_down(a, is_redo, lm)
		UndoAction.Type.MODIFY_VISIBILITY:
			_toggle_bool(a, is_redo, lm, "visible")
		UndoAction.Type.MODIFY_LOCK:
			_toggle_bool(a, is_redo, lm, "locked")
		UndoAction.Type.MODIFY_OPACITY:
			_swap_float(a, is_redo, lm, "opacity")
		UndoAction.Type.MODIFY_NAME:
			_swap_string(a, is_redo, lm, "layer_name")


# --------------------------------------------------------------
#  Pixel actions: restore before (undo) or after (redo) snapshot
# --------------------------------------------------------------

func _pixel_swap(a: UndoAction, is_redo: bool, lm: LayerManager):
	if a.layer_index < 0 or a.layer_index >= lm.layers.size():
		return
	var layer: LayerData = lm.layers[a.layer_index]
	if layer == null or layer.image == null:
		return
	var src := a.after_pixels if is_redo else a.before_pixels
	_restore_region(layer.image, a.region, src)
	lm.mark_dirty_rect(a.region)


# --------------------------------------------------------------
#  ADD_LAYER
# --------------------------------------------------------------

func _undo_add_layer(a: UndoAction, is_redo: bool, lm: LayerManager):
	var data: LayerData = a.aux.layer_data
	if is_redo:
		var idx: int = a.aux.index
		if idx >= 0 and idx <= lm.layers.size():
			lm.layers.insert(idx, data)
			lm.active_index = idx
	else:
		var found := lm.layers.find(data)
		if found >= 0:
			lm.layers.remove_at(found)
			lm.active_index = maxi(0, found - 1)
	lm.composited_dirty = true
	lm.layers_changed.emit()
	lm.active_layer_changed.emit(lm.active_index)


# --------------------------------------------------------------
#  DELETE_LAYER
# --------------------------------------------------------------

func _undo_delete_layer(a: UndoAction, is_redo: bool, lm: LayerManager):
	var data: LayerData = a.aux.layer_data
	if is_redo:
		var found := lm.layers.find(data)
		if found >= 0:
			lm.layers.remove_at(found)
			lm.active_index = maxi(0, found - 1)
	else:
		var idx: int = a.aux.index
		if idx >= 0 and idx <= lm.layers.size():
			lm.layers.insert(idx, data)
			lm.active_index = idx
	lm.composited_dirty = true
	lm.layers_changed.emit()
	lm.active_layer_changed.emit(lm.active_index)


# --------------------------------------------------------------
#  MOVE_LAYER  (swap is its own inverse)
# --------------------------------------------------------------

func _undo_move_layer(a: UndoAction, _is_redo: bool, lm: LayerManager):
	var fi: int = a.aux.from_index
	var ti: int = a.aux.to_index
	if fi < 0 or fi >= lm.layers.size() or ti < 0 or ti >= lm.layers.size():
		return
	var tmp := lm.layers[fi]
	lm.layers[fi] = lm.layers[ti]
	lm.layers[ti] = tmp
	if lm.active_index == fi:
		lm.active_index = ti
	elif lm.active_index == ti:
		lm.active_index = fi
	lm.composited_dirty = true
	lm.layers_changed.emit()
	lm.active_layer_changed.emit(lm.active_index)


# --------------------------------------------------------------
#  DUPLICATE_LAYER
# --------------------------------------------------------------

func _undo_duplicate_layer(a: UndoAction, is_redo: bool, lm: LayerManager):
	var data: LayerData = a.aux.layer_data
	if is_redo:
		var idx: int = a.aux.index
		if idx >= 0 and idx <= lm.layers.size():
			lm.layers.insert(idx, data)
			lm.active_index = idx
	else:
		var found := lm.layers.find(data)
		if found >= 0:
			lm.layers.remove_at(found)
			lm.active_index = maxi(0, found - 1)
	lm.composited_dirty = true
	lm.layers_changed.emit()
	lm.active_layer_changed.emit(lm.active_index)


# --------------------------------------------------------------
#  MERGE_DOWN
# --------------------------------------------------------------

func _undo_merge_down(a: UndoAction, is_redo: bool, lm: LayerManager):
	var ui: int = a.aux.index
	if not is_redo:
		if ui - 1 >= 0 and ui - 1 < lm.layers.size():
			var lower: LayerData = lm.layers[ui - 1]
			if lower != null and lower.image != null and a.aux.lower_pre_image != null:
				lower.image = a.aux.lower_pre_image.duplicate()
		var upper_data: LayerData = a.aux.upper_data
		if upper_data != null and ui >= 0 and ui <= lm.layers.size():
			lm.layers.insert(ui, upper_data.duplicate_layer(upper_data.layer_name))
			lm.active_index = ui
	else:
		if ui >= 0 and ui < lm.layers.size():
			if ui - 1 >= 0:
				var lower: LayerData = lm.layers[ui - 1]
				if lower != null and lower.image != null and a.aux.lower_post_image != null:
					lower.image = a.aux.lower_post_image.duplicate()
			var found := lm.layers.find(a.aux.upper_data)
			if found >= 0:
				lm.layers.remove_at(found)
				lm.active_index = maxi(0, found - 1)
			elif ui < lm.layers.size():
				lm.layers.remove_at(ui)
				lm.active_index = maxi(0, ui - 1)
	lm.composited_dirty = true
	lm.layers_changed.emit()
	lm.active_layer_changed.emit(lm.active_index)


# --------------------------------------------------------------
#  Property helpers
# --------------------------------------------------------------

func _toggle_bool(a: UndoAction, is_redo: bool, lm: LayerManager, prop: String):
	var li := a.layer_index
	if li < 0 or li >= lm.layers.size():
		return
	var layer: LayerData = lm.layers[li]
	var old_val: bool = a.aux.old
	layer.set(prop, !old_val if is_redo else old_val)
	lm.composited_dirty = true
	lm.layers_changed.emit()


func _swap_float(a: UndoAction, is_redo: bool, lm: LayerManager, prop: String):
	var li := a.layer_index
	if li < 0 or li >= lm.layers.size():
		return
	var layer: LayerData = lm.layers[li]
	layer.set(prop, a.aux.new if is_redo else a.aux.old)
	lm.composited_dirty = true
	lm.layers_changed.emit()


func _swap_string(a: UndoAction, is_redo: bool, lm: LayerManager, prop: String):
	var li := a.layer_index
	if li < 0 or li >= lm.layers.size():
		return
	var layer: LayerData = lm.layers[li]
	layer.set(prop, a.aux.new if is_redo else a.aux.old)
	lm.layers_changed.emit()


# ==============================================================
#  Pixel helpers
# ==============================================================

func capture_region(img: Image, rect: Rect2i) -> PackedByteArray:
	return _capture_region(img, rect)


func _capture_region(img: Image, rect: Rect2i) -> PackedByteArray:
	var iw := img.get_width()
	var ih := img.get_height()
	var data: PackedByteArray = PackedByteArray()
	data.resize(rect.size.x * rect.size.y * 4)
	data.fill(0)
	var inside := rect.intersection(Rect2i(0, 0, iw, ih))
	if inside.size.x <= 0 or inside.size.y <= 0:
		return data
	# Bulk-read the in-bounds part as raw RGBA8 bytes, then copy row by row;
	# off-canvas pixels stay transparent (zero-filled above).
	var src := img.get_region(inside)
	var src_bytes: PackedByteArray = src.get_data()
	var src_pitch := inside.size.x * 4
	var dst_pitch := rect.size.x * 4
	var dst_offset := (inside.position.y - rect.position.y) * dst_pitch \
		+ (inside.position.x - rect.position.x) * 4
	for y in range(inside.size.y):
		var s := y * src_pitch
		var d := dst_offset + y * dst_pitch
		for x in range(src_pitch):
			data[d + x] = src_bytes[s + x]
	return data


func _restore_region(img: Image, rect: Rect2i, data: PackedByteArray):
	if data.size() < rect.size.x * rect.size.y * 4:
		return
	var idx: int = 0
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			var c: Color = Color(
				data[idx] / 255.0,
				data[idx + 1] / 255.0,
				data[idx + 2] / 255.0,
				data[idx + 3] / 255.0
			)
			img.set_pixel(x, y, c)
			idx += 4
