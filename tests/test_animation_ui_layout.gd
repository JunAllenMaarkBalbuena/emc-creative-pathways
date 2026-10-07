extends Node

## Animation lab UI layout regression test.
##
## Regression: the lab root `UI` Control was 0x0 (anchors_preset 0 under the
## CanvasLayer root, no size), so every anchored panel collapsed into the
## top-left corner, and bottom-docked panels like AnimationControls floated
## above the window — "the UI is bugged and part outside the viewport screen".
## The fix gives `UI` full-rect anchors so panels resolve against the window.
##
## This test proves the invariant that encodes the user-visible symptom: every
## UI panel's rect must sit entirely inside the window's visible rect, with the
## edge-docked panels landing on the exact edges they were authored for.
##
## Scene-harness test on purpose: the layout only exists once the scene is
## inside a running tree (same reason as test_animation_ui_stages.gd). Autosave
## is disabled so the boot never touches user://animation_lab/guided.tres.

const LAB := "res://scenes/animation_production_lab/animation_production_lab.tscn"
const EPSILON := 1.0

func _ready() -> void:
	var tree := get_tree()
	var failures := await _run()
	if failures.is_empty():
		print("PASS: animation lab UI stays inside the viewport")
		tree.quit(0)
	else:
		for f in failures:
			print("FAIL: ", f)
		tree.quit(1)


func _inside(rect: Rect2, bounds: Rect2) -> bool:
	return rect.position.x >= bounds.position.x - EPSILON \
		and rect.position.y >= bounds.position.y - EPSILON \
		and rect.end.x <= bounds.end.x + EPSILON \
		and rect.end.y <= bounds.end.y + EPSILON


func _matches(rect: Rect2, bounds: Rect2) -> bool:
	return rect.position.x >= bounds.position.x - EPSILON \
		and rect.position.y >= bounds.position.y - EPSILON \
		and absf(rect.end.x - bounds.end.x) <= EPSILON \
		and absf(rect.end.y - bounds.end.y) <= EPSILON


func _run() -> Array[String]:
	var failures: Array[String] = []
	var lab := load(LAB).instantiate() as AnimationProductionLab
	lab.autosave_enabled = false
	lab.enable_creative_studio = false
	add_child(lab)
	for i in 3:
		await get_tree().process_frame

	var vp: Rect2 = get_viewport().get_visible_rect()
	var ui := lab.get_node("UI") as Control
	var ui_rect: Rect2 = ui.get_global_rect()
	if absf(ui_rect.position.x) > EPSILON or absf(ui_rect.position.y) > EPSILON \
			or absf(ui_rect.size.x - vp.size.x) > EPSILON \
			or absf(ui_rect.size.y - vp.size.y) > EPSILON:
		failures.append("UI root must track the window rect, got %s vs %s" % [ui_rect, vp])

	for child in ui.get_children():
		if child is Control:
			var c := child as Control
			if not _inside(c.get_global_rect(), vp):
				failures.append("%s escapes the viewport: rect %s vs window %s" % [
					c.name, c.get_global_rect(), vp])

	var top_rect: Rect2 = (lab.get_node("UI/TopBar") as Control).get_global_rect()
	if absf(top_rect.position.y) > EPSILON or absf(top_rect.size.y - 56.0) > EPSILON \
			or absf(top_rect.end.x - vp.end.x) > EPSILON:
		failures.append("TopBar should be a full-width 56px top strip, got %s" % top_rect)

	var controls_rect: Rect2 = (lab.get_node("UI/AnimationControls") as Control).get_global_rect()
	if absf(controls_rect.size.y - 72.0) > EPSILON \
			or absf(controls_rect.end.x - vp.end.x) > EPSILON \
			or absf(controls_rect.end.y - vp.end.y) > EPSILON:
		failures.append("AnimationControls should be a full-width 72px bottom strip, got %s" % controls_rect)

	var hint_rect: Rect2 = (lab.get_node("UI/HintPanel") as Control).get_global_rect()
	if absf(hint_rect.position.x) > EPSILON or absf(hint_rect.end.y - vp.end.y) > EPSILON:
		failures.append("HintPanel should sit on the bottom-left edge, got %s" % hint_rect)

	var assign_rect: Rect2 = (lab.get_node("UI/AssignmentPanel") as Control).get_global_rect()
	if not _matches(assign_rect, vp):
		failures.append("AssignmentPanel should fill the viewport, got %s vs %s" % [assign_rect, vp])

	lab.queue_free()
	return failures