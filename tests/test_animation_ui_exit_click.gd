extends Node

## Regression: the TopBar Exit button was unreachable by real mouse input at
## the gated stages. Full-rect modal panels (AssetLibraryPanel at ASSETS,
## TimelinePanel at FRAMES, the TutorialOverlay at boot) sat AFTER TopBar in
## the UI child order, and later siblings both draw and pick first, so their
## default STOP mouse_filter swallowed every click bound for the TopBar. The
## fix makes TopBar the LAST child of UI; this test proves the Exit button
## fires exit_requested under real (engine-routed) clicks at two stages with
## different modal panels up.
##
## Scene-harness test on purpose: buttons only resolve inside a running tree.
## Autosave and the studio are disabled so the boot never touches
## user://animation_lab/guided.tres or the progression file.

const LAB := "res://scenes/animation_production_lab/animation_production_lab.tscn"

var _exit_fires := 0


func _ready() -> void:
	var tree := get_tree()
	var lab := load(LAB).instantiate() as AnimationProductionLab
	lab.autosave_enabled = false
	lab.enable_creative_studio = false
	add_child(lab)
	for i in 3:
		await tree.process_frame

	var exit_button := lab.get_node("UI/TopBar/Row/ExitButton") as Button
	if exit_button == null:
		print("FAIL: ExitButton missing from TopBar")
		tree.quit(1)
		return

	# exit_lab -> SceneTransition.change_scene -> change_scene_to_file is
	# deferred to the end of the frame, so both clicks and both assertions
	# run synchronously inside this frame — the harness is never swapped out
	# mid-test. The second exit_requested fires the PASS and quits the loop,
	# which is also before the queued scene change.
	lab.top_bar.exit_requested.connect(_on_exit_fired)

	lab.assignment_manager.go_to(AnimationAssignmentManager.Stage.ASSETS)
	await tree.process_frame
	_click(exit_button)

	# Same frame, a second modal-heavy stage, to prove the fix is not tied to
	# one panel's layout.
	lab.assignment_manager.go_to(AnimationAssignmentManager.Stage.FRAMES)
	_click(exit_button)

	# If the clicks were swallowed, _exit_fires stays at 0, no PASS marker is
	# printed, and the gate reports the scene as failed (no PASS within the
	# frame budget).


func _on_exit_fired() -> void:
	_exit_fires += 1
	if _exit_fires >= 2:
		print("PASS: exit button reachable by real clicks at ASSETS and FRAMES")
		get_tree().quit(0)


## Engine-routed real click: map the control's center through the viewport
## screen transform (so headless 1280x1280 window coords line up), then push
## press+release through Input.parse_input_event — the same path a real mouse
## takes, including GUI hit-testing against the modal panel stack.
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