extends Node

## Guided-mode workspace UI test (Task 13): instantiate the lab scene, verify
## the TopBar shows its mode label, then drive the stage machine through the
## assignment manager and check the per-stage panel visibility map:
## BRIEF -> AssignmentPanel, PLAN -> StoryboardPanel, FRAMES -> TimelinePanel,
## SUBMIT -> SubmissionPanel (with the other panels hidden).
##
## Scene-harness test on purpose: panels resolve via the CanvasLayer's own
## Control tree, which only exists once the scene is inside a running tree.

const LAB := "res://scenes/animation_production_lab/animation_production_lab.tscn"
const ASSIGN := "res://data/assignments/animation/day_in_emc_lab.tres"

func _ready() -> void:
	var tree := get_tree()
	var failures := await _run()
	if failures.is_empty():
		print("PASS: stage-driven panel switching")
		tree.quit(0)
	else:
		for f in failures:
			print("FAIL: ", f)
		tree.quit(1)


func _run() -> Array[String]:
	var failures: Array[String] = []
	var lab := load(LAB).instantiate() as AnimationProductionLab
	add_child(lab)
	await get_tree().process_frame

	if lab.top_bar.mode_label.text == "":
		failures.append("TopBar should show a mode label")
	if not lab.assignment_manager.load_assignment(ASSIGN):
		failures.append("assignment should load")

	lab.assignment_manager.go_to(AnimationAssignmentManager.Stage.BRIEF)
	if not lab.assignment_panel.visible:
		failures.append("BRIEF should show AssignmentPanel")
	if lab.timeline_panel.visible:
		failures.append("BRIEF should hide TimelinePanel")

	lab.assignment_manager.go_to(AnimationAssignmentManager.Stage.PLAN)
	if not lab.storyboard_panel.visible:
		failures.append("PLAN should show StoryboardPanel")
	if lab.assignment_panel.visible:
		failures.append("PLAN should hide AssignmentPanel")

	lab.assignment_manager.go_to(AnimationAssignmentManager.Stage.FRAMES)
	if not lab.timeline_panel.visible:
		failures.append("FRAMES should show TimelinePanel")

	lab.assignment_manager.go_to(AnimationAssignmentManager.Stage.SUBMIT)
	if not lab.submission_panel.visible:
		failures.append("SUBMIT should show SubmissionPanel")
	if lab.timeline_panel.visible:
		failures.append("SUBMIT should hide TimelinePanel")

	lab.queue_free()
	return failures