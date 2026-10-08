extends RefCounted

## Pure per-target lane derivation for the multi-track timeline editor (Task 2).
## Consumes live controller state through plain injectable properties (set by
## the root or a test) and re-derives everything on every call — no signals,
## no nodes, no cached state of its own. KeyframeController.keyframes stays the
## flat, time-sorted source of truth; lanes() groups a copy of it per target.
##
## Lane kinds (single source of truth — the editor's signals and the root's
## handlers match on these ints):
##   KIND_FRAMES - the frame strip lane (no keys: frames are a separate channel)
##   KIND_OBJECT - one lane per world layer, in layer_order() stack order
##   KIND_CAMERA - one lane; collects TARGET_CAMERA keys by type only, because
##                 authored target_ids vary ("cam") and playback ignores them
##   KIND_LIGHT  - one lane per lighting.light_ids() entry (registration order)
##
## Membership: object/light lanes match target_type AND target_id; the camera
## lane matches TARGET_CAMERA by type alone. Orphan keys (target never
## registered) are excluded from every lane but stay in the flat list. The
## flat list is time-sorted, so every lane's keys come out time-sorted too.

const KIND_FRAMES := 0
const KIND_OBJECT := 1
const KIND_CAMERA := 2
const KIND_LIGHT := 3

## Injectable input refs (test/root set these; see PreviewController.timeline
## for the same injection convention).
var world: WorldController
var keyframes: KeyframeController
var frames: FrameController
var timeline: TimelineController
var lighting: LightingController


## Ordered lanes: [frames strip, one per world.layer_order() back-to-front,
## Camera, one per lighting.light_ids()]. Each lane is {id, kind, label, keys}
## with object lanes also carrying locked; keys are one {target_id,
## property_path, time, interpolation} entry per flat key of that lane, sorted
## by time. Orphan keys (target not registered) route to no lane.
func lanes() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var lane_index: Dictionary = {}  # lane id -> position in result
	result.append(_frames_lane())
	lane_index["frames"] = 0
	if world != null:
		for object_id in world.layer_order():
			lane_index[object_id] = result.size()
			result.append(_object_lane(object_id))
	lane_index["camera"] = result.size()
	result.append(_camera_lane())
	if lighting != null:
		for light_id in lighting.light_ids():
			lane_index[light_id] = result.size()
			result.append(_light_lane(light_id))
	if keyframes != null:
		for kf in keyframes.keyframes:
			var lane_id := _lane_for_key(kf)
			if lane_id != "" and lane_index.has(lane_id):
				var pos: int = lane_index[lane_id]
				(result[pos]["keys"] as Array).append(_key_entry(kf))
	return result


## Nearest frame boundary, clamped to [0, duration]. fps/duration read from
## TimelineController; the fallbacks are that controller's own defaults.
func snap_time(time: float) -> float:
	var fps := timeline.fps if timeline != null else 12
	var duration := timeline.duration if timeline != null else 5.0
	return clampf(roundf(time * fps) / fps, 0.0, duration)


## The frame channel's start times on the fps tempo grid: entry i = i/fps.
## (Per-frame AnimationFrameData.duration is a hold property for the frame
## controls, not a boundary — deliberately not read here.)
func frame_boundaries() -> Array[float]:
	var fps := timeline.fps if timeline != null else 12
	var out: Array[float] = []
	if frames == null:
		return out
	for i in frames.frames.size():
		out.append(float(i) / float(fps))
	return out


## Flat-list indices (into KeyframeController.keyframes) of that lane's keys
## with start <= time <= end.
func range_keys(lane_id: String, start: float, end: float) -> Array[int]:
	var out: Array[int] = []
	if keyframes == null:
		return out
	for i in keyframes.keyframes.size():
		var kf := keyframes.keyframes[i] as AnimationKeyframeData
		if _key_in_lane(kf, lane_id) and kf.time >= start and kf.time <= end:
			out.append(i)
	return out


## Flat index of the lane's key nearest `time` within `tolerance`, else -1
## (used to resolve a grabbed key tick to a flat-list index).
func key_index_at(lane_id: String, time: float, tolerance: float) -> int:
	var best := -1
	var best_distance := tolerance
	if keyframes == null:
		return best
	for i in keyframes.keyframes.size():
		var kf := keyframes.keyframes[i] as AnimationKeyframeData
		if not _key_in_lane(kf, lane_id):
			continue
		var distance := absf(kf.time - time)
		if distance <= tolerance and (best == -1 or distance < best_distance):
			best = i
			best_distance = distance
	return best


## The lane id a flat key belongs to, or "" when it is an orphan (no such
## registered target). This doubles as the membership/orphan route: object and
## light keys must match their lane's id exactly, camera keys match by type.
func _lane_for_key(kf: AnimationKeyframeData) -> String:
	match kf.target_type:
		KeyframeController.TARGET_CAMERA:
			return "camera"
		KeyframeController.TARGET_OBJECT:
			if world != null and not world.get_object(kf.target_id).is_empty():
				return kf.target_id
		KeyframeController.TARGET_LIGHT:
			if lighting != null and lighting.light_ids().has(kf.target_id):
				return kf.target_id
	return ""


## Whether `kf` belongs to the lane identified by `lane_id` (the same rule
## lanes() uses to route, so range_keys/key_index_at agree with the rendered
## lanes exactly).
func _key_in_lane(kf: AnimationKeyframeData, lane_id: String) -> bool:
	match _lane_type(lane_id):
		KeyframeController.TARGET_CAMERA:
			return kf.target_type == KeyframeController.TARGET_CAMERA
		KeyframeController.TARGET_OBJECT:
			return kf.target_type == KeyframeController.TARGET_OBJECT and kf.target_id == lane_id
		KeyframeController.TARGET_LIGHT:
			return kf.target_type == KeyframeController.TARGET_LIGHT and kf.target_id == lane_id
		_:
			return false


## Target type a lane id collects, or -1 when the id is not a lane. The frames
## lane never collects keys (the frame channel is separate).
func _lane_type(lane_id: String) -> int:
	if lane_id == "camera":
		return KeyframeController.TARGET_CAMERA
	if world != null and not world.get_object(lane_id).is_empty():
		return KeyframeController.TARGET_OBJECT
	if lighting != null and lighting.light_ids().has(lane_id):
		return KeyframeController.TARGET_LIGHT
	return -1


func _frames_lane() -> Dictionary:
	var keys: Array[Dictionary] = []
	return {"id": "frames", "kind": KIND_FRAMES, "label": "Frames", "keys": keys}


func _object_lane(object_id: String) -> Dictionary:
	var keys: Array[Dictionary] = []
	var data := world.get_object(object_id)
	var label := str(data.get("display_name", ""))
	if label.is_empty():
		label = object_id
	return {
		"id": object_id,
		"kind": KIND_OBJECT,
		"label": label,
		"keys": keys,
		"locked": bool(data.get("locked", false)),
	}


func _camera_lane() -> Dictionary:
	var keys: Array[Dictionary] = []
	return {"id": "camera", "kind": KIND_CAMERA, "label": "Camera", "keys": keys}


func _light_lane(light_id: String) -> Dictionary:
	var keys: Array[Dictionary] = []
	return {"id": light_id, "kind": KIND_LIGHT, "label": light_id, "keys": keys}


func _key_entry(kf: AnimationKeyframeData) -> Dictionary:
	return {
		"target_id": kf.target_id,
		"property_path": kf.property_path,
		"time": kf.time,
		"interpolation": kf.interpolation,
	}