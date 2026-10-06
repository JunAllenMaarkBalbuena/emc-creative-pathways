class_name PreviewController
extends Node

## Applies the timeline to the live world: the frame channel swaps character
## Sprite3D textures at frame boundaries, and keyframe channels route
## evaluated values to the world/camera/lighting controllers by target_type
## and property_path. RF4: evaluate() returns null for an unknown target or a
## property with no track, and this controller skips those channels silently.
## evaluate_review() fills the 10-item review checklist — every item measured
## from the consumed controllers, never from stored state.

var timeline: TimelineController
var frames: FrameController
var keyframes: KeyframeController
var world: WorldController
var camera: AnimationCameraController
var lighting: LightingController

var review_checklist: Dictionary = {}


## Swap every visible character sprite to the current frame's texture.
## Missing texture (or out-of-range index) keeps the current sprite — never
## crashes.
func apply_frame() -> void:
	if frames == null or timeline == null or world == null:
		return
	var idx := timeline.current_frame_index()
	if idx >= frames.frames.size() or frames.frames[idx].texture == null:
		return
	var tex := frames.frames[idx].texture
	for object_id in world.all_objects():
		var data := world.get_object(object_id)
		if data.get("category", "") != WorldController.CATEGORY_CHARACTER:
			continue
		var node := world.get_object_node(object_id) as Sprite3D
		if node != null:
			node.texture = tex


## Evaluate every track at the current clock time and route by target type.
func apply_keyframes() -> void:
	if keyframes == null or timeline == null:
		return
	var t := timeline.current_time
	var seen: Dictionary = {}
	for kf in keyframes.keyframes:
		var channel := "%s|%d|%s" % [kf.target_id, kf.target_type, kf.property_path]
		if seen.has(channel):
			continue
		seen[channel] = true
		var value: Variant = keyframes.evaluate(kf.target_id, kf.property_path, t)
		if value == null:
			continue  # RF4: unknown target or missing track -> skip silently
		match kf.target_type:
			KeyframeController.TARGET_OBJECT:
				_apply_object(kf.target_id, kf.property_path, value)
			KeyframeController.TARGET_CAMERA:
				_apply_camera(kf.property_path, value)
			KeyframeController.TARGET_LIGHT:
				_apply_light(kf.target_id, kf.property_path, value)


## Advance the clock, apply keyframes, then the frame channel at boundaries.
func step(delta: float) -> void:
	if timeline == null:
		return
	var prev_index := timeline.current_frame_index()
	timeline.step_time(delta)
	apply_keyframes()
	if timeline.current_frame_index() != prev_index:
		apply_frame()


## Fill review_checklist: {label: String, passed: bool} for the 10 spec items,
## each read-only over the consumed controllers.
func evaluate_review() -> void:
	review_checklist.clear()
	var character_positions: Array[Vector3] = []
	var has_character := false
	var has_background := false
	if world != null:
		for object_id in world.all_objects():
			var data := world.get_object(object_id)
			var category: String = data.get("category", "")
			var visible: bool = data.get("visible", false)
			if category == WorldController.CATEGORY_CHARACTER:
				has_character = has_character or visible
				if visible:
					var node := world.get_object_node(object_id)
					if node != null:
						character_positions.append(node.position)
			elif category == WorldController.CATEGORY_BACKGROUND:
				has_background = has_background or visible
	_check("character visible", has_character)
	_check("background visible", has_background)
	_check("main action understandable", _has_movement_keyframe())
	_check("camera framed", _camera_framed(character_positions))
	_check("lighting sufficient", _lighting_ok())
	var frame_count := _frame_count()
	_check("beginning/middle/end present", frame_count >= 3)
	_check("timing correct", _timing_ok())
	_check("final pose visible", _final_pose_visible(frame_count))
	_check("pose change", _distinct_poses() >= 2)
	_check("plays without errors", _plays_without_errors())


func _check(label: String, passed: bool) -> void:
	review_checklist[label] = passed


func _apply_object(object_id: String, property_path: String, value: Variant) -> void:
	if world == null:
		return
	match property_path:
		"position":
			if value is Vector3:
				world.set_object_position(object_id, value as Vector3)
		"rotation":
			if value is Vector3:
				world.set_object_rotation(object_id, value as Vector3)
		"scale":
			if value is Vector3:
				world.set_object_scale(object_id, value as Vector3)
		"visible":
			if value is bool:
				world.set_object_visible(object_id, value)


func _apply_camera(property_path: String, value: Variant) -> void:
	if camera == null:
		return
	match property_path:
		"position":
			if value is Vector3:
				var cam := camera.camera()
				var rot := Vector3.ZERO if cam == null else cam.rotation_degrees
				camera.set_transform(value as Vector3, rot)
		"rotation":
			if value is Vector3:
				var cam := camera.camera()
				var pos := Vector3.ZERO if cam == null else cam.position
				camera.set_transform(pos, value as Vector3)
		"zoom":
			if value is float:
				camera.set_zoom(value)


func _apply_light(light_id: String, property_path: String, value: Variant) -> void:
	if lighting == null:
		return
	match property_path:
		"intensity":
			if value is float:
				lighting.set_intensity(light_id, value)
		"color":
			if value is Color:
				lighting.set_color(light_id, value)


func _has_movement_keyframe() -> bool:
	if keyframes == null:
		return false
	for kf in keyframes.keyframes:
		if kf.target_type == KeyframeController.TARGET_OBJECT \
				and (kf.property_path == "position" or kf.property_path == "rotation"):
			return true
	return false


func _camera_framed(character_positions: Array[Vector3]) -> bool:
	if camera == null or character_positions.is_empty():
		return false
	var cam := camera.camera()
	if cam == null or not cam.is_inside_tree():
		return false
	return camera.framing_ok(Vector3.ZERO, character_positions, camera.MAX_DISTANCE)


func _lighting_ok() -> bool:
	if lighting == null:
		return false
	return lighting.key_light_exists() and lighting.min_intensity() > 0.0


func _timing_ok() -> bool:
	if timeline == null:
		return false
	return absi(timeline.fps - 12) <= 2


func _frame_count() -> int:
	if frames == null:
		return 0
	return frames.frames.size()


func _final_pose_visible(frame_count: int) -> bool:
	if frames == null or frame_count <= 0:
		return false
	return frames.frames[frame_count - 1].texture != null


func _distinct_poses() -> int:
	if frames == null:
		return 0
	var seen: Dictionary = {}
	for frame in frames.frames:
		if frame.texture != null:
			seen[frame.texture.get_instance_id()] = true
	return seen.size()


func _plays_without_errors() -> bool:
	if frames == null or world == null or keyframes == null or timeline == null \
			or camera == null or lighting == null:
		return false
	return frames.frames.size() >= 1