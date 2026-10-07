extends Node

## Dock layout test (plan Task 6): the Studio gets a real docked layout —
## TopBar check-toggles (Layers/Inspector/Assets/Timeline) and thin resize
## strips that drag the dockers' edges. Assertions (per plan + Review-Focus
## #5): toggles are Studio-only (hidden in GUIDED), toggling Layers off hides
## the panel and its strip, a simulated strip drag widens LayersPanel by the
## delta while Inspector stays put, clamps keep the panel >= 120px and inside
## the window, and every UI child stays inside the viewport after the
## resize + toggles.
##
## Scene-harness test: panels resolve only once the scene is running. Studio
## boots via unlock_creative_studio() after setting the completed flag (the
## plan's non-file alternative to the save_roundtrip backup pattern).

const LAB := "res://scenes/animation_production_lab/animation_production_lab.tscn"
const EPSILON := 1.0

func _ready() -> void:
	var tree := get_tree()
	var failures := await _run()
	if failures.is_empty():
		print("PASS: studio dock layout - resize strips + toggles")
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


func _run() -> Array[String]:
	var failures: Array[String] = []
	var lab := load(LAB).instantiate() as AnimationProductionLab
	lab.autosave_enabled = false
	lab.enable_creative_studio = true
	add_child(lab)
	for i in 3:
		await get_tree().process_frame

	# Pre-implementation guard: the strips are the new nodes this task adds.
	if lab.get_node_or_null("UI/LayersResizeStrip") == null:
		failures.append("LayersResizeStrip is missing from the lab scene")
		return failures

	# GUIDED: dock toggles are studio-only (Review-Focus #5)
	if (lab.top_bar.get_node("%LayersToggle") as CheckButton).visible:
		failures.append("dock toggles must be hidden in GUIDED mode")

	# Boot Studio
	lab.guided_completed = true
	lab.unlock_creative_studio()
	if not (lab.top_bar.get_node("%LayersToggle") as CheckButton).visible:
		failures.append("dock toggles should be visible in Studio")
	if not lab.layers_panel.visible:
		failures.append("LayersPanel should be visible in Studio")
	if not (lab.get_node("UI/LayersResizeStrip") as Control).visible:
		failures.append("LayersResizeStrip should be visible in Studio")

	# Toggle Layers off hides panel + strip; on restores
	(lab.top_bar.get_node("%LayersToggle") as CheckButton).emit_signal("toggled", false)
	if lab.layers_panel.visible:
		failures.append("Layers toggle off should hide the panel")
	if (lab.get_node("UI/LayersResizeStrip") as Control).visible:
		failures.append("Layers toggle off should hide its resize strip")
	(lab.top_bar.get_node("%LayersToggle") as CheckButton).emit_signal("toggled", true)
	if not lab.layers_panel.visible:
		failures.append("Layers toggle on should show the panel")

	# Simulated strip drag widens LayersPanel; Inspector stays put
	var strip := lab.get_node("UI/LayersResizeStrip") as Control
	var before_l: float = lab.layers_panel.size.x
	var before_i: float = lab.inspector_panel.size.x
	strip.call("_apply", 40.0)
	if not is_equal_approx(lab.layers_panel.size.x, before_l + 40.0):
		failures.append("strip drag should widen LayersPanel by 40, got %s -> %s" % [before_l, lab.layers_panel.size.x])
	if not is_equal_approx(lab.inspector_panel.size.x, before_i):
		failures.append("Inspector should stay put during a Layers resize")

	# Clamp: a huge delta keeps the panel in-window and >= 120px
	strip.call("_apply", 5000.0)
	var vp: Rect2 = get_viewport().get_visible_rect()
	var lr: Rect2 = lab.layers_panel.get_global_rect()
	if lr.end.x > vp.end.x + EPSILON:
		failures.append("LayersPanel must never leave the window: %s vs %s" % [lr, vp])
	if lab.layers_panel.size.x < 120.0 - EPSILON:
		failures.append("LayersPanel must never collapse below 120px")

	# Every UI child stays inside the window after the resize + toggles
	for child in (lab.get_node("UI") as Control).get_children():
		if child is Control:
			var c := child as Control
			if not _inside(c.get_global_rect(), vp):
				failures.append("%s escapes the viewport: rect %s vs window %s" % [c.name, c.get_global_rect(), vp])

	lab.queue_free()
	return failures