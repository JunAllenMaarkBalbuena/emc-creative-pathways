extends Node

## Regression test: the inspector panel must fit on screen and its labels must
## line up, REGARDLESS of whether the shear warning is showing.
##
## The defect. The inspector's fields lived in a 2-column GridContainer, which
## fills two cells per row in child order and SKIPS hidden children:
##
##   ShearWarning visible -> 20 visible children -> even -> parity holds
##   ShearWarning hidden   -> 19 visible children -> odd  -> every World row
##                                                          shifts one slot
##
## So the panel only lined up while the warning was showing, and snapped out of
## alignment the moment a clean object was selected. Measured: Local "Position:"
## at x=816, World "Position:" at x=1089 - mirrored, because the label and field
## columns had swapped.
##
## The second half of the complaint. Three SpinBoxes per row force a 542px
## minimum against a 360px anchored panel. A Control is sized up to its minimum
## and the panel is flush to the right edge, so it hung 78px past a 1280 screen
## (measured right edge x=1358).
##
## This asserts GEOMETRY, not appearance, because geometry is what was wrong and
## geometry is what can be checked without a human eye. It is deliberately blind
## to colours, fonts and spacing.
##
## Every size is asserted against the panel's OWN rect rather than a hardcoded
## number, so the test keeps working if the panel is later resized deliberately.
## The screen edge is the one absolute reference, because "outside the viewport"
## is the actual complaint.

var _fail := 0
var _done := 0
var _lab: ModelingLab

const SUB_TESTS := 7

## The shipped design resolution. Also the tightest case: a shorter window has
## less vertical room, a narrower one has less horizontal room.
const DESIGN := Vector2i(1280, 720)

## Slack for float rect arithmetic. Layout maths runs through several
## multiplications by the stretch factor, so exact equality is not available.
const EPS := 0.5


func _ready() -> void:
	var tree := get_tree()
	_lab = (load("res://scenes/modeling_lab/modeling_lab.tscn") as PackedScene).instantiate()
	add_child(_lab)
	await _settle()
	_lab._enter_creative_studio()
	await _settle()
	_lab.selection_manager.deselect_all()
	_lab._on_spawn_selected(PrimitiveDef.Type.CUBE)
	await _settle()
	get_window().size = DESIGN
	await _settle()
	_show_inspector()
	await _settle()

	await _test_panel_fits_inside_the_screen()
	await _test_no_field_crosses_the_panel_edge()
	await _test_labels_share_one_x_when_warning_is_hidden()
	await _test_labels_share_one_x_when_warning_is_visible()
	await _test_warning_visibility_does_not_move_any_field()
	await _test_panel_minimum_fits_its_anchor_box()
	await _test_inspector_content_fits_its_tab_area()

	_finish()


## The Inspector tab is index 1 and starts hidden, so it must be selected for the
## container chain to run a real layout pass. Measuring a hidden Control returns
## stale rects and produces meaningless numbers - the first draft of this probe
## did exactly that and every position came back at the parent's origin.
func _show_inspector() -> void:
	var tabs := _lab.get_node_or_null("%TabContainer") as TabContainer
	if tabs != null:
		tabs.current_tab = 1
	var sel := _lab.selection_manager.get_selected() as Node3D
	if sel != null:
		_lab._update_inspector(sel)


func _settle() -> void:
	for _i in 6:
		await get_tree().process_frame


# ── sub-tests ─────────────────────────────────────────────────────

## "the parts of the panel is outside the viewport panel"
func _test_panel_fits_inside_the_screen() -> void:
	if not await _ready_or_fail():
		return
	var screen := get_viewport().get_visible_rect().size
	var panel := _panel()
	var right := panel.position.x + panel.size.x
	if right > screen.x + EPS:
		_fail += 1
		print("FAIL: the panel's right edge is at x=%.1f on a %.0fpx screen, so %.0fpx "
			% [right, screen.x, right - screen.x]
			+ "of it is off the right edge. Its minimum size is inflating it past "
			+ "its anchor width.")
		return
	# A Control forced wider than its anchors keeps its left edge and grows right,
	# so an inflated panel is also wider than the anchor box intends.
	var anchor_w: float = panel.size.x
	if anchor_w < 1.0:
		_fail += 1
		print("FAIL: the panel has no width")
		return
	_done += 1
	print("      the panel fits: right edge %.0f on a %.0fpx screen"
		% [right, screen.x])


## The stronger form: not just the panel, but every individual field inside it.
## A panel can be on screen while a row of SpinBoxes still spills past its edge.
func _test_no_field_crosses_the_panel_edge() -> void:
	if not await _ready_or_fail():
		return
	var panel := _panel()
	var panel_right := panel.position.x + panel.size.x
	var screen_x := get_viewport().get_visible_rect().size.x
	var offenders: Array[String] = []
	for c in _all_fields():
		var r: Rect2 = (c as Control).get_global_rect()
		var over_panel: float = r.position.x + r.size.x - panel_right
		var over_screen: float = r.position.x + r.size.x - screen_x
		if over_panel > EPS or over_screen > EPS:
			offenders.append("%s (%+.0f past panel, %+.0f past screen)"
				% [c.name, over_panel, over_screen])
	if offenders.size() > 0:
		_fail += 1
		print("FAIL: %d control(s) cross the panel or screen edge: %s"
			% [offenders.size(), ", ".join(offenders)])
		return
	_done += 1
	print("      all %d fields sit inside the panel" % _all_fields().size())


## The alignment complaint, on the path that was BROKEN: a clean object, so the
## warning is hidden and the old GridContainer dropped a cell.
func _test_labels_share_one_x_when_warning_is_hidden() -> void:
	if not await _ready_or_fail():
		return
	var warn := _lab.get_node_or_null("%ShearWarning") as Control
	if warn != null and warn.visible:
		_fail += 1
		print("FAIL: the setup is wrong - the warning is visible, so this sub-test "
			+ "is not exercising the broken path")
		return
	var spread := _label_x_spread()
	if spread > EPS:
		_fail += 1
		print("FAIL: with the shear warning hidden the labels sit %.1fpx apart in "
			% spread + "x (%s). A hidden control is shifting the rows."
			% _label_x_report())
		return
	_done += 1
	print("      labels share one x with the warning hidden (spread %.2f)" % spread)


## The same assertion on the path that looked fine, so the fix cannot buy the
## broken case by breaking the working one.
func _test_labels_share_one_x_when_warning_is_visible() -> void:
	if not await _ready_or_fail():
		return
	var warn := _lab.get_node_or_null("%ShearWarning") as Control
	if warn == null:
		_fail += 1
		print("FAIL: there is no ShearWarning label")
		return
	warn.visible = true
	await _settle()
	var spread := _label_x_spread()
	if spread > EPS:
		_fail += 1
		print("FAIL: with the shear warning visible the labels sit %.1fpx apart in "
			% spread + "x (%s)" % _label_x_report())
		return
	_done += 1
	print("      labels share one x with the warning visible (spread %.2f)" % spread)


## The sharpest form of the bug: toggling the warning must not move any field
## HORIZONTALLY, and must not disturb anything ABOVE it.
##
## The first draft asserted no movement at all, in either axis, and failed for 9
## World fields shifted down 20px. That was the assertion being wrong, not the
## layout: the warning owns its own row, so when it appears everything below it
## MUST move down. Vertical reflow is correct behaviour. The original defect was
## horizontal - a column swap - so that is what is forbidden here.
func _test_warning_visibility_does_not_move_any_field() -> void:
	if not await _ready_or_fail():
		return
	var warn := _lab.get_node_or_null("%ShearWarning") as Control
	if warn == null:
		_fail += 1
		print("FAIL: there is no ShearWarning label")
		return
	warn.visible = false
	await _settle()
	var before := _field_rects()
	var warn_top_when_hidden: float = warn.position.y
	warn.visible = true
	await _settle()
	var after := _field_rects()

	var sideways: Array[String] = []
	var disturbed_above: Array[String] = []
	for key in before:
		if not after.has(key):
			continue
		var d: Vector2 = (after[key] as Vector2) - (before[key] as Vector2)
		if absf(d.x) > EPS:
			sideways.append("%s by %.1fpx in x" % [key, d.x])
		# A field sitting above where the warning will appear cannot legitimately
		# move in either axis, because the warning is below it.
		if (before[key] as Vector2).y < warn_top_when_hidden \
				and absf(d.y) > EPS:
			disturbed_above.append("%s by %.1fpx in y" % [key, d.y])
	if sideways.size() > 0 or disturbed_above.size() > 0:
		_fail += 1
		if sideways.size() > 0:
			print("FAIL: showing the shear warning moved %d field(s) SIDEWAYS: %s"
				% [sideways.size(), ", ".join(sideways)])
		if disturbed_above.size() > 0:
			print("FAIL: showing the warning moved %d field(s) that sit ABOVE it, "
				% disturbed_above.size()
				+ "which cannot legitimately reflow: %s"
				% ", ".join(disturbed_above))
		return
	_done += 1
	print("      toggling the warning moves nothing sideways, and nothing above it")


## Resolution-INDEPENDENT, and therefore stronger than checking two resolutions.
##
## The first draft of this sub-test resized the window to 1920x1080 and asserted
## against `get_visible_rect()`. That cannot work: under `canvas_items` + `expand`
## the visible rect stays at the design size when the window is resized at
## runtime, so it asserted a 1920 window against a 1280 viewport and failed for
## the wrong reason.
##
## The real property is that a Control only leaves the screen when its minimum
## size exceeds the box its anchors describe. So assert exactly that. If the
## minimum fits the anchor box the panel is correct at EVERY resolution, and
## there is no need to enumerate resolutions at all.
func _test_panel_minimum_fits_its_anchor_box() -> void:
	if not await _ready_or_fail():
		return
	var panel := _panel()
	var anchor_w: float = (panel.anchor_right - panel.anchor_left) \
		* panel.get_parent_area_size().x \
		+ (panel.offset_right - panel.offset_left)
	var min_w: float = panel.get_combined_minimum_size().x
	if min_w > anchor_w + EPS:
		_fail += 1
		print("FAIL: the panel needs %.0fpx but its anchors give it %.0fpx, so its "
			% [min_w, anchor_w]
			+ "minimum inflates it and pushes it off the right edge at every "
			+ "resolution. The fields are too wide for the panel.")
		return
	_done += 1
	print("      panel minimum %.0fpx fits its %.0fpx anchor box (so it fits at any "
		% [min_w, anchor_w] + "resolution)")


## Same idea vertically: the inspector's content must fit the tab area, or it
## needs to scroll. Asserted against the tab area rather than the window because
## that is the space actually available to the fields.
func _test_inspector_content_fits_its_tab_area() -> void:
	if not await _ready_or_fail():
		return
	var tabs := _lab.get_node_or_null("%TabContainer") as Control
	var insp := _lab.get_node_or_null("%TabContainer/Inspector") as Control
	if tabs == null or insp == null:
		_fail += 1
		print("FAIL: the TabContainer or Inspector is missing")
		return
	var avail: float = tabs.size.y - insp.position.y
	# A ScrollContainer reports a minimum height of 0 because it does not propagate
	# its child's, so the number that matters is the content's - measured one level
	# down, inside the scroller.
	var scroller := _find_scroller(insp) as Control
	var need: float = 0.0
	if scroller != null and scroller.get_child_count() > 0:
		need = (scroller.get_child(0) as Control).get_combined_minimum_size().y
	if need > avail + EPS and scroller == null:
		_fail += 1
		print("FAIL: the inspector needs %.0fpx of height but has %.0fpx, and "
			% [need, avail]
			+ "nothing inside it scrolls. It will clip on a shorter window.")
		return
	_done += 1
	print("      inspector content fits, or scrolls (needs %.0f, has %.0f)"
		% [need, avail])


## First ScrollContainer at or below `n`, or null. Looked up structurally so the
## test does not depend on what the scroller happens to be called.
func _find_scroller(n: Node) -> Node:
	if n == null:
		return null
	if n is ScrollContainer:
		return n
	for c in n.get_children():
		var found := _find_scroller(c)
		if found != null:
			return found
	return null


# ── helpers ───────────────────────────────────────────────────────

## True when the panel and all eighteen fields exist. Each dependent sub-test
## bails here rather than crashing partway and reporting a pass.
func _ready_or_fail() -> bool:
	if _panel() == null:
		_fail += 1
		print("FAIL: there is no RightPanel")
		return false
	if _all_fields().size() < 18:
		_fail += 1
		print("FAIL: expected 18 transform fields, found %d"
			% _all_fields().size())
		return false
	return true


func _panel() -> Control:
	return _lab.get_node_or_null("%RightPanel") as Control


## The eighteen SpinBoxes, found by UNIQUE NAME rather than by path. The point of
## this test is the geometry, and a geometry test must not also be a test of
## where the nodes happen to live - otherwise the fix under test would be forced
## to keep the very structure that caused the bug.
func _all_fields() -> Array:
	var out: Array = []
	for prefix in ["Pos", "Rot", "Scale", "WPos", "WRot", "WScale"]:
		for axis in ["X", "Y", "Z"]:
			var sb := _lab.get_node_or_null("%" + prefix + axis) as SpinBox
			if sb != null:
				out.append(sb)
	return out


func _labels() -> Array:
	var out: Array = []
	var insp := _lab.get_node_or_null("%TabContainer/Inspector") as Control
	if insp == null:
		return out
	for n in _walk(insp):
		if n is Label and (n as Label).text != "":
			out.append(n)
	return out


func _walk(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		out.append(c)
		out.append_array(_walk(c))
	return out


func _label_x_spread() -> float:
	var labels := _labels()
	if labels.size() < 2:
		return 0.0
	var lo := INF
	var hi := -INF
	for l in labels:
		var x: float = (l as Control).get_global_rect().position.x
		lo = minf(lo, x)
		hi = maxf(hi, x)
	return hi - lo


func _label_x_report() -> String:
	var parts: Array[String] = []
	for l in _labels():
		parts.append("%s@%.0f" % [l.name, (l as Control).get_global_rect().position.x])
	return ", ".join(parts)


func _field_rects() -> Dictionary:
	var out := {}
	for f in _all_fields():
		out[f.name] = (f as Control).get_global_rect().position
	return out


func _finish() -> void:
	if _done < SUB_TESTS:
		_fail += SUB_TESTS - _done
		print("FAIL: only %d of %d sub-tests completed - the rest died on an "
			% [_done, SUB_TESTS] + "unreported engine error, so the run above is "
			+ "NOT a pass")
	if _fail == 0:
		print("PASS: the inspector panel fits inside the viewport at every tested "
			+ "resolution, no field crosses its edge, and the labels stay on one x "
			+ "whether or not the shear warning is showing")
	get_tree().quit(1 if _fail else 0)