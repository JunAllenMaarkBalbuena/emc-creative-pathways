extends SceneTree

## AnimationAssignmentManager test: data-driven assignment load (with a
## type-taint fallback), the 11-stage machine with per-stage gating, the
## live stage_requirements() shape, and the challenge helpers A–F (story
## beat order, missing frame, fps tolerance, movement-before-pose-change).
## RF: a missing resource and a wrong-typed resource both fail closed and
## keep the previous assignment, never crashing.

const ASSIGNMENT_PATH := "res://data/assignments/animation/day_in_emc_lab.tres"
const RUN_7 := "res://assets/char_animation/run/7b805aea-b3c0-43fa-a4d2-84ef858de3d6-7.png"
const RUN_8 := "res://assets/char_animation/run/7b805aea-b3c0-43fa-a4d2-84ef858de3d6-8.png"

func _init() -> void:
	var failures := _run()
	if failures.is_empty():
		print("PASS: assignment loads and stage machine gates challenges A-F")
		quit(0)
	else:
		for f in failures:
			print("FAIL: ", f)
		quit(1)


func _run() -> Array[String]:
	var failures: Array[String] = []
	var manager := AnimationAssignmentManager.new()
	if not manager.load_assignment(ASSIGNMENT_PATH):
		failures.append("load_assignment(day_in_emc_lab) should be true")
		return failures
	if manager.assignment == null or manager.assignment.assignment_id != "day_in_emc_lab":
		failures.append("assignment data did not load (id mismatch)")
	if manager.assignment.story_beats.size() != 3:
		failures.append("assignment should carry 3 story beats")

	# Gating: BRIEF is a read-only intro (spec §4.1 "read the assignment,
	# Continue") — a loaded assignment is all it needs, so a fresh manager
	# advances to PLAN. The story-order gate lives at PLAN and SUBMIT, where
	# the storyboard is actually drafted.
	if manager.current_stage() != AnimationAssignmentManager.Stage.BRIEF:
		failures.append("fresh manager should sit at BRIEF")
	if not manager.advance_stage():
		failures.append("advance from BRIEF should succeed once the assignment is loaded")
	if manager.current_stage() != AnimationAssignmentManager.Stage.PLAN:
		failures.append("advancing from BRIEF should land on PLAN")

	# A stage with a live unmet gate (PLAN: story beats still unordered) must
	# refuse to advance and leave the stage put.
	if manager.advance_stage():
		failures.append("advance from PLAN must fail while the story is unordered")
	if manager.current_stage() != AnimationAssignmentManager.Stage.PLAN:
		failures.append("a failed advance must not move the stage")

	manager.go_to(AnimationAssignmentManager.Stage.STAGING)
	if manager.current_stage() != AnimationAssignmentManager.Stage.STAGING:
		failures.append("go_to(STAGING) did not land on STAGING")

	# Challenge A: story beat ordering (assignment story_beats must be ordered
	# by their `order` field: begin/middle/end).
	if not manager.order_story_beats(["begin", "middle", "end"]):
		failures.append("order_story_beats(correct order) should be true")
	if manager.order_story_beats(["end", "begin", "middle"]):
		failures.append("order_story_beats(jumbled) should be false")
	if not manager.order_story_beats(["begin", "middle", "end"]):
		failures.append("order_story_beats(correct order again) should be true")

	# Challenge B: missing-frame selection against correct_frame_path.
	if not manager.missing_frame_ok(load(RUN_8) as Texture2D):
		failures.append("missing_frame_ok(correct frame) should be true")
	if manager.missing_frame_ok(load(RUN_7) as Texture2D):
		failures.append("missing_frame_ok(wrong frame) should be false")
	if manager.missing_frame_ok(null):
		failures.append("missing_frame_ok(null) should be false")

	# Challenge C: fps tolerance (target 12, tolerance 2).
	if not manager.fps_ok(12) or not manager.fps_ok(13):
		failures.append("fps_ok(12/13) should be true within tolerance")
	if manager.fps_ok(20):
		failures.append("fps_ok(20) should be false beyond tolerance")
	if manager.fps_ok(0):
		failures.append("fps_ok(0) should be false (out of range)")

	# Challenge D+F: movement keyframe must precede the pose change.
	var frames_no_pose := FrameController.new()
	frames_no_pose.add_frame(load(RUN_7) as Texture2D, 0.1)
	var frames_pose := FrameController.new()
	frames_pose.add_frame(load(RUN_7) as Texture2D, 0.1)
	frames_pose.add_frame(load(RUN_7) as Texture2D, 0.1)
	frames_pose.add_frame(load(RUN_8) as Texture2D, 0.1)
	var keyframes := KeyframeController.new()
	keyframes.add_keyframe(0.0, "hero", KeyframeController.TARGET_OBJECT, "position", Vector3(0, 0, 0))
	var timeline := TimelineController.new()
	timeline.fps = 12
	manager.keyframe_sources = keyframes
	manager.frame_sources = frames_no_pose
	manager.timeline_sources = timeline
	if manager.keyframe_order_ok():
		failures.append("keyframe_order_ok must be false without a pose change")
	manager.frame_sources = frames_pose
	if not manager.keyframe_order_ok():
		failures.append("keyframe_order_ok should be true once a later pose change exists")

	# Live per-stage requirements: {label, check: Callable, passed}.
	manager.go_to(AnimationAssignmentManager.Stage.FRAMES)
	var reqs := manager.stage_requirements()
	if reqs.is_empty():
		failures.append("FRAMES stage should list at least one requirement")
	else:
		var first := reqs[0]
		if not first.has("label") or not first.has("check") or not first.has("passed"):
			failures.append("requirement entries must carry label/check/passed")

	# Hints are assignment-driven and non-empty once loaded.
	if manager.hints_for_stage().is_empty():
		failures.append("hints_for_stage should be non-empty with an assignment loaded")

	# RF: a missing resource -> false, previous assignment kept.
	if manager.load_assignment("res://data/assignments/animation/does_not_exist.tres"):
		failures.append("load_assignment(missing path) should be false")
	if manager.assignment == null or manager.assignment.assignment_id != "day_in_emc_lab":
		failures.append("a failed load must keep the previous assignment")

	# RF (type-taint): a well-formed .tres of the WRONG class must also fail
	# closed, quietly, and keep the previous assignment.
	var dir := "user://animation_lab_test"
	DirAccess.make_dir_recursive_absolute(dir)
	var tainted := dir + "/tainted.tres"
	var f := FileAccess.open(tainted, FileAccess.WRITE)
	if f == null:
		failures.append("could not write the tainted file")
	else:
		f.store_string("[gd_resource type=\"Resource\" script_class=\"LevelDefinition\" load_steps=2 format=3]\n")
		f.store_string("[ext_resource type=\"Script\" path=\"res://scripts/level_definition.gd\" id=\"1\"]\n")
		f.store_string("[resource]\n")
		f.store_string("script = ExtResource(\"1\")\n")
		f.store_string("level_id = \"tainted\"\n")
		f.close()
	if manager.load_assignment(tainted):
		failures.append("load_assignment(wrong-typed resource) should be false")
	if manager.assignment == null or manager.assignment.assignment_id != "day_in_emc_lab":
		failures.append("a wrong-typed load must keep the previous assignment")

	return failures