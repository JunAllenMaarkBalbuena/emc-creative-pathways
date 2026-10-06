extends SceneTree

## ScoringController test: nine weighted categories measured from controller
## state (spec §4.2). A fully-satisfied submission -> total 100 with every
## subscore 100 and empty feedback; an empty one -> ~0 with feedback; a "half"
## one (required categories placed, fps 13, no lights) -> staging/frame/timing
## full, lighting 0, total midway; RF2 - a character whose texture path is
## dead gives frame_animation_score 50 and never crashes.

const ASSIGNMENT_PATH := "res://data/assignments/animation/day_in_emc_lab.tres"
const RUN_7 := "res://assets/char_animation/run/7b805aea-b3c0-43fa-a4d2-84ef858de3d6-7.png"
const RUN_8 := "res://assets/char_animation/run/7b805aea-b3c0-43fa-a4d2-84ef858de3d6-8.png"
const RUN_9 := "res://assets/char_animation/run/7b805aea-b3c0-43fa-a4d2-84ef858de3d6-9.png"
const BG := "res://assets/Scene_BG/Menu_Bg_image.png"
const DEAD := "res://assets/char_animation/run/__dead__.png"

func _init() -> void:
	var failures := _run()
	if failures.is_empty():
		print("PASS: scoring measures nine categories from measurable requirements")
		quit(0)
	else:
		for f in failures:
			print("FAIL: ", f)
		quit(1)


func _run() -> Array[String]:
	var failures: Array[String] = []
	var assignment := load(ASSIGNMENT_PATH) as AnimationAssignment
	if assignment == null:
		failures.append("assignment did not load")
		return failures
	var scorer := ScoringController.new()

	# --- Full submission: every category satisfied -> total 100. ---
	var full := _fixture(true, true)
	var full_frames := FrameController.new()
	full_frames.add_frame(load(RUN_7) as Texture2D, 0.1)
	full_frames.add_frame(load(RUN_8) as Texture2D, 0.1)
	full_frames.add_frame(load(RUN_9) as Texture2D, 0.1)
	var full_keyframes := KeyframeController.new()
	full_keyframes.add_keyframe(0.0, "hero", KeyframeController.TARGET_OBJECT, "position", Vector3(0, 0, 0))
	full_keyframes.add_keyframe(0.5, "hero", KeyframeController.TARGET_OBJECT, "visible", true)
	# Extra keyframe (beyond requirements) -> creativity bonus.
	full_keyframes.add_keyframe(0.5, "light_1", KeyframeController.TARGET_LIGHT, "color", Color(1, 1, 1))
	var full_timeline := TimelineController.new()
	full_timeline.set_fps(12)
	full_timeline.set_duration(5.0)
	var full_world: WorldController = full["world"]
	var full_char := _add_character(full_world, RUN_7, Vector3(0, 0.3, -2))
	var full_bg := _add_asset(full_world, WorldController.CATEGORY_BACKGROUND, "bg", BG, Vector3(0, 0, -4))
	_add_asset(full_world, WorldController.CATEGORY_PROP, "desk", "", Vector3(0.8, 0.3, -2.5))
	if full_char == "" or full_bg == "":
		failures.append("could not stage the full world")
	var full_score := scorer.score(true, assignment, full_world,
		full["camera"] as AnimationCameraController, full["lighting"] as LightingController,
		full_frames, full_keyframes, full_timeline, _review(_ALL))
	if absf(full_score.total_score - 100.0) > 0.01:
		failures.append("full submission should total 100.0, got %s" % str(full_score.total_score))
	for label in ["story_score", "staging_score", "camera_score", "lighting_score",
			"frame_animation_score", "keyframe_score", "timing_score",
			"technical_score", "creativity_score"]:
		if full_score.get(label) != 100.0:
			failures.append("full submission %s should be 100, got %s" % [label, str(full_score.get(label))])
	if not full_score.feedback.is_empty():
		failures.append("full submission should produce no feedback")

	# --- Empty submission: nothing staged -> ~0 and non-empty feedback. ---
	var empty := _fixture(false, false)
	var empty_score := scorer.score(false, assignment,
		empty["world"] as WorldController, empty["camera"] as AnimationCameraController,
		empty["lighting"] as LightingController, FrameController.new(),
		KeyframeController.new(), _timeline(20, 5.0), _review([]))
	if empty_score.total_score >= 15.0:
		failures.append("empty submission should total ~0, got %s" % str(empty_score.total_score))
	if empty_score.feedback.is_empty():
		failures.append("empty submission should produce feedback")

	# --- Half submission: required categories placed, fps 13, no lights. ---
	var half := _fixture(false, false)
	var half_frames := FrameController.new()
	half_frames.add_frame(load(RUN_7) as Texture2D, 0.1)
	half_frames.add_frame(load(RUN_8) as Texture2D, 0.1)
	half_frames.add_frame(load(RUN_9) as Texture2D, 0.1)
	var half_world: WorldController = half["world"]
	_add_character(half_world, RUN_7, Vector3(0, 0.3, -2))
	_add_asset(half_world, WorldController.CATEGORY_BACKGROUND, "bg", BG, Vector3(0, 0, -4))
	_add_asset(half_world, WorldController.CATEGORY_PROP, "desk", "", Vector3(0.8, 0.3, -2.5))
	var half_score := scorer.score(true, assignment, half_world,
		half["camera"] as AnimationCameraController, half["lighting"] as LightingController,
		half_frames, KeyframeController.new(), _timeline(13, 5.0), _review(_HALF_OK))
	if half_score.staging_score != 100.0:
		failures.append("half staging should be 100, got %s" % str(half_score.staging_score))
	if half_score.frame_animation_score != 100.0:
		failures.append("half frame animation should be 100, got %s" % str(half_score.frame_animation_score))
	if half_score.timing_score != 100.0:
		failures.append("half timing should be 100 at fps 13 (tolerance 2), got %s" % str(half_score.timing_score))
	if half_score.lighting_score != 0.0:
		failures.append("half lighting should be 0 without lights, got %s" % str(half_score.lighting_score))
	if half_score.total_score < 40.0 or half_score.total_score > 70.0:
		failures.append("half total should be midway, got %s" % str(half_score.total_score))
	if half_score.feedback.is_empty():
		failures.append("half submission should produce feedback")

	# --- RF2: dead character texture -> frame_animation_score 50, no crash. ---
	var rf2 := _fixture(false, false)
	var rf2_world: WorldController = rf2["world"]
	_add_character(rf2_world, DEAD, Vector3(0, 0.3, -2))
	_add_asset(rf2_world, WorldController.CATEGORY_BACKGROUND, "bg", BG, Vector3(0, 0, -4))
	_add_asset(rf2_world, WorldController.CATEGORY_PROP, "desk", "", Vector3(0.8, 0.3, -2.5))
	var rf2_frames := FrameController.new()
	rf2_frames.add_frame(load(DEAD) as Texture2D, 0.1)  # fails to load -> null texture
	rf2_frames.add_frame(load(RUN_8) as Texture2D, 0.1)
	rf2_frames.add_frame(load(RUN_9) as Texture2D, 0.1)
	var rf2_score := scorer.score(true, assignment, rf2_world,
		rf2["camera"] as AnimationCameraController, rf2["lighting"] as LightingController,
		rf2_frames, KeyframeController.new(), _timeline(12, 5.0), _review(_HALF_OK))
	if rf2_score.frame_animation_score != 50.0:
		failures.append("RF2: dead-texture character should give frame animation 50, got %s" % str(rf2_score.frame_animation_score))
	if rf2_score.staging_score != 50.0:
		failures.append("RF2: required category without valid texture should give staging 50, got %s" % str(rf2_score.staging_score))
	var has_frame_feedback := false
	for line in rf2_score.feedback:
		if line.find("frame") != -1 or line.find("texture") != -1:
			has_frame_feedback = true
	if not has_frame_feedback:
		failures.append("RF2: feedback should mention the frame texture problem")

	return failures


const _ALL := ["character visible", "background visible", "main action understandable",
	"camera framed", "lighting sufficient", "beginning/middle/end present",
	"timing correct", "final pose visible", "pose change", "plays without errors"]
const _HALF_OK := ["character visible", "background visible", "main action understandable",
	"beginning/middle/end present", "final pose visible", "pose change"]


func _review(passed: Array) -> Dictionary:
	var d: Dictionary = {
		"character visible": false, "background visible": false,
		"main action understandable": false, "camera framed": false,
		"lighting sufficient": false, "beginning/middle/end present": false,
		"timing correct": false, "final pose visible": false,
		"pose change": false, "plays without errors": false,
	}
	for k in passed:
		d[k] = true
	return d


func _timeline(fps: int, duration: float) -> TimelineController:
	var t := TimelineController.new()
	t.set_fps(fps)
	t.set_duration(duration)
	return t


## Scratch stage: world (Characters/Backgrounds/Props), optional camera +
## Camera3D, optional lights. Returns {"world", "camera", "lighting", "stage"}.
func _fixture(with_camera: bool, with_lights: bool) -> Dictionary:
	var stage := Node3D.new()
	var world := WorldController.new()
	stage.add_child(world)
	world.add_child(_named("Characters"))
	world.add_child(_named("Backgrounds"))
	world.add_child(_named("Props"))
	world.character_root = NodePath("Characters")
	world.background_root = NodePath("Backgrounds")
	world.prop_root = NodePath("Props")
	var lighting := LightingController.new()
	stage.add_child(lighting)
	var lights := _named("Lights")
	stage.add_child(lights)
	lighting.lighting_root = NodePath("../Lights")
	var camera: AnimationCameraController = null
	if with_camera:
		camera = AnimationCameraController.new()
		stage.add_child(camera)
		var cam := Camera3D.new()
		cam.name = "Cam"
		stage.add_child(cam)
		camera.camera_path = NodePath("../Cam")
	if with_lights:
		lighting.add_light(LightingController.LIGHT_DIRECTIONAL, Vector3(3, 5, 1))
		lighting.add_light(LightingController.LIGHT_OMNI, Vector3(-2, 1.5, 1))
	return {"world": world, "camera": camera, "lighting": lighting, "stage": stage}


func _named(name: String) -> Node3D:
	var node := Node3D.new()
	node.name = name
	return node


func _add_character(world: WorldController, tex_path: String, pos: Vector3) -> String:
	return _add_asset(world, WorldController.CATEGORY_CHARACTER, "hero", tex_path, pos)


func _add_asset(world: WorldController, category: String, id: String, path: String, pos: Vector3) -> String:
	var asset := EMCAssetData.new()
	asset.asset_id = id
	asset.category = category
	asset.asset_type = "sprite"
	asset.path = path
	return world.add_asset(asset, pos)