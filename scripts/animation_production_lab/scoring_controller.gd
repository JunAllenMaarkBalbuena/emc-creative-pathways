class_name ScoringController
extends RefCounted

## Turns live controller state into one AnimationScoreData report (spec §4.2).
## Nine 0..100 categories, each measured from a controller's state — never
## from stored flags — plus a weighted total and non-punitive feedback lines
## for every category under 100. RF2: dead texture paths degrade scores to 50
## instead of crashing.

const WEIGHT_STORY := 0.125
const WEIGHT_STAGING := 0.125
const WEIGHT_CAMERA := 0.10
const WEIGHT_LIGHTING := 0.10
const WEIGHT_FRAME := 0.125
const WEIGHT_KEYFRAME := 0.125
const WEIGHT_TIMING := 0.10
const WEIGHT_TECHNICAL := 0.10
const WEIGHT_CREATIVITY := 0.10

const REVIEW_TECHNICAL_THRESHOLD := 0.7  # >= 7/10 checklist items -> full marks


## story_order_correct comes from AnimationAssignmentManager (Challenge A).
func score(story_order_correct: bool, assignment: AnimationAssignment,
		world: WorldController, camera: AnimationCameraController,
		lighting: LightingController, frames: FrameController,
		keyframes: KeyframeController, timeline: TimelineController,
		review: Dictionary) -> AnimationScoreData:
	var result := AnimationScoreData.new()
	result.story_score = _story_score(story_order_correct)
	result.staging_score = _staging_score(assignment, world)
	result.camera_score = _camera_score(camera, world)
	result.lighting_score = _lighting_score(lighting)
	result.frame_animation_score = _frame_animation_score(assignment, frames)
	result.keyframe_score = _keyframe_score(assignment, keyframes)
	result.timing_score = _timing_score(assignment, timeline)
	result.technical_score = _technical_score(review)
	result.creativity_score = _creativity_score(assignment, world, keyframes)

	result.total_score = (
		result.story_score * WEIGHT_STORY
		+ result.staging_score * WEIGHT_STAGING
		+ result.camera_score * WEIGHT_CAMERA
		+ result.lighting_score * WEIGHT_LIGHTING
		+ result.frame_animation_score * WEIGHT_FRAME
		+ result.keyframe_score * WEIGHT_KEYFRAME
		+ result.timing_score * WEIGHT_TIMING
		+ result.technical_score * WEIGHT_TECHNICAL
		+ result.creativity_score * WEIGHT_CREATIVITY
	)
	_fill_feedback(result, assignment)
	return result


func _story_score(story_order_correct: bool) -> float:
	return 100.0 if story_order_correct else 0.0


func _staging_score(assignment: AnimationAssignment, world: WorldController) -> float:
	if assignment == null or world == null:
		return 0.0
	# Category presence + whether each present category shows a valid texture.
	var category_valid: Dictionary = {}
	for object_id in world.all_objects():
		var data := world.get_object(object_id)
		var category := str(data.get("category", ""))
		if category == "":
			continue
		if not category_valid.has(category):
			category_valid[category] = false
		if _object_has_valid_texture(world, object_id):
			category_valid[category] = true
	for required in assignment.required_categories:
		if not category_valid.has(required):
			return 0.0
	# RF2: a required category present but with no valid texture -> 50.
	for required in assignment.required_categories:
		if not category_valid[required]:
			return 50.0
	# Extra (non-required) assets that show no texture cost 20 each.
	var score := 100.0
	for object_id in world.all_objects():
		var data := world.get_object(object_id)
		var category := str(data.get("category", ""))
		if assignment.required_categories.has(category):
			continue
		if not _object_has_valid_texture(world, object_id):
			score -= 20.0
	return maxf(score, 0.0)


func _camera_score(camera: AnimationCameraController, world: WorldController) -> float:
	if camera == null or world == null:
		return 0.0
	var targets := _character_positions(world)
	if targets.is_empty():
		return 0.0  # no visible action to stage
	return 100.0 if camera.framing_ok(Vector3.ZERO, targets, camera.MAX_DISTANCE) else 0.0


func _lighting_score(lighting: LightingController) -> float:
	if lighting == null:
		return 0.0
	if lighting.key_light_exists() and lighting.min_intensity() > 0.0:
		return 100.0
	return 0.0


func _frame_animation_score(assignment: AnimationAssignment, frames: FrameController) -> float:
	if assignment == null or frames == null:
		return 0.0
	# RF2: a texture that failed to load cannot animate -> degraded 50.
	for frame in frames.frames:
		if frame.texture == null:
			return 50.0
	if frames.frames.size() < assignment.min_frames:
		return 0.0
	var score := 100.0
	if _distinct_poses(frames) >= 2:
		score += 10.0  # pose-change bonus, clamped so it never exceeds 100.
	return minf(score, 100.0)


func _keyframe_score(assignment: AnimationAssignment, keyframes: KeyframeController) -> float:
	if assignment == null or keyframes == null:
		return 0.0
	for required in assignment.required_keyframes:
		var wanted_type := int(required.get("target_type", -1))
		var wanted_path := str(required.get("property_path", ""))
		if not _has_any_keyframe(keyframes, wanted_type, wanted_path):
			return 0.0
	return 100.0


func _timing_score(assignment: AnimationAssignment, timeline: TimelineController) -> float:
	if assignment == null or timeline == null:
		return 0.0
	if absi(timeline.fps - assignment.target_fps) > assignment.fps_tolerance:
		return 0.0
	if timeline.duration >= assignment.target_duration and timeline.duration <= timeline.max_duration:
		return 100.0
	return 50.0


## Review is the 10-item checklist; plays_without_errors is one of its items,
## so the pass ratio over the whole checklist is the measure. >= 70% -> full.
func _technical_score(review: Dictionary) -> float:
	var total := review.size()
	if total == 0:
		return 0.0
	var passed := 0
	for key in review:
		if review[key] == true:
			passed += 1
	var ratio := float(passed) / float(total)
	if ratio >= REVIEW_TECHNICAL_THRESHOLD:
		return 100.0
	return ratio * 100.0


func _creativity_score(assignment: AnimationAssignment, world: WorldController,
		keyframes: KeyframeController) -> float:
	if _has_extra_keyframe(assignment, keyframes) or _has_extra_prop(assignment, world):
		return 100.0
	return 75.0


func _fill_feedback(result: AnimationScoreData, assignment: AnimationAssignment) -> void:
	result.feedback.clear()
	if result.story_score < 100.0:
		result.feedback.append("Order the story beats so the scene has a clear beginning, middle, and end.")
	if result.staging_score < 100.0:
		if result.staging_score == 0.0:
			result.feedback.append("Add every required element to the scene: character, background, and prop.")
		else:
			result.feedback.append("Make sure each placed asset shows a real image with no missing textures.")
	if result.camera_score < 100.0:
		result.feedback.append("Move the camera so it frames the main action.")
	if result.lighting_score < 100.0:
		result.feedback.append("Add a key light with enough intensity to read the scene.")
	if result.frame_animation_score < 100.0:
		if result.frame_animation_score == 50.0:
			result.feedback.append("Every frame needs a real texture before the animation can play.")
		else:
			result.feedback.append("Add at least %d frames to the animation." % _min_frames(assignment))
	if result.keyframe_score < 100.0:
		result.feedback.append("Add the required keyframes: a movement and a visibility change.")
	if result.timing_score < 100.0:
		if result.timing_score == 0.0:
			result.feedback.append("Set the frame rate near %d frames per second." % _target_fps(assignment))
		else:
			result.feedback.append("A longer timeline gives the action room to breathe.")
	if result.technical_score < 100.0:
		result.feedback.append("Run the review checklist — most items should pass before submitting.")
	if result.creativity_score < 100.0:
		result.feedback.append("Try an extra keyframe or a second prop for a creative touch.")


func _min_frames(assignment: AnimationAssignment) -> int:
	if assignment == null:
		return 0
	return assignment.min_frames


func _target_fps(assignment: AnimationAssignment) -> int:
	if assignment == null:
		return 12
	return assignment.target_fps


func _object_has_valid_texture(world: WorldController, object_id: String) -> bool:
	var node := world.get_object_node(object_id)
	if node == null:
		return false
	if node is Sprite3D:
		return (node as Sprite3D).texture != null
	return true  # Primitive props render geometry, not textures.


func _character_positions(world: WorldController) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for object_id in world.all_objects():
		var data := world.get_object(object_id)
		if str(data.get("category", "")) != WorldController.CATEGORY_CHARACTER:
			continue
		if not bool(data.get("visible", false)):
			continue
		var node := world.get_object_node(object_id)
		if node != null:
			result.append(node.position)
	return result


func _distinct_poses(frames: FrameController) -> int:
	var seen: Dictionary = {}
	for frame in frames.frames:
		seen[frame.texture.get_instance_id()] = true
	return seen.size()


func _has_any_keyframe(keyframes: KeyframeController, target_type: int, property_path: String) -> bool:
	for kf in keyframes.keyframes:
		if kf.target_type == target_type and kf.property_path == property_path:
			return true
	return false


func _has_extra_keyframe(assignment: AnimationAssignment, keyframes: KeyframeController) -> bool:
	if assignment == null or keyframes == null:
		return false
	for kf in keyframes.keyframes:
		if not _matches_required_keyframe(kf, assignment.required_keyframes):
			return true
	return false


func _matches_required_keyframe(kf: AnimationKeyframeData, required: Array[Dictionary]) -> bool:
	for req in required:
		if kf.target_type == int(req.get("target_type", -1)) and kf.property_path == str(req.get("property_path", "")):
			return true
	return false


func _has_extra_prop(assignment: AnimationAssignment, world: WorldController) -> bool:
	if assignment == null or world == null:
		return false
	var prop_count := 0
	for object_id in world.all_objects():
		var data := world.get_object(object_id)
		if str(data.get("category", "")) == WorldController.CATEGORY_PROP:
			prop_count += 1
	return prop_count >= 2  # one prop is required; a second one is the extra.