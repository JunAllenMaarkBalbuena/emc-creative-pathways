extends Control

## Multi-track timeline canvas (Task 3): a single custom-drawn Control that
## consumes the Task 2 lane model and emits Task 4's eight signals. One `_draw`
## pass from state precomputed in refresh(); nothing runs per engine frame
## except the playhead moving on `timeline.time_changed` (never a lane rebuild).
##
## Layout (spec §5, px verbatim): ruler 32px (minor tick per frame, labels
## every 5th frame decimated so labels sit >= 48px apart), lanes 24px with a
## 96px label gutter, key ticks 3px tall, world-time -> x is `offset + t*pps`.
## Key colors: position #4caf50, rotation #2196f3, scale #ffc107, visible
## #9c27b0; camera/light lanes use their single color #00bcd4 / #ff7043.
##
## Gestures (_gui_input, mouse + touch): tap-vs-drag by an 8px movement
## threshold; tap lane -> lane_pressed, tap ruler (on press) ->
## playhead_requested(snap), double-tap empty lane (300ms, <=8px apart) ->
## key_add_requested; drag a key tick -> key_move_requested (index resolved
## once at press via key_index_at, snap state captured at drag activation);
## drag empty lane -> marquee span (selection drawn as a tinted band, keys from
## range_keys at use); drag inside a selection -> span_slide_requested; Ctrl-
## drag inside a selection -> span_duplicate_requested. Delete/Backspace and
## delete_selection() -> keys_remove_requested (silent when empty or the span
## resolves to no keys). Every press path grabs keyboard focus
## (FOCUS_CLICK), which is what lets Godot deliver Delete/Backspace to this
## control in a live window. Wheel zoom anchors at the pointer, pinch at the
## two-finger centroid, zoom_in/out() at the playhead; `pps` in [24, 240],
## x1.5 steps; the draw offset keeps `t = 0` at or left of the left edge.
##
## Touch pinch: two tracked InputEventScreenTouch indices; a 16px distance
## change per drag event is one x1.5 zoom step RELATIVE to the current zoom
## (no baseline reset - any prior zoom state continues from where it is);
## the second finger cancels the pending single-touch tap.

signal lane_pressed(lane_id: String, lane_kind: int)
signal playhead_requested(time: float)
signal key_add_requested(lane_id: String, lane_kind: int, time: float)
signal key_move_requested(index: int, from_time: float, to_time: float)
signal keys_remove_requested(indices: Array[int])
signal span_slide_requested(indices: Array[int], delta: float)
signal span_duplicate_requested(indices: Array[int], offset: float)
signal snap_toggled(on: bool)

const TimelineLaneModel := preload("res://scripts/animation_production_lab/ui/timeline_lane_model.gd")

const RULER_H := 32.0
const LANE_H := 24.0
const GUTTER := 96.0
const TICK_H := 3.0
const TICK_W := 2.0
const MIN_PPS := 24.0
const MAX_PPS := 240.0
const DEFAULT_PPS := 96.0
const ZOOM_STEP := 1.5
const DRAG_PX := 8.0
const PINCH_PX := 16.0
const DOUBLE_TAP_MS := 300
const KEY_TOLERANCE := 4.0
const LABEL_GAP := 48.0
const LABEL_EVERY := 5
const HIT_LANE_IGNORE_Y := 10000.0

const COL_POSITION := Color("4caf50")
const COL_ROTATION := Color("2196f3")
const COL_SCALE := Color("ffc107")
const COL_VISIBLE := Color("9c27b0")
const COL_CAMERA := Color("00bcd4")
const COL_LIGHT := Color("ff7043")
const COL_PLAYHEAD := Color(1.0, 0.38, 0.35, 0.9)
const COL_SELECTION := Color(0.35, 0.55, 1.0, 0.22)
const COL_UNKNOWN_KEY := Color(0.8, 0.8, 0.85, 1.0)

var _world: WorldController
var _keyframes: KeyframeController
var _frames: FrameController
var _timeline: TimelineController
var _lighting: LightingController
var _model: TimelineLaneModel

var _snap := true
var _pps := DEFAULT_PPS
var _offset := 0.0
var _playhead := 0.0
var _refresh_count := 0
var _draw_count := 0  # test hook: proves the natural redraw path ran (headless)

var _lanes: Array[Dictionary] = []
var _lane_ids: Array[String] = []
var _selection: Dictionary = {}  # lane_id -> {"start": float, "end": float}

var _ruler_ticks := PackedFloat32Array()
var _ruler_labels: Array = []  # [x, text]
var _frame_boundary_xs := PackedFloat32Array()

# gesture state (mouse + single-touch share this session)
var _press_active := false
var _press_pos := Vector2.ZERO
var _press_in_ruler := false
var _press_lane_id := ""
var _press_lane_kind := -1
var _press_key_index := -1
var _press_inside_selection := false
var _press_start_time := 0.0
var _ctrl_down := false
var _drag_active := false
var _drag_mode := ""  # "", "key", "marquee", "span_slide", "span_dup", "scrub"
var _drag_snap := true
var _drag_last := Vector2.ZERO
var _key_index := -1
var _key_from := 0.0
var _span_indices: Array[int] = []
var _marquee_start := 0.0
var _last_tap_time := -1
var _last_tap_token := ""
var _last_tap_pos := Vector2.ZERO

# touch bookkeeping
var _touch_pos: Dictionary = {}  # index -> Vector2
var _pending_touch := -1
var _pinch_indices: Array[int] = []
var _pinch_dist := 0.0


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_ruler()


# ---------------------------------------------------------------- sources ---

## Stores the sources, (re)wires the two subscriptions the editor owns
## (timeline.time_changed -> playhead-only redraw; keyframes.keyframes_changed
## -> rebuild) and refreshes. Re-bind is safe: subscriptions are disconnected
## from the previous timeline/keyframes before connecting.
func set_sources(world, keyframes, frames, timeline, lighting) -> void:
	_wire_timeline(timeline)
	_wire_keyframes(keyframes)
	_world = world
	_keyframes = keyframes
	_frames = frames
	_timeline = timeline
	_lighting = lighting
	if _model == null:
		_model = TimelineLaneModel.new()
	_model.world = world
	_model.keyframes = keyframes
	_model.frames = frames
	_model.timeline = timeline
	_model.lighting = lighting
	refresh()


func _wire_timeline(timeline: TimelineController) -> void:
	if _timeline != null and _timeline.time_changed.is_connected(_on_time_changed):
		_timeline.time_changed.disconnect(_on_time_changed)
	if timeline != null:
		timeline.time_changed.connect(_on_time_changed)


func _wire_keyframes(keyframes: KeyframeController) -> void:
	if _keyframes != null and _keyframes.keyframes_changed.is_connected(_on_keyframes_changed):
		_keyframes.keyframes_changed.disconnect(_on_keyframes_changed)
	if keyframes != null:
		keyframes.keyframes_changed.connect(_on_keyframes_changed)


## Playback redraw (spec §7): the playhead moved — redraw only, never rebuild
## lanes (a refresh() counter is exposed so tests can assert the split).
func _on_time_changed(time: float) -> void:
	_playhead = time
	queue_redraw()


func _on_keyframes_changed() -> void:
	refresh()


## Rebuild lanes from the model, clear per-lane selections when the lane set
## changed, precompute drawing state, then redraw. The only rebuild path.
func refresh() -> void:
	if _model == null:
		_model = TimelineLaneModel.new()
	_lanes = _model.lanes()
	var ids: Array[String] = []
	for lane in _lanes:
		ids.append(str(lane["id"]))
	if ids != _lane_ids:
		_lane_ids = ids
		_selection.clear()
	_refresh_count += 1
	_layout_ruler()
	queue_redraw()


# ---------------------------------------------------------------- public ---

func set_snap(on: bool) -> void:
	if on == _snap:
		return
	_snap = on
	snap_toggled.emit(on)


func get_snap() -> bool:
	return _snap


## Model delegate: nearest frame boundary, clamped to [0, duration]; the
## fallback replicates the model's defaults before sources are wired.
func snap_time(time: float) -> float:
	if _model != null:
		return _model.snap_time(time)
	var fps := 12.0
	var duration := 5.0
	return clampf(roundf(time * fps) / fps, 0.0, duration)


func get_pps() -> float:
	return _pps


func get_draw_offset() -> float:
	return _offset


func get_refresh_count() -> int:
	return _refresh_count


func get_draw_count() -> int:
	return _draw_count


func get_playhead_time() -> float:
	return _playhead


func zoom_in() -> void:
	_zoom_anchored_at_playhead(ZOOM_STEP)


func zoom_out() -> void:
	_zoom_anchored_at_playhead(1.0 / ZOOM_STEP)


## Emit keys_remove_requested for the current selection; no signal when the
## selection is empty or resolves to no keys.
func delete_selection() -> void:
	var indices := _selection_indices()
	if indices.is_empty():
		return
	keys_remove_requested.emit(indices)


# ---------------------------------------------------------------- zoom -----

func _zoom_anchored_at_playhead(factor: float) -> void:
	_apply_zoom(_offset + _playhead * _pps, _playhead, factor)


func _zoom_at_pointer(x: float, factor: float) -> void:
	_apply_zoom(x, _time_at(x), factor)


func _apply_zoom(anchor_x: float, anchor_time: float, factor: float) -> void:
	var new_pps := clampf(_pps * factor, MIN_PPS, MAX_PPS)
	if is_equal_approx(new_pps, _pps):
		return
	_pps = new_pps
	_offset = minf(0.0, anchor_x - anchor_time * _pps)
	_layout_ruler()
	queue_redraw()


# ---------------------------------------------------------------- draw -----

func _draw() -> void:
	_draw_count += 1
	var w := size.x
	var h := size.y
	if w <= 0.0 or h <= 0.0:
		return
	draw_rect(Rect2(0, 0, w, h), Color(0.06, 0.07, 0.10, 1.0))
	draw_rect(Rect2(0, 0, w, RULER_H), Color(0.12, 0.13, 0.17, 1.0))
	var content_h := h - RULER_H
	if content_h > 0.0:
		var full := mini(_lanes.size(), floori(content_h / LANE_H))
		for i in full:
			_draw_lane_row(i, RULER_H + float(i) * LANE_H, w)
		if full < _lanes.size() and content_h - full * LANE_H > 0.0:
			_draw_lane_band(full, RULER_H + float(full) * LANE_H, content_h - full * LANE_H, w)
		draw_line(Vector2(0, RULER_H), Vector2(w, RULER_H), Color(0.35, 0.37, 0.45, 0.8), 1.0)
	for i in _ruler_ticks.size():
		var x := _ruler_ticks[i]
		draw_line(Vector2(x, RULER_H - 6.0), Vector2(x, RULER_H), Color(0.45, 0.47, 0.55, 0.9), 1.0)
	for label in _ruler_labels:
		draw_string(ThemeDB.fallback_font, Vector2(float(label[0]) - 20.0, 10.0), str(label[1]),
			HORIZONTAL_ALIGNMENT_LEFT, 40, 10, Color(0.75, 0.78, 0.85, 1.0))
	var px := _offset + _playhead * _pps
	if px >= -2.0 and px <= w + 2.0:
		draw_rect(Rect2(px - 0.5, 0, 1.0, h), COL_PLAYHEAD)
		draw_rect(Rect2(px - 4.0, 0, 8.0, 8.0), COL_PLAYHEAD)


func _draw_lane_row(index: int, y: float, w: float) -> void:
	var lane: Dictionary = _lanes[index]
	var kind := int(lane["kind"])
	var bg := Color(0.10, 0.11, 0.15, 1.0) if index % 2 == 0 else Color(0.09, 0.10, 0.13, 1.0)
	if kind == TimelineLaneModel.KIND_FRAMES:
		bg = Color(0.08, 0.09, 0.13, 1.0)
	draw_rect(Rect2(0, y, w, LANE_H), bg)
	if kind == TimelineLaneModel.KIND_FRAMES:
		for i in _frame_boundary_xs.size():
			var bx := _frame_boundary_xs[i]
			if bx >= -2.0 and bx <= w + 2.0:
				draw_line(Vector2(bx, y), Vector2(bx, y + LANE_H), Color(0.20, 0.22, 0.30, 0.9), 1.0)
	draw_rect(Rect2(0, y, GUTTER, LANE_H), Color(0.05, 0.06, 0.09, 0.92))
	draw_line(Vector2(GUTTER - 1.0, y), Vector2(GUTTER - 1.0, y + LANE_H), Color(0.28, 0.30, 0.38, 0.9), 1.0)
	# label first so the selection band tints over it and key ticks (the
	# interactive affordance) always stay crisp on top
	draw_string(ThemeDB.fallback_font, Vector2(8.0, y + 16.0), str(lane["label"]),
		HORIZONTAL_ALIGNMENT_LEFT, GUTTER - 12.0, 11, Color(0.7, 0.73, 0.82, 1.0))
	var span: Dictionary = _selection.get(str(lane["id"]), {})
	if not span.is_empty():
		_draw_band(_offset + float(span["start"]) * _pps, _offset + float(span["end"]) * _pps, y, LANE_H, w)
	if kind != TimelineLaneModel.KIND_FRAMES:
		for key in lane["keys"]:
			var kx := _offset + float(key["time"]) * _pps
			if kx < -2.0 or kx > w + 2.0:
				continue
			draw_rect(Rect2(kx - 1.0, y + (LANE_H - TICK_H) * 0.5, TICK_W, TICK_H),
				_key_color(kind, str(key["property_path"])))


func _draw_lane_band(index: int, y: float, h: float, w: float) -> void:
	if index % 2 == 0:
		draw_rect(Rect2(0, y, w, h), Color(0.09, 0.10, 0.13, 1.0))
	else:
		draw_rect(Rect2(0, y, w, h), Color(0.08, 0.09, 0.12, 1.0))


func _draw_band(sx: float, ex: float, y: float, h: float, w: float) -> void:
	var a := maxf(minf(sx, ex), 0.0)
	var b := minf(maxf(sx, ex), w)
	if b <= a:
		return
	draw_rect(Rect2(a, y, b - a, h), COL_SELECTION)


func _key_color(kind: int, property_path: String) -> Color:
	if kind == TimelineLaneModel.KIND_CAMERA:
		return COL_CAMERA
	if kind == TimelineLaneModel.KIND_LIGHT:
		return COL_LIGHT
	match property_path:
		"position":
			return COL_POSITION
		"rotation":
			return COL_ROTATION
		"scale":
			return COL_SCALE
		"visible":
			return COL_VISIBLE
		_:
			return COL_UNKNOWN_KEY


func _layout_ruler() -> void:
	_ruler_ticks = PackedFloat32Array()
	_ruler_labels.clear()
	_frame_boundary_xs = PackedFloat32Array()
	if _model == null:
		return
	var fps := float(_model.timeline.fps if _model.timeline != null else 12)
	var step := _pps / fps
	if step <= 0.0:
		return
	var w := size.x
	if w <= 0.0:
		return
	var last_label_x := -1e9
	for f in range(maxi(0, floori(-_offset / step) - 1), maxi(0, ceil((w - _offset) / step) + 2)):
		var x := _offset + float(f) * step
		if x < -2.0 or x > w + 2.0:
			continue
		_ruler_ticks.append(x)
		if f % LABEL_EVERY == 0:
			if x - last_label_x >= LABEL_GAP - 0.001:
				_ruler_labels.append([x, _format_time(float(f) / fps)])
				last_label_x = x
	for t in _model.frame_boundaries():
		var bx := _offset + t * _pps
		if bx >= -2.0 and bx <= w + 2.0:
			_frame_boundary_xs.append(bx)


func _format_time(t: float) -> String:
	var s := roundf(t * 100.0) / 100.0
	if absf(s - roundf(s)) < 0.0001:
		return "%ds" % int(s)
	return "%.2fs" % s


# ------------------------------------------------------------- gestures ----

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event as InputEventMouseMotion)
	elif event is InputEventScreenTouch:
		_handle_screen_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_handle_screen_drag(event as InputEventScreenDrag)
	elif event is InputEventKey:
		_handle_key(event as InputEventKey)
	accept_event()


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
		_zoom_at_pointer(event.position.x, ZOOM_STEP)
		return
	if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
		_zoom_at_pointer(event.position.x, 1.0 / ZOOM_STEP)
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.pressed:
		_cancel_pending_press()
		_begin_press(event.position, event.ctrl_pressed)
	else:
		_end_press(event.position)


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if not _press_active:
		return
	_drag_progress(event.position)


func _handle_key(event: InputEventKey) -> void:
	if event.pressed and (event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE):
		delete_selection()


func _handle_screen_touch(event: InputEventScreenTouch) -> void:
	var index := event.index
	if event.pressed:
		_touch_pos[index] = event.position
		if _touch_pos.size() == 1:
			_pending_touch = index
			_begin_press(event.position, false)
		elif _touch_pos.size() == 2:
			# second finger: pinch cancels the pending single-touch tap
			_cancel_pending_press()
			_pinch_indices.clear()
			for other in _touch_pos:
				if int(other) != index:
					_pinch_indices.append(int(other))
					break
			_pinch_indices.append(index)
			# pinch is RELATIVE to the current zoom: no baseline reset - the
			# next qualifying distance change steps x1.5 from the live pps,
			# anchored at the two-finger centroid
			_pinch_dist = _pinch_distance()
		return
	_touch_pos.erase(index)
	if _pinch_indices.has(index):
		_pinch_indices.clear()
		_pending_touch = -1
		return
	if _pending_touch == index:
		_pending_touch = -1
		_end_press(event.position)


func _handle_screen_drag(event: InputEventScreenDrag) -> void:
	var index := event.index
	_touch_pos[index] = event.position
	if _pinch_indices.has(index):
		var d := _pinch_distance()
		if _pinch_dist > 0.0 and d > 0.0:
			# anchor at the pinch centroid: the world time between the two
			# fingers is what must survive every zoom step (brief:19)
			var cx := _pinch_centroid_x()
			if d > _pinch_dist + PINCH_PX:
				_zoom_at_pointer(cx, ZOOM_STEP)
				_pinch_dist = d
			elif d < _pinch_dist - PINCH_PX:
				_zoom_at_pointer(cx, 1.0 / ZOOM_STEP)
				_pinch_dist = d
		return
	if _pending_touch == index:
		_drag_progress(event.position)


func _pinch_distance() -> float:
	if _pinch_indices.size() != 2:
		return 0.0
	return (_touch_pos[_pinch_indices[0]] as Vector2).distance_to(_touch_pos[_pinch_indices[1]] as Vector2)


## Midpoint of the two pinching fingers. Only called while the pinch is active
## (both indices still tracked), which is exactly the size==2 precondition of
## _pinch_distance().
func _pinch_centroid_x() -> float:
	var a := _touch_pos[_pinch_indices[0]] as Vector2
	var b := _touch_pos[_pinch_indices[1]] as Vector2
	return (a.x + b.x) * 0.5


func _time_at(x: float) -> float:
	return (x - _offset) / _pps


func _cancel_pending_press() -> void:
	_press_active = false
	_drag_active = false
	_drag_mode = ""
	_pending_touch = -1


func _begin_press(pos: Vector2, ctrl: bool) -> void:
	# every press path (mouse, touch, marquee start) must grant keyboard focus,
	# else Godot never delivers Delete/Backspace to this control in a live
	# window (FOCUS_CLICK is set on the node in the scene)
	grab_focus()
	_press_active = true
	_press_pos = pos
	_ctrl_down = ctrl
	_drag_active = false
	_drag_mode = ""
	_press_in_ruler = pos.y < RULER_H
	_press_lane_id = ""
	_press_lane_kind = -1
	_press_key_index = -1
	_press_inside_selection = false
	_press_start_time = _time_at(pos.x)
	if _press_in_ruler:
		playhead_requested.emit(snap_time(_press_start_time))
		return
	var row := floori((pos.y - RULER_H) / LANE_H)
	if row < 0 or row >= _lanes.size():
		_press_active = false
		return
	var lane: Dictionary = _lanes[row]
	_press_lane_id = str(lane["id"])
	_press_lane_kind = int(lane["kind"])
	if _press_lane_kind != TimelineLaneModel.KIND_FRAMES and _model != null:
		_press_key_index = _model.key_index_at(_press_lane_id, _press_start_time, KEY_TOLERANCE / _pps)
	var span: Dictionary = _selection.get(_press_lane_id, {})
	if not span.is_empty():
		_press_inside_selection = _press_start_time >= float(span["start"]) and _press_start_time <= float(span["end"])


func _drag_progress(pos: Vector2) -> void:
	if not _press_active:
		return
	if not _drag_active:
		if _press_pos.distance_to(pos) < DRAG_PX:
			_drag_last = pos
			return
		_drag_active = true
		_drag_last = pos
		_drag_snap = _snap  # snapping captured at drag activation (Review-Focus #4)
		if _press_in_ruler:
			_drag_mode = "scrub"
		elif _press_key_index >= 0:
			_drag_mode = "key"
			_key_index = _press_key_index
			_key_from = _keyframes.keyframes[_key_index].time if _keyframes != null else 0.0
		elif _press_inside_selection:
			_drag_mode = "span_dup" if _ctrl_down else "span_slide"
			_span_indices = _selection_indices_for(_press_lane_id)
		else:
			_drag_mode = "marquee"
			_marquee_start = _press_start_time
		return
	_drag_last = pos
	if _drag_mode == "key":
		key_move_requested.emit(_key_index, _key_from, _to_time(pos.x))
	elif _drag_mode == "scrub":
		playhead_requested.emit(snap_time(_time_at(pos.x)))


func _to_time(x: float) -> float:
	var t := _time_at(x)
	if _drag_snap:
		return snap_time(t)
	return t


func _end_press(pos: Vector2) -> void:
	if not _press_active:
		return
	_press_active = false
	if not _drag_active:
		if not _press_in_ruler:
			_handle_lane_tap(pos)
		_reset_gesture()
		return
	match _drag_mode:
		"key":
			key_move_requested.emit(_key_index, _key_from, _to_time(pos.x))
		"marquee":
			var a := minf(_marquee_start, _time_at(pos.x))
			var b := maxf(_marquee_start, _time_at(pos.x))
			# a fresh marquee replaces any prior selection entirely
			_selection.clear()
			_selection[_press_lane_id] = {"start": a, "end": b}
			queue_redraw()
		"span_slide":
			var dx := (_drag_last.x - _press_pos.x) / _pps
			span_slide_requested.emit(_span_indices, dx)
		"span_dup":
			var drop := _time_at(_drag_last.x)
			var span: Dictionary = _selection.get(_press_lane_id, {})
			var offset := drop - float(span.get("start", drop))
			span_duplicate_requested.emit(_span_indices, offset)
		"scrub":
			playhead_requested.emit(snap_time(_time_at(pos.x)))
	_reset_gesture()


func _handle_lane_tap(pos: Vector2) -> void:
	var now := Time.get_ticks_msec()
	var token := "lane:%s" % _press_lane_id
	if _last_tap_token == token and now - _last_tap_time <= DOUBLE_TAP_MS \
			and _press_pos.distance_to(_last_tap_pos) <= DRAG_PX:
		_last_tap_token = ""
		if _press_key_index < 0 and _press_lane_kind != TimelineLaneModel.KIND_FRAMES:
			key_add_requested.emit(_press_lane_id, _press_lane_kind, snap_time(_time_at(pos.x)))
		return
	lane_pressed.emit(_press_lane_id, _press_lane_kind)
	_last_tap_time = now
	_last_tap_token = token
	_last_tap_pos = _press_pos


func _reset_gesture() -> void:
	_press_pos = Vector2.ZERO
	_drag_active = false
	_drag_mode = ""
	_drag_last = Vector2.ZERO
	_key_index = -1
	_span_indices = []


func _selection_indices() -> Array[int]:
	var flat: Array[int] = []
	if _model == null:
		return flat
	var set_keys := {}
	for lane_id in _selection:
		var span: Dictionary = _selection[lane_id]
		for idx in _model.range_keys(str(lane_id), float(span["start"]), float(span["end"])):
			set_keys[idx] = true
	for idx in set_keys:
		flat.append(int(idx))
	flat.sort()
	return flat


func _selection_indices_for(lane_id: String) -> Array[int]:
	var flat: Array[int] = []
	if _model == null:
		return flat
	var span: Dictionary = _selection.get(lane_id, {})
	if span.is_empty():
		return flat
	flat.assign(_model.range_keys(lane_id, float(span["start"]), float(span["end"])))
	return flat