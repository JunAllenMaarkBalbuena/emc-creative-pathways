extends Node

## Guided-flow wiring: past PLAN, advance_stage() had no UI affordance — only
## BRIEF (brief acknowledged) and PLAN (storyboard order submitted) connected
## to it, so ASSETS..SUBMIT were only reachable by direct controller calls.
## This test drives the whole run through the real Continue button in the
## TopBar, exercising the live per-stage gates (STAGING re-measures the world,
## FRAMES/KEYFRAME/TIMING read the live controllers), the blocked-stage status
## feedback, and the visibility contract (hidden at BRIEF/SUBMIT, visible
## ASSETS..PREVIEW; hidden in Studio mode by _enter_studio_mode).
##
## Scene-harness test on purpose: buttons resolve inside a running tree.
## Autosave and the studio are disabled so the boot never touches
## user://animation_lab/guided.tres or user://level_progression.json.

const LAB := "res://scenes/animation_production_lab/animation_production_lab.tscn"

var _failures: Array[String] = []


func _ready() -> void:
	var tree := get_tree()
	_failures = await _run()
	if _failures.is_empty():
		print("PASS: continue button drives ASSETS through SUBMIT with live gates")
		tree.quit(0)
	else:
		for f in _failures:
			print("FAIL: ", f)
		tree.quit(1)


func _run() -> Array[String]:
	var failures: Array[String] = []
	var tree := get_tree()
	var lab := load(LAB).instantiate() as AnimationProductionLab
	lab.autosave_enabled = false
	lab.enable_creative_studio = false
	add_child(lab)
	for i in 3:
		await tree.process_frame

	var continue_button := lab.get_node("UI/TopBar/Row/ContinueButton") as Button
	if continue_button == null:
		failures.append("ContinueButton should exist in the TopBar")
		lab.queue_free()
		return failures
	var status: Label = lab.top_bar.status_label
	if status == null:
		failures.append("StatusLabel should exist in the TopBar")
		lab.queue_free()
		return failures

	if continue_button.visible:
		failures.append("Continue should be hidden at BRIEF (panels own their controls)")

	lab.assignment_manager.go_to(AnimationAssignmentManager.Stage.ASSETS)
	await tree.process_frame
	if not continue_button.visible:
		failures.append("Continue should be visible at ASSETS")

	_click(continue_button)
	await tree.process_frame
	if lab.assignment_manager.current_stage() != AnimationAssignmentManager.Stage.STAGING:
		failures.append("ASSETS should advance to STAGING via Continue")

	# Empty stage: the gate must block and explain itself on the StatusLabel.
	_click(continue_button)
	await tree.process_frame
	if lab.assignment_manager.current_stage() != AnimationAssignmentManager.Stage.STAGING:
		failures.append("STAGING must block advance with no objects placed")
	if status.text.is_empty():
		failures.append("blocked STAGING should report the unmet requirement")

	# Challenge E staging: character in front (z above the background's z) and
	# a prop within 2.0 units of the character. The gate re-measures the live
	# world on press — placing the objects is all the test has to do.
	var char_id := lab.world.add_asset(_make_asset("character"), Vector3(0, 0.5, 0))
	lab.world.add_asset(_make_asset("background"), Vector3(0, 1, -6))
	lab.world.add_asset(_make_asset("prop"), Vector3(1.2, 0.45, 0))
	_click(continue_button)
	await tree.process_frame
	if lab.assignment_manager.current_stage() != AnimationAssignmentManager.Stage.CAMERA:
		failures.append("STAGING should advance to CAMERA once the scene is staged")

	# CAMERA and LIGHTING are free stages (spec §4.1): straight through.
	_click(continue_button)
	await tree.process_frame
	_click(continue_button)
	await tree.process_frame
	if lab.assignment_manager.current_stage() != AnimationAssignmentManager.Stage.FRAMES:
		failures.append("CAMERA/LIGHTING should pass through to FRAMES")
	# Click again at FRAMES with no frames: the gate must block and explain.
	_click(continue_button)
	await tree.process_frame
	if lab.assignment_manager.current_stage() != AnimationAssignmentManager.Stage.FRAMES:
		failures.append("FRAMES must block advance with no frames")
	if status.text.is_empty():
		failures.append("blocked FRAMES should report the requirement")

	# Seed the frame/keyframe/timing data the same way the guided-flow test
	# does, then walk the remaining gates through Continue.
	var assign := lab.assignment_manager.assignment
	var correct_tex := load(assign.correct_frame_path) as Texture2D
	var other_tex := load(assign.candidate_frame_paths[0]) as Texture2D
	lab.frames.add_frame(correct_tex, 0.1)
	lab.frames.add_frame(other_tex, 0.1)
	lab.frames.add_frame(other_tex, 0.1)
	lab.keyframes.add_keyframe(0.0, char_id, KeyframeController.TARGET_OBJECT, "position", Vector3(0, 0.5, 0))
	lab.keyframes.add_keyframe(0.8, char_id, KeyframeController.TARGET_OBJECT, "visible", true)
	lab.timeline.set_fps(12)
	lab.timeline.set_duration(5.0)

	_click(continue_button)
	await tree.process_frame
	if lab.assignment_manager.current_stage() != AnimationAssignmentManager.Stage.KEYFRAME:
		failures.append("FRAMES should advance to KEYFRAME with frames seeded")
	_click(continue_button)
	await tree.process_frame
	if lab.assignment_manager.current_stage() != AnimationAssignmentManager.Stage.TIMING:
		failures.append("KEYFRAME should advance to TIMING with the movement keyframe")
	_click(continue_button)
	await tree.process_frame
	if lab.assignment_manager.current_stage() != AnimationAssignmentManager.Stage.PREVIEW:
		failures.append("TIMING should advance to PREVIEW with fps/duration on target")
	_click(continue_button)
	await tree.process_frame
	if lab.assignment_manager.current_stage() != AnimationAssignmentManager.Stage.SUBMIT:
		failures.append("PREVIEW should advance to SUBMIT via Continue")
	if continue_button.visible:
		failures.append("Continue should hide at SUBMIT (SubmissionPanel owns its Submit)")

	lab.queue_free()
	return failures


## Engine-routed real click — same helper as test_animation_ui_exit_click.gd:
## the control's center mapped through the viewport screen transform, then
## press+release via Input.parse_input_event so the GUI hit-test, including
## the modal panel stack, sees a genuine click.
func _click(control: Control) -> void:
	var center: Vector2 = get_viewport().get_screen_transform() * control.get_global_rect().get_center()
	_send_mouse_button(center, true)
	_send_mouse_button(center, false)


func _send_mouse_button(pos: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = pos
	ev.global_position = pos
	Input.parse_input_event(ev)


func _make_asset(category: String) -> EMCAssetData:
	var asset := EMCAssetData.new()
	asset.asset_id = "test_%s" % category
	asset.category = category
	match category:
		"character":
			asset.asset_type = "sprite"
			asset.path = "res://assets/char_animation/idle/1c66b4d4-7798-4026-9ddd-b75a5d3ce19d-8.png"
		"background":
			asset.asset_type = "sprite"
			asset.path = "res://assets/Scene_BG/Menu_Bg_image.png"
		"prop":
			asset.asset_type = "primitive"
	return asset