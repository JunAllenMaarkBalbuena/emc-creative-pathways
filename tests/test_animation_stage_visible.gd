extends Node

## Guided-flow layout: the working stages used to show only full-screen modal
## panels — the 3D SubViewport world (character/background/prop) was fully
## covered from BRIEF through TIMING, so placing and arranging objects had no
## visual feedback. The working panels are now docked (asset library and
## inspector on the right, timeline at the bottom) so the stage stays on
## screen from ASSETS through PREVIEW.
##
## This test encodes "the scene is not just the UI": at every working stage
## the active panel must NOT cover the window centre (which shows the 3D
## world), and at the read-and-decide stages (BRIEF/PLAN/SUBMIT) the
## full-screen modal MUST cover it.
##
## Scene-harness test on purpose: rects only resolve inside a running tree.
## Autosave and the studio are disabled so the boot never touches
## user://animation_lab/guided.tres.

const LAB := "res://scenes/animation_production_lab/animation_production_lab.tscn"


func _ready() -> void:
	var tree := get_tree()
	var failures := await _run()
	if failures.is_empty():
		print("PASS: 3D stage visible beside panels from ASSETS through PREVIEW")
		tree.quit(0)
	else:
		for f in failures:
			print("FAIL: ", f)
		tree.quit(1)


func _run() -> Array[String]:
	var failures: Array[String] = []
	var lab := load(LAB).instantiate() as AnimationProductionLab
	lab.autosave_enabled = false
	lab.enable_creative_studio = false
	add_child(lab)
	for i in 3:
		await get_tree().process_frame

	# The SubViewport world fills the whole window behind the panels, so the
	# window centre is the world centre: any panel that covers it hides the
	# stage from the player.
	var center := get_viewport().get_visible_rect().get_center()

	var working := {
		AnimationAssignmentManager.Stage.ASSETS: lab.asset_library_panel,
		AnimationAssignmentManager.Stage.STAGING: lab.inspector_panel,
		AnimationAssignmentManager.Stage.CAMERA: lab.inspector_panel,
		AnimationAssignmentManager.Stage.LIGHTING: lab.inspector_panel,
		AnimationAssignmentManager.Stage.FRAMES: lab.timeline_panel,
		AnimationAssignmentManager.Stage.KEYFRAME: lab.timeline_panel,
		AnimationAssignmentManager.Stage.TIMING: lab.timeline_panel,
		AnimationAssignmentManager.Stage.PREVIEW: lab.hint_panel,
	}
	for stage in working:
		lab.assignment_manager.go_to(stage)
		await get_tree().process_frame
		var panel := working[stage] as Control
		if panel == null:
			failures.append("stage %s: panel missing" % stage)
		elif panel.get_global_rect().has_point(center):
			failures.append("stage %s: %s must not cover the world centre" % [
				AnimationProductionLab.STAGE_NAMES[stage], panel.name])

	var modal := {
		AnimationAssignmentManager.Stage.BRIEF: lab.assignment_panel,
		AnimationAssignmentManager.Stage.PLAN: lab.storyboard_panel,
		AnimationAssignmentManager.Stage.SUBMIT: lab.submission_panel,
	}
	for stage in modal:
		lab.assignment_manager.go_to(stage)
		await get_tree().process_frame
		var panel := modal[stage] as Control
		if panel == null:
			failures.append("stage %s: panel missing" % stage)
		elif not panel.get_global_rect().has_point(center):
			failures.append("stage %s: %s should keep the full-screen modal" % [
				AnimationProductionLab.STAGE_NAMES[stage], panel.name])

	lab.queue_free()
	return failures