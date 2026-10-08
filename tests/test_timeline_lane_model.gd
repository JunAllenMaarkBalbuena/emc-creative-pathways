extends SceneTree

## TimelineLaneModel test (Task 2, multi-track timeline round): a pure
## RefCounted that derives per-target lanes from the flat keyframe list —
## frames strip, one lane per world layer (stack order, index 0 = back), the
## Camera lane, one lane per light — plus snap_time / frame_boundaries /
## range_keys / key_index_at, and LightingController.light_ids().
##
## Membership: object/light lanes match target_type AND target_id; the Camera
## lane matches TARGET_CAMERA by type only, so keys authored as "cam" (or any
## id) land there (Review-Focus #3) and range_keys/key_index_at resolve them.
## Orphan keys (target never registered) appear in no lane but stay in the
## flat list (Review-Focus #2). snaps clamp to [0, duration]; frame boundaries
## are the fps tempo grid i/fps over the frame channel.

const TimelineLaneModel := preload("res://scripts/animation_production_lab/ui/timeline_lane_model.gd")
const FPS := 12
const DURATION := 5.0
const IDLE_DIR := "res://assets/char_animation/idle"
const BG_PATH := "res://assets/Scene_BG/Menu_Bg_image.png"


func _init() -> void:
	var failures := _run()
	if failures.is_empty():
		print("PASS: timeline lane model — lane order/membership/snap/boundaries/range_keys/key_index_at")
		quit(0)
	else:
		for f in failures:
			print("FAIL: ", f)
		quit(1)


func _run() -> Array[String]:
	var failures: Array[String] = []
	var boot := _bootstrap()
	var world := boot["world"] as WorldController
	var keyframes_ctrl := boot["keyframes"] as KeyframeController
	var frames_ctrl := boot["frames"] as FrameController
	var timeline := boot["timeline"] as TimelineController
	var lighting := boot["lighting"] as LightingController
	var char_id := boot["char_id"] as String
	var bg_id := boot["bg_id"] as String
	var prop_id := boot["prop_id"] as String
	var light_id := boot["light_id"] as String

	var model := TimelineLaneModel.new()
	model.world = world
	model.keyframes = keyframes_ctrl
	model.frames = frames_ctrl
	model.timeline = timeline
	model.lighting = lighting

	# --- lane order: frames, layers back-to-front, camera, lights ----------
	var lanes := model.lanes()
	var ids: Array[String] = []
	for lane in lanes:
		ids.append(str(lane["id"]))
	if ids != ["frames", char_id, bg_id, prop_id, "camera", light_id]:
		failures.append("lane order should be frames, layers back-to-front, camera, lights; got %s" % [ids])
	if _kinds(lanes) != [
		TimelineLaneModel.KIND_FRAMES, TimelineLaneModel.KIND_OBJECT,
		TimelineLaneModel.KIND_OBJECT, TimelineLaneModel.KIND_OBJECT,
		TimelineLaneModel.KIND_CAMERA, TimelineLaneModel.KIND_LIGHT,
	]:
		failures.append("lane kinds should follow the spec int consts")
	if str(lanes[0]["label"]) != "Frames" or str(lanes[4]["label"]) != "Camera" or str(lanes[5]["label"]) != light_id:
		failures.append("frames/camera/light lane labels are wrong")
	if str(lanes[1]["label"]) != "char_starter" or str(lanes[2]["label"]) != "bg_starter" or str(lanes[3]["label"]) != "prop_box":
		failures.append("object lane labels should be the display_name")

	# --- lane shape: id/kind/label/keys (+ locked for objects) --------------
	for lane in lanes:
		var d := lane as Dictionary
		if not d.has_all(["id", "kind", "label", "keys"]):
			failures.append("every lane needs id/kind/label/keys: %s" % [d])
		if not (d["keys"] is Array):
			failures.append("lane keys must be an Array")
	for i in [1, 2, 3]:
		if not lanes[i].has("locked"):
			failures.append("object lanes must carry locked")
		if lanes[i]["locked"] != false:
			failures.append("object lanes default to locked=false")
	var frame_keys: Array = lanes[0]["keys"]
	if frame_keys.size() != 0:
		failures.append("the frames strip lane has no keys (frames are a separate channel)")

	# --- object lane keys: sorted by time, per-key entry shape --------------
	var char_lane := _lane(lanes, char_id)
	if char_lane.is_empty():
		failures.append("char lane is missing")
	else:
		var char_times: Array[float] = []
		for e in char_lane["keys"]:
			var entry := e as Dictionary
			if not entry.has_all(["target_id", "property_path", "time", "interpolation"]):
				failures.append("lane key entry is missing a field: %s" % [entry])
			char_times.append(float(entry["time"]))
		if char_times != [0.0, 0.25, 0.75]:
			failures.append("object lane keys should be time-sorted, got %s" % [char_times])
		if int(char_lane["keys"][1]["interpolation"]) != KeyframeController.STEP:
			failures.append("lane key interpolation should pass through (the 0.25 char key is STEP)")

	# --- camera lane collects camera keys by type only (Review-Focus #3) ----
	var cam_lane := _lane(lanes, "camera")
	var cam_ids: Array[String] = []
	for e in cam_lane["keys"]:
		cam_ids.append(str(e["target_id"]))
	if cam_ids != ["cam", "cam", "camera_alt"]:
		failures.append("camera lane should collect every TARGET_CAMERA key regardless of authored id, got %s" % [cam_ids])

	# --- light lane keys ------------------------------------------------------
	var light_lane := _lane(lanes, light_id)
	if light_lane.is_empty():
		failures.append("light lane is missing")
	else:
		var light_times: Array[float] = []
		for e in light_lane["keys"]:
			light_times.append(float(e["time"]))
		if light_times != [0.3, 1.0]:
			failures.append("light lane keys should be time-sorted, got %s" % [light_times])

	# --- orphans: in the flat list, in no lane (Review-Focus #2) --------------
	if keyframes_ctrl.keyframes.size() != 12:
		failures.append("flat keyframe list should keep all 12 seeded keys, got %d" % keyframes_ctrl.keyframes.size())
	if keyframes_ctrl.keyframes_for("ghost").size() != 1:
		failures.append("the orphan key must stay in the flat list")
	var lane_count := 0
	for lane in lanes:
		lane_count += (lane["keys"] as Array).size()
	if lane_count != 8:
		failures.append("lanes should hold 8 keys total (3 char + 3 camera + 2 light); orphan/target-gone keys are excluded, got %d" % lane_count)
	if not _lane(lanes, "ghost").is_empty():
		failures.append("no lane should exist for an unregistered target id")

	# --- membership is type AND id (id alone is not enough) -------------------
	if model.range_keys(light_id, 0.55, 0.85) != []:
		failures.append("light lane range must exclude the object-typed key with a light id and the unregistered light id")

	# --- range_keys -> flat indices ------------------------------------------
	if model.range_keys("camera", 0.4, 1.6) != [
		_flat(keyframes_ctrl, 0.5, "cam", "fov"),
		_flat(keyframes_ctrl, 1.5, "cam", "fov"),
	]:
		failures.append("range_keys on the camera lane should resolve camera keys to flat indices")
	if model.range_keys(light_id, 0.3, 1.0) != [
		_flat(keyframes_ctrl, 0.3, light_id, "light_energy"),
		_flat(keyframes_ctrl, 1.0, light_id, "light_energy"),
	]:
		failures.append("range_keys on the light lane should include both endpoints")
	if model.range_keys(char_id, 0.0, 0.25) != [
		_flat(keyframes_ctrl, 0.0, char_id, "position"),
		_flat(keyframes_ctrl, 0.25, char_id, "position"),
	]:
		failures.append("range_keys should include the inclusive start/end bounds")
	if model.range_keys("frames", 0.0, DURATION) != []:
		failures.append("range_keys on the frames lane is always empty")
	if model.range_keys("ghost", 0.0, DURATION) != []:
		failures.append("range_keys for an unknown lane id is empty")

	# --- key_index_at: nearest within tolerance, else -1 ----------------------
	if model.key_index_at("camera", 0.5, 0.01) != _flat(keyframes_ctrl, 0.5, "cam", "fov"):
		failures.append("key_index_at must resolve the \"cam\"-authored camera key (Review-Focus #3)")
	if model.key_index_at("camera", 1.52, 0.1) != _flat(keyframes_ctrl, 1.5, "cam", "fov"):
		failures.append("key_index_at should pick the nearest key within tolerance")
	if model.key_index_at("camera", 1.0, 0.05) != -1:
		failures.append("key_index_at returns -1 when no key is within tolerance")
	if model.key_index_at(char_id, 0.25, 0.01) != _flat(keyframes_ctrl, 0.25, char_id, "position"):
		failures.append("key_index_at should resolve object lane keys")
	if model.key_index_at(char_id, 0.5, 0.05) != -1:
		failures.append("key_index_at on the char lane must not see other lanes' keys")
	if model.key_index_at(light_id, 0.3, 0.01) != _flat(keyframes_ctrl, 0.3, light_id, "light_energy"):
		failures.append("key_index_at should resolve light lane keys")
	if model.key_index_at("frames", 0.5, 1.0) != -1:
		failures.append("the frames lane has no keys to resolve")

	# --- reordering the world re-orders the object lanes on the next call ------
	if not world.move_layer_up(bg_id):
		failures.append("move_layer_up(bg) should succeed")
	lanes = model.lanes()
	ids = []
	for lane in lanes:
		ids.append(str(lane["id"]))
	if ids != ["frames", char_id, prop_id, bg_id, "camera", light_id]:
		failures.append("object lanes should follow the reordered layer stack, got %s" % [ids])

	# --- snap_time clamps and rounds to the fps grid ----------------------------
	if absf(model.snap_time(0.37) - 4.0 / 12.0) > 0.000001:
		failures.append("snap_time(0.37) at fps 12 should snap to 4/12 = 0.333..., got %s" % model.snap_time(0.37))
	if model.snap_time(-1.0) != 0.0:
		failures.append("snap_time clamps below 0 to 0")
	if model.snap_time(99.0) != DURATION:
		failures.append("snap_time clamps above the timeline duration")
	if absf(model.snap_time(0.4) - 5.0 / 12.0) > 0.000001:
		failures.append("snap_time(0.4) should round up to 5/12")

	# --- frame_boundaries = the fps tempo grid over the frame channel ------------
	var boundaries := model.frame_boundaries()
	var expected: Array[float] = []
	for i in frames_ctrl.frames.size():
		expected.append(float(i) / float(FPS))
	if boundaries != expected:
		failures.append("frame_boundaries should be [i/fps for each frame], got %s expected %s" % [boundaries, expected])

	# --- LightingController.light_ids() is registration order --------------------
	if lighting.light_ids() != [light_id]:
		failures.append("light_ids() should list registered lights in order, got %s" % [lighting.light_ids()])

	return failures


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
	var char_asset := _asset("char_starter", "character", "sprite", "starter", IDLE_DIR + "/" + idle_file)
	var bg_asset := _asset("bg_starter", "background", "sprite", "starter", BG_PATH)
	var box_asset := _asset("prop_box", "prop", "primitive", "starter", "", {"shape": "box"})
	var char_id := wc.add_asset(char_asset, Vector3(0, 0.5, 0))
	var bg_id := wc.add_asset(bg_asset, Vector3(0, 1, -6))
	var prop_id := wc.add_asset(box_asset, Vector3(1.2, 0.45, 0))

	var light_root := Node3D.new()
	light_root.name = "LightingRoot"
	var lc := LightingController.new()
	light_root.add_child(lc)
	lc.lighting_root = NodePath("../LightingRoot")
	var light := DirectionalLight3D.new()
	light_root.add_child(light)
	var light_id := "light_1"
	if not lc.register_existing(light_id, light):
		return {}  # impossible on a bare controller

	var frames_ctrl := FrameController.new()
	frames_ctrl.add_frame()
	frames_ctrl.add_frame()
	frames_ctrl.add_frame()

	var timeline := TimelineController.new()
	timeline.fps = FPS
	timeline.duration = DURATION

	var keyframes_ctrl := KeyframeController.new()
	keyframes_ctrl.add_keyframe(0.0, char_id, KeyframeController.TARGET_OBJECT, "position", Vector3(0, 0, 0))
	keyframes_ctrl.add_keyframe(0.25, char_id, KeyframeController.TARGET_OBJECT, "position", Vector3(2, 0, 0), KeyframeController.STEP)
	keyframes_ctrl.add_keyframe(0.3, light_id, KeyframeController.TARGET_LIGHT, "light_energy", 1.0)
	keyframes_ctrl.add_keyframe(0.5, "cam", KeyframeController.TARGET_CAMERA, "fov", 45.0)
	keyframes_ctrl.add_keyframe(0.55, "ghost", KeyframeController.TARGET_OBJECT, "position", Vector3(0, 0, 0))
	keyframes_ctrl.add_keyframe(0.6, light_id, KeyframeController.TARGET_OBJECT, "position", Vector3(0, 0, 0))
	keyframes_ctrl.add_keyframe(0.65, char_id, KeyframeController.TARGET_LIGHT, "fov", 9.0)
	keyframes_ctrl.add_keyframe(0.7, "light_ghost", KeyframeController.TARGET_LIGHT, "light_energy", 2.0)
	keyframes_ctrl.add_keyframe(0.75, char_id, KeyframeController.TARGET_OBJECT, "position", Vector3(1, 0, 0))
	keyframes_ctrl.add_keyframe(1.0, light_id, KeyframeController.TARGET_LIGHT, "light_energy", 1.5)
	keyframes_ctrl.add_keyframe(1.5, "cam", KeyframeController.TARGET_CAMERA, "fov", 55.0)
	keyframes_ctrl.add_keyframe(2.0, "camera_alt", KeyframeController.TARGET_CAMERA, "fov", 60.0)

	return {
		"world": wc,
		"keyframes": keyframes_ctrl,
		"frames": frames_ctrl,
		"timeline": timeline,
		"lighting": lc,
		"char_id": char_id,
		"bg_id": bg_id,
		"prop_id": prop_id,
		"light_id": light_id,
	}


func _kinds(lanes: Array) -> Array[int]:
	var out: Array[int] = []
	for lane in lanes:
		out.append(int(lane["kind"]))
	return out


## Lane dict for an id, or {} when no such lane exists.
func _lane(lanes: Array, lane_id: String) -> Dictionary:
	for lane in lanes:
		if str(lane["id"]) == lane_id:
			return lane as Dictionary
	return {}


## Flat-list index of the seeded key (time, target_id, property_path).
func _flat(ctrl: KeyframeController, time: float, target_id: String, property_path: String) -> int:
	for i in ctrl.keyframes.size():
		var kf := ctrl.keyframes[i] as AnimationKeyframeData
		if kf.time == time and kf.target_id == target_id and kf.property_path == property_path:
			return i
	return -1


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