class_name AnimationAssignmentManager
extends Node

## The guided-mode stage machine (spec §4). Loads an AnimationAssignment and
## turns its data into 11 stages (BRIEF..SUBMIT) with per-stage requirement
## gates, the challenge helpers A–F, hints, and a built-in tutorial walk.
## RF: load_assignment fails closed on a missing or wrong-typed resource and
## keeps the previous assignment; every helper returns a safe default instead
## of crashing when no assignment is loaded.

signal stage_changed(stage: int)
signal assignment_loaded(assignment: AnimationAssignment)

enum Stage {BRIEF, PLAN, ASSETS, STAGING, CAMERA, LIGHTING, FRAMES, KEYFRAME, TIMING, PREVIEW, SUBMIT}

var assignment: AnimationAssignment

## Challenge state written by the mutating helpers.
var story_order_correct := false
var staged_scene_ok := false

## Live data sources injected by the root (same plain-property pattern as
## PreviewController); used by keyframe_order_ok and the stage gates.
var keyframe_sources: KeyframeController
var frame_sources: FrameController
var timeline_sources: TimelineController

var tutorial_steps: Array[String] = [
	"Welcome to the Animation Lab.",
	"Read your assignment brief.",
	"Order the story beats.",
	"Open the asset library.",
	"Place your character.",
	"Add a background.",
	"Add a prop nearby.",
	"Frame your animation.",
	"Add a movement keyframe.",
	"Check the timing.",
	"Preview your animation.",
	"Submit your work.",
]
var tutorial_completed := false

var _stage: int = Stage.BRIEF


## Load + type-check an assignment resource. False on missing/tainted input —
## keeps the previous assignment, never crashes. A successful load resets the
## stage to BRIEF and the challenge state.
func load_assignment(path: String) -> bool:
	if not ResourceLoader.exists(path):
		return false
	var res: Resource = load(path)
	if res == null or not (res is AnimationAssignment):
		return false
	assignment = res as AnimationAssignment
	_stage = Stage.BRIEF
	story_order_correct = false
	staged_scene_ok = false
	assignment_loaded.emit(assignment)
	stage_changed.emit(_stage)
	return true


func current_stage() -> int:
	return _stage


## Live per-stage requirements. Each entry is {label, check: Callable, passed}
## where passed is re-evaluated on every call. Free stages (CAMERA, LIGHTING,
## PREVIEW) have no requirements; ASSETS only needs an assignment.
func stage_requirements() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	match current_stage():
		Stage.BRIEF:
			_add_requirement(result, "Story beats ordered", _story_order_ok)
		Stage.PLAN:
			_add_requirement(result, "Storyboard drafted", _story_order_ok)
		Stage.ASSETS:
			_add_requirement(result, "Assignment loaded", _assignment_loaded_ok)
		Stage.STAGING:
			_add_requirement(result, "Character placed first, prop nearby", _staging_ok)
		Stage.CAMERA, Stage.LIGHTING, Stage.PREVIEW:
			pass
		Stage.FRAMES:
			_add_requirement(result, "At least %d frames" % _min_frames(), _frames_ok)
		Stage.KEYFRAME:
			_add_requirement(result, "Movement keyframe before pose change", _keyframe_order_ok_callable)
		Stage.TIMING:
			_add_requirement(result, "Frames per second on target", _fps_live_ok)
			_add_requirement(result, "Duration of at least %s sec" % str(assignment.target_duration), _duration_ok)
		Stage.SUBMIT:
			_add_requirement(result, "Story beats ordered", _story_order_ok)
			_add_requirement(result, "Scene staged", _staging_ok)
			_add_requirement(result, "At least %d frames" % _min_frames(), _frames_ok)
			_add_requirement(result, "Movement keyframe before pose change", _keyframe_order_ok_callable)
			_add_requirement(result, "Timing on target", _timing_combined_ok)
	return result


func can_advance() -> bool:
	if assignment == null:
		return false
	for req in stage_requirements():
		if not req.get("passed", false):
			return false
	return true


func advance_stage() -> bool:
	if not can_advance():
		return false
	if current_stage() >= Stage.SUBMIT:
		return false
	go_to(current_stage() + 1)
	return true


func go_to(stage: int) -> void:
	var target := clampi(stage, Stage.BRIEF, Stage.SUBMIT)
	if target == _stage:
		return
	_stage = target
	stage_changed.emit(_stage)


## Challenge A: story beats in the assignment's `order` sequence.
func order_story_beats(ids: Array[String]) -> bool:
	story_order_correct = _matches_story_order(ids)
	return story_order_correct


## Challenge E: character before background AND a prop nearby. Records the
## result for the STAGING gate.
func stage_scene_ok(character_before_background: bool, near_prop: bool) -> bool:
	staged_scene_ok = character_before_background and near_prop
	return staged_scene_ok


## Challenge B: the picked frame is the assignment's correct missing frame.
func missing_frame_ok(texture: Texture2D) -> bool:
	if texture == null or assignment == null:
		return false
	return texture.resource_path == assignment.correct_frame_path


## Challenge C: fps within the assignment tolerance of the target.
func fps_ok(fps: int) -> bool:
	if assignment == null:
		return false
	return absi(fps - assignment.target_fps) <= assignment.fps_tolerance


## Challenge D+F: a TARGET_OBJECT/"position" keyframe at an earlier clock time
## than the first frame-channel pose change (>= 2 distinct frame textures).
func keyframe_order_ok() -> bool:
	if keyframe_sources == null or frame_sources == null:
		return false
	var position_time := -1.0
	for kf in keyframe_sources.keyframes:
		if kf.target_type == KeyframeController.TARGET_OBJECT and kf.property_path == "position":
			if position_time < 0.0 or kf.time < position_time:
				position_time = kf.time
	if position_time < 0.0:
		return false
	if frame_sources.frames.size() < 2:
		return false
	var pose_index := -1
	for i in frame_sources.frames.size():
		if frame_sources.frames[i].texture != frame_sources.frames[0].texture:
			pose_index = i
			break
	if pose_index < 0:
		return false
	var fps := 12.0
	if timeline_sources != null:
		fps = float(timeline_sources.fps)
	return position_time < float(pose_index) / maxf(fps, 1.0)


func hints_for_stage() -> Array[String]:
	if assignment == null:
		return []
	return assignment.hints


func tutorial_done() -> void:
	tutorial_completed = true


func _add_requirement(result: Array[Dictionary], label: String, check: Callable) -> void:
	result.append({"label": label, "check": check, "passed": check.call()})


func _story_order_ok() -> bool:
	return story_order_correct


func _staging_ok() -> bool:
	return staged_scene_ok


func _assignment_loaded_ok() -> bool:
	return assignment != null


func _frames_ok() -> bool:
	if assignment == null or frame_sources == null:
		return false
	return frame_sources.frames.size() >= assignment.min_frames


func _keyframe_order_ok_callable() -> bool:
	return keyframe_order_ok()


func _fps_live_ok() -> bool:
	if timeline_sources == null:
		return false
	return fps_ok(timeline_sources.fps)


func _duration_ok() -> bool:
	if timeline_sources == null or assignment == null:
		return false
	return timeline_sources.duration >= assignment.target_duration


func _timing_combined_ok() -> bool:
	return _fps_live_ok() and _duration_ok()


func _min_frames() -> int:
	if assignment == null:
		return 0
	return assignment.min_frames


func _expected_story_ids() -> Array[String]:
	var beats := assignment.story_beats.duplicate()
	beats.sort_custom(_by_story_order)
	var ids: Array[String] = []
	for beat in beats:
		ids.append(str(beat.get("id", "")))
	return ids


func _by_story_order(a: Dictionary, b: Dictionary) -> bool:
	return int(a.get("order", 0)) < int(b.get("order", 0))


func _matches_story_order(ids: Array[String]) -> bool:
	if assignment == null:
		return false
	if ids.size() != assignment.story_beats.size():
		return false
	var expected := _expected_story_ids()
	for i in ids.size():
		if ids[i] != expected[i]:
			return false
	return true