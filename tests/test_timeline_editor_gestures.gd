extends Node

## TimelineEditor gesture + canvas test (Task 3, multi-track timeline round):
## mounts the TimelinePanel docker alone, binds bare controllers bootstrapped
## like Task 2 (2 objects, camera key authored "cam", 1 light, 2 frames,
## timeline fps 12 / duration 5), sets the editor rect explicitly, then
## synthesizes _gui_input events (mouse button/motion/wheel/key + screen
## touch/drag) and asserts the §5 signals with resolved indices and snapped
## times. Also covers the Review-Focus items: camera-lane key authorship in
## the span path (#3), snap captured at drag start (#4), zoom bounds + t=0
## offset (#5), lane clipping inside the editor rect (#1), and the §7
## playhead-only redraw vs keyframes-changed rebuild split (Ruling 2:
## a refresh() call counter is exposed instead of lane object identity —
## model.lanes() returns fresh Dictionaries every call).

const TimelineLaneModel := preload("res://scripts/animation_production_lab/ui/timeline_lane_model.gd")
const TimelinePanel := preload("res://scripts/animation_production_lab/ui/timeline_panel.gd")
const TimelineEditor := preload("res://scripts/animation_production_lab/ui/timeline_editor.gd")
const PANEL_SCENE := "res://scenes/animation_production_lab/ui/timeline_panel.tscn"
const RULER_H := 32.0
const LANE_H := 24.0
const GUTTER := 96.0
const FPS := 12
const DURATION := 5.0
const IDLE_DIR := "res://assets/char_animation/idle"
const BG_PATH := "res://assets/Scene_BG/Menu_Bg_image.png"
const EPSILON := 1.0

var world: WorldController
var keyframes_ctrl: KeyframeController
var frames_ctrl: FrameController
var timeline: TimelineController
var lighting: LightingController
var panel: Control
var editor: TimelineEditor
var bg_id := ""
var char_id := ""
var light_id := ""

# received signal payloads (cleared between groups)
var lane_pressed: Array = []
var playhead_requested: Array = []
var key_add_requested: Array = []
var key_move_requested: Array = []
var keys_remove_requested: Array = []
var span_slide_requested: Array = []
var span_duplicate_requested: Array = []
var snap_toggled: Array = []
var failures: Array[String] = []


func _ready() -> void:
	var tree := get_tree()
	var failed := await _run()
	if failed.is_empty():
		print("PASS: timeline editor gestures - canvas + touch/mouse + zoom + snap + playback redraw")
		tree.quit(0)
	else:
		for f in failed:
			print("FAIL: ", f)
		tree.quit(1)


func _run() -> Array[String]:
	var boot := _bootstrap()
	if boot.is_empty():
		failures.append("bootstrap failed (no idle sprite?)")
		return failures
	world = boot["world"] as WorldController
	keyframes_ctrl = boot["keyframes"] as KeyframeController
	frames_ctrl = boot["frames"] as FrameController
	timeline = boot["timeline"] as TimelineController
	lighting = boot["lighting"] as LightingController
	char_id = boot["char_id"] as String
	bg_id = boot["bg_id"] as String
	light_id = boot["light_id"] as String

	panel = load(PANEL_SCENE).instantiate() as Control
	add_child(panel)
	await get_tree().process_frame

	# Scene drill: the panel must host the editor + toolbar (Step 2 RED: missing)
	editor = panel.get_node_or_null("%TimelineEditor") as TimelineEditor
	if editor == null:
		failures.append("TimelineEditor is missing from TimelinePanel")
		return failures
	var snap_toggle := panel.get_node_or_null("%SnapToggle") as CheckButton
	var zoom_in_btn := panel.get_node_or_null("%ZoomIn") as Button
	var zoom_out_btn := panel.get_node_or_null("%ZoomOut") as Button
	var delete_btn := panel.get_node_or_null("%DeleteSelection") as Button
	if snap_toggle == null or zoom_in_btn == null or zoom_out_btn == null or delete_btn == null:
		failures.append("toolbar nodes are missing from TimelinePanel")

	_connect_received()
	editor.size = Vector2(800, 220)
	(panel as TimelinePanel).bind(world, keyframes_ctrl, frames_ctrl, timeline, lighting)
	await get_tree().process_frame

	if editor.get_pps() != 96.0:
		failures.append("default pps must be 96, got %s" % editor.get_pps())
	if not editor.get_snap():
		failures.append("snap must default to on")

	# --- Group A: taps, ruler scrub, double-tap add, empty delete ------------
	# delete with no selection emits nothing (Review-Focus #1b)
	editor.call("delete_selection")
	if not keys_remove_requested.is_empty():
		failures.append("delete_selection with no selection must not emit")

	_tap(Vector2(150, _row_y(2)))  # bg lane row, x clear of any key
	if not _has(lane_pressed, [bg_id, TimelineLaneModel.KIND_OBJECT]):
		failures.append("tap on a lane row should emit lane_pressed(bg, KIND_OBJECT); got %s" % [lane_pressed])

	_reset_received()
	_tap(Vector2(48, _row_y(2)))  # bg lane is empty at x=48 (time 0.5)
	_tap(Vector2(48, _row_y(2)))  # second tap within the double-tap window
	if not _has(key_add_requested, [bg_id, TimelineLaneModel.KIND_OBJECT, 0.5]):
		failures.append("double-tap on an empty lane should emit key_add_requested(bg, KIND_OBJECT, 0.5); got %s" % [key_add_requested])

	_reset_received()
	_press(Vector2(GUTTER, 16.0))
	if not _has(playhead_requested, 1.0):
		failures.append("tap the ruler at x=96 should emit playhead_requested(1.0); got %s" % [playhead_requested])

	# --- Group B: key drag (snap on), key drag (snap off), Review-Focus #4 ---
	_reset_received()
	# char lane key at t=0.5 sits at x=48 (pps 96, offset 0): flat index 1
	_drag(Vector2(48, _row_y(1)), Vector2(96, _row_y(1)))
	if not _has(key_move_requested, [1, 0.5, 1.0]):
		failures.append("key drag with snap on should emit key_move_requested(1, 0.5, 1.0); got %s" % [key_move_requested])

	_reset_received()
	editor.set_snap(false)
	_drag(Vector2(48, _row_y(1)), Vector2(90, _row_y(1)))
	var raw := _last_of(key_move_requested)
	if raw.size() != 3 or raw[0] != 1 or not _approx(raw[2], 90.0 / 96.0):
		failures.append("key drag with snap off should carry the raw pointer time 0.9375; got %s" % [raw])

	_reset_received()
	editor.set_snap(true)
	_press(Vector2(48, _row_y(1)))          # drag starts with snap ON
	_motion(Vector2(78, _row_y(1)))         # crosses the 8px threshold -> key drag
	editor.set_snap(false)                  # toggled mid-drag
	_motion(Vector2(90, _row_y(1)))
	_release(Vector2(90, _row_y(1)))        # emitted `to` still snapped
	var rf4 := _last_of(key_move_requested)
	if rf4.size() != 3 or rf4[0] != 1 or not _approx(rf4[2], 11.0 / 12.0):
		failures.append("snap state must be captured at drag start (to still snapped 11/12); got %s" % [rf4])
	if editor.get_snap():
		failures.append("set_snap(false) mid-drag should stick")

	# --- Group C: camera marquee + slide (Review-Focus #3) + toolbar delete --
	_reset_received()
	_drag(Vector2(0, _row_y(3)), Vector2(192, _row_y(3)))   # marquee camera 0.0..2.0
	_drag(Vector2(GUTTER, _row_y(3)), Vector2(192, _row_y(3)))  # drag inside selection
	var slide := _last_of(span_slide_requested)
	if slide.size() != 2 or slide[0] != [2, 4] or not _approx(slide[1], 1.0):
		failures.append("span slide should carry range_keys(camera, 0, 2) = [2, 4] incl. the 'cam' key, dx 1.0; got %s" % [slide])
	var expected_range := _range_keys("camera", 0.0, 2.0)
	if slide.size() == 2 and slide[0] != expected_range:
		failures.append("slide indices must match range_keys for the band; expected %s got %s" % [expected_range, slide[0]])

	# toolbar Delete button with an active selection -> keys_remove_requested
	_reset_received()
	var delete_btn2 := panel.get_node("%DeleteSelection") as Button
	delete_btn2.emit_signal("pressed")
	if not _has(keys_remove_requested, [2, 4]):
		failures.append("toolbar Delete should emit keys_remove_requested([2, 4]); got %s" % [keys_remove_requested])

	# Delete KEY with a selection -> keys_remove_requested
	_reset_received()
	_drag(Vector2(0, _row_y(3)), Vector2(192, _row_y(3)))   # re-marquee camera
	_key(KEY_DELETE)
	if not _has(keys_remove_requested, [2, 4]):
		failures.append("Delete key should emit keys_remove_requested([2, 4]); got %s" % [keys_remove_requested])

	# --- Group D: 8px tap-vs-drag threshold --------------------------------
	_reset_received()
	_tap(Vector2(48, _row_y(2)))
	var taps_before := lane_pressed.size()
	_press(Vector2(48, _row_y(2)))
	_motion(Vector2(70, _row_y(2)))   # 22px move -> drag, not tap
	_release(Vector2(70, _row_y(2)))
	if lane_pressed.size() != taps_before:
		failures.append("a >8px move must become a drag, not a second tap")
	# the marquee over the empty bg lane yields no keys: Delete stays silent
	_key(KEY_DELETE)
	if not keys_remove_requested.is_empty():
		failures.append("Delete over a keyless selection must not emit; got %s" % [keys_remove_requested])

	# --- Group E: wheel zoom bounds + t=0 offset (Review-Focus #5) ----------
	_reset_received()
	var pps_before := editor.get_pps()
	for i in 6:
		_wheel_up(Vector2(200, 16))
		# growth only applies below the cap: once pps reaches 240 the clamp
		# holds it there (the never-exceed + final-clamp asserts verify it)
		if editor.get_pps() < 240.0 and editor.get_pps() <= pps_before:
			failures.append("wheel-up must grow pps")
		if editor.get_pps() > 240.000001:
			failures.append("pps must never exceed 240")
		pps_before = editor.get_pps()
	if not _approx(editor.get_pps(), 240.0):
		failures.append("repeated wheel-up should clamp pps at 240, got %s" % editor.get_pps())
	var offset_at_240 := editor.get_draw_offset()
	editor.call("zoom_in")   # already at max: must not move
	if not _approx(editor.get_pps(), 240.0) or not _approx(editor.get_draw_offset(), offset_at_240):
		failures.append("zoom_in at 240 must not change pps or the draw offset")
	for i in 12:
		var before_offset := editor.get_draw_offset()
		_wheel_down(Vector2(200, 16))
		if editor.get_draw_offset() > 0.000001:
			failures.append("t=0 draw offset must never exceed 0: %s" % editor.get_draw_offset())
		if editor.get_draw_offset() < before_offset and editor.get_pps() >= 24.0:
			failures.append("zoom-out must keep the t=0 offset monotone; %s -> %s" % [before_offset, editor.get_draw_offset()])
	if not _approx(editor.get_pps(), 24.0):
		failures.append("repeated wheel-down should clamp pps at 24, got %s" % editor.get_pps())

	# pinch zoom (two-finger): distance growth zooms in, shrink zooms out
	var t_start := [Vector2(100, _row_y(1)), Vector2(200, _row_y(1))]
	_reset_received()
	_touch(0, t_start[0], true)
	_touch(1, t_start[1], true)            # second finger -> pinch cancels the tap
	_drag_touch(0, Vector2(80, _row_y(1)))   # distance 100 -> 120
	if not _approx(editor.get_pps(), 144.0):
		failures.append("pinch grow should zoom in to pps 144, got %s" % editor.get_pps())
	_drag_touch(1, Vector2(230, _row_y(1)))  # 120 -> 150
	if not _approx(editor.get_pps(), 216.0):
		failures.append("second pinch grow should zoom in to 216, got %s" % editor.get_pps())
	_drag_touch(0, Vector2(60, _row_y(1)))   # 150 -> 170 -> clamps at 240
	if not _approx(editor.get_pps(), 240.0):
		failures.append("pinch grow must clamp at 240, got %s" % editor.get_pps())
	_drag_touch(1, Vector2(200, _row_y(1)))  # 170 -> 140 -> out
	if not _approx(editor.get_pps(), 160.0):
		failures.append("pinch shrink should zoom out to 160, got %s" % editor.get_pps())
	if not lane_pressed.is_empty():
		failures.append("pinch must cancel the single-touch tap")
	_touch(0, Vector2(60, _row_y(1)), false)
	_touch(1, Vector2(200, _row_y(1)), false)

	# touch tap lands on the ruler -> playhead_requested; the pinch left the
	# view zoomed, so target the screen x of exactly t=1.0s via the zoom hooks
	_reset_received()
	var st := InputEventScreenTouch.new()
	st.index = 3
	st.position = Vector2(editor.get_draw_offset() + editor.get_pps() * 1.0, 16.0)
	st.pressed = true
	editor.call("_gui_input", st)
	if not _has(playhead_requested, 1.0):
		failures.append("touch tap on the ruler should emit playhead_requested(1.0); got %s" % [playhead_requested])

	# --- Group F: playback redraw (spec §7) + rebuild split ------------------
	_reset_received()
	var rc := editor.get_refresh_count()
	timeline.time_changed.emit(3.0)
	if not _approx(editor.get_playhead_time(), 3.0):
		failures.append("time_changed must move the playhead to 3.0, got %s" % editor.get_playhead_time())
	if editor.get_refresh_count() != rc:
		failures.append("time_changed must redraw the playhead only, never rebuild lanes")
	keyframes_ctrl.keyframes_changed.emit()
	if editor.get_refresh_count() != rc + 1:
		failures.append("keyframes_changed must rebuild lanes (+1 refresh)")

	# --- Group G: Review-Focus #1 (many layers clip inside the editor) -------
	_reset_received()
	editor.size = Vector2(800, 220)
	await get_tree().process_frame
	var rect_before := editor.get_global_rect()
	for i in 8:
		_register_object("obj_extra_%d" % i)
	(panel as TimelinePanel).bind(world, keyframes_ctrl, frames_ctrl, timeline, lighting)
	if editor.get_global_rect() != rect_before:
		failures.append("the editor rect must be unchanged by more lanes")
	var model := TimelineLaneModel.new()
	model.world = world
	model.keyframes = keyframes_ctrl
	model.frames = frames_ctrl
	model.timeline = timeline
	model.lighting = lighting
	if model.lanes().size() < 10:
		failures.append("lanes() must grow past 10 lanes with 10 objects, got %d" % model.lanes().size())
	# viewport containment at the docker's natural size
	editor.size = Vector2(800, 140)
	await get_tree().process_frame
	var vp: Rect2 = get_viewport().get_visible_rect()
	for child in _controls(panel):
		if not _inside(child.get_global_rect(), vp):
			failures.append("%s escapes the viewport: %s vs %s" % [child.name, child.get_global_rect(), vp])
	# _draw never throws for an editor shorter than the lane stack
	editor.size = Vector2(800, 100)
	editor.call("_draw")
	if not editor.get_global_rect().size.x > 0:
		failures.append("editor rect must stay valid after the short _draw")

	return failures


# ---------------------------------------------------------------- gestures ---

func _press(pos: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = pos
	editor.call("_gui_input", e)


func _release(pos: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = false
	e.position = pos
	editor.call("_gui_input", e)


func _motion(pos: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	editor.call("_gui_input", e)


func _tap(pos: Vector2) -> void:
	_press(pos)
	_release(pos)


func _drag(from: Vector2, to: Vector2) -> void:
	_press(from)
	_motion(to)
	_release(to)


func _wheel_up(pos: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_WHEEL_UP
	e.pressed = true
	e.position = pos
	editor.call("_gui_input", e)


func _wheel_down(pos: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_WHEEL_DOWN
	e.pressed = true
	e.position = pos
	editor.call("_gui_input", e)


func _key(keycode: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = keycode
	e.pressed = true
	editor.call("_gui_input", e)


func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = pos
	e.pressed = pressed
	editor.call("_gui_input", e)


func _drag_touch(index: int, pos: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = pos
	editor.call("_gui_input", e)


# ---------------------------------------------------------------- received ---

func _connect_received() -> void:
	panel.lane_pressed.connect(func(id: String, kind: int) -> void: lane_pressed.append([id, kind]))
	panel.playhead_requested.connect(func(t: float) -> void: playhead_requested.append(t))
	panel.key_add_requested.connect(func(id: String, kind: int, t: float) -> void: key_add_requested.append([id, kind, t]))
	panel.key_move_requested.connect(func(idx: int, f: float, t: float) -> void: key_move_requested.append([idx, f, t]))
	panel.keys_remove_requested.connect(func(idxs: Array[int]) -> void: keys_remove_requested.append(idxs.duplicate()))
	panel.span_slide_requested.connect(func(idxs: Array[int], d: float) -> void: span_slide_requested.append([idxs.duplicate(), d]))
	panel.span_duplicate_requested.connect(func(idxs: Array[int], off: float) -> void: span_duplicate_requested.append([idxs.duplicate(), off]))
	panel.snap_toggled.connect(func(on: bool) -> void: snap_toggled.append(on))


func _reset_received() -> void:
	lane_pressed.clear()
	playhead_requested.clear()
	key_add_requested.clear()
	key_move_requested.clear()
	keys_remove_requested.clear()
	span_slide_requested.clear()
	span_duplicate_requested.clear()
	snap_toggled.clear()


func _last_of(arr: Array) -> Array:
	if arr.is_empty():
		return []
	return arr[arr.size() - 1] as Array


func _has(arr: Array, payload: Variant) -> bool:
	for item in arr:
		if item == payload:
			return true
	return false


func _approx(a: float, b: float) -> bool:
	return absf(a - b) < 0.0001


func _row_y(row: int) -> float:
	return RULER_H + float(row) * LANE_H


# ---------------------------------------------------------------- helpers ---

func _inside(rect: Rect2, bounds: Rect2) -> bool:
	return rect.position.x >= bounds.position.x - EPSILON \
		and rect.position.y >= bounds.position.y - EPSILON \
		and rect.end.x <= bounds.end.x + EPSILON \
		and rect.end.y <= bounds.end.y + EPSILON


func _controls(node: Node) -> Array:
	var out: Array = []
	if node is Control:
		out.append(node)
	for c in node.get_children():
		out.append_array(_controls(c))
	return out


func _range_keys(lane_id: String, start: float, end: float) -> Array:
	var model := TimelineLaneModel.new()
	model.world = world
	model.keyframes = keyframes_ctrl
	model.frames = frames_ctrl
	model.timeline = timeline
	model.lighting = lighting
	return model.range_keys(lane_id, start, end)


func _register_object(id: String) -> void:
	var a := _asset(id, "prop", "primitive", "starter", "", {"shape": "box"})
	world.add_asset(a, Vector3(0, 0.5, 0))


func _bootstrap() -> Dictionary:
	var world_root := Node3D.new()
	var char_root := Node3D.new()
	char_root.name = "CharacterRoot"
	var bg_root := Node3D.new()
	bg_root.name = "BackgroundRoot"
	var prop_root := Node3D.new()
	prop_root.name = "PropRoot"
	world_root.add_child(char_root)
	world_root.add_child(bg_root)
	world_root.add_child(prop_root)
	var wc := WorldController.new()
	world_root.add_child(wc)
	wc.character_root = NodePath("../CharacterRoot")
	wc.background_root = NodePath("../BackgroundRoot")
	wc.prop_root = NodePath("../PropRoot")

	var idle_file := _first_idle_png()
	if idle_file.is_empty():
		return {}
	var char_asset := _asset("char_starter", "character", "sprite", "starter", IDLE_DIR + "/" + idle_file)
	var bg_asset := _asset("bg_starter", "background", "sprite", "starter", BG_PATH)
	var char_id := wc.add_asset(char_asset, Vector3(0, 0.5, 0))
	var bg_id := wc.add_asset(bg_asset, Vector3(0, 1, -6))

	var light_root := Node3D.new()
	light_root.name = "LightingRoot"
	var lc := LightingController.new()
	light_root.add_child(lc)
	lc.lighting_root = NodePath("../LightingRoot")
	var light := DirectionalLight3D.new()
	light_root.add_child(light)
	var light_id := "light_1"
	if not lc.register_existing(light_id, light):
		return {}

	var frames_ctrl := FrameController.new()
	frames_ctrl.add_frame()
	frames_ctrl.add_frame()

	var timeline := TimelineController.new()
	timeline.fps = FPS
	timeline.duration = DURATION

	var keyframes_ctrl := KeyframeController.new()
	keyframes_ctrl.add_keyframe(0.0, char_id, KeyframeController.TARGET_OBJECT, "position", Vector3(0, 0, 0))
	keyframes_ctrl.add_keyframe(0.5, char_id, KeyframeController.TARGET_OBJECT, "position", Vector3(2, 0, 0))
	keyframes_ctrl.add_keyframe(0.5, "cam", KeyframeController.TARGET_CAMERA, "fov", 45.0)
	keyframes_ctrl.add_keyframe(1.0, light_id, KeyframeController.TARGET_LIGHT, "light_energy", 1.0)
	keyframes_ctrl.add_keyframe(1.5, "cam", KeyframeController.TARGET_CAMERA, "fov", 55.0)

	return {
		"world": wc,
		"keyframes": keyframes_ctrl,
		"frames": frames_ctrl,
		"timeline": timeline,
		"lighting": lc,
		"char_id": char_id,
		"bg_id": bg_id,
		"light_id": light_id,
	}


func _asset(id: String, category: String, type: String, source: String, path: String, metadata: Dictionary = {}) -> EMCAssetData:
	var a := EMCAssetData.new()
	a.asset_id = id
	a.display_name = id
	a.category = category
	a.asset_type = type
	a.source_lab = source
	a.path = path
	a.metadata = metadata
	return a


func _first_idle_png() -> String:
	var dir := DirAccess.open(IDLE_DIR)
	if dir == null:
		return ""
	var names: Array[String] = []
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.ends_with(".png"):
			names.append(name)
		name = dir.get_next()
	dir.list_dir_end()
	names.sort()
	return names[0] if names.size() > 0 else ""