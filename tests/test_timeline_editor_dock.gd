extends Node

## Timeline editor dock wiring (plan Task 4): the lab root consumes the
## docker boundary — the 8 TimelinePanel signals must reach the owning
## controllers (spec §6 handlers), the 5 data-change signals must rebuild the
## editor, keyframes.history/keyframes.timeline must be injected and
## timeline_panel.bind(...) must wire the editor's sources. Also pins the
## guided stage map this wiring lives under (spec §6: unchanged — shown from
## FRAMES, hidden before it; Studio always) and the two Review-Focus #2
## halves that must stay true after the edits: a project load leaves an empty
## undo stack, and evaluate_review still fills all 10 checklist items.
##
## Scene-harness test: mirror of test_animation_dock_layout.gd (boot with
## enable_creative_studio, panels resolve after a few frames; Studio opens
## via guided_completed + unlock_creative_studio).

const LAB := "res://scenes/animation_production_lab/animation_production_lab.tscn"
const TimelineEditor := preload("res://scripts/animation_production_lab/ui/timeline_editor.gd")
const TimelineLaneModel := preload("res://scripts/animation_production_lab/ui/timeline_lane_model.gd")
const TimelinePanel := preload("res://scripts/animation_production_lab/ui/timeline_panel.gd")


func _ready() -> void:
	var tree := get_tree()
	var failures := await _run()
	if failures.is_empty():
		print("PASS: timeline editor dock wiring - routing, refresh, injection, gating")
		tree.quit(0)
	else:
		for f in failures:
			print("FAIL: ", f)
		tree.quit(1)


func _run() -> Array[String]:
	var failures: Array[String] = []
	var lab := load(LAB).instantiate() as AnimationProductionLab
	lab.autosave_enabled = false
	lab.enable_creative_studio = true
	add_child(lab)
	for i in 3:
		await get_tree().process_frame

	var panel := lab.timeline_panel

	# --- structure: the Task 3 dock the root now wires into -----------------
	var ed := panel.get_node("%TimelineEditor") as TimelineEditor
	if ed == null:
		failures.append("timeline_panel should contain %TimelineEditor")
		return failures
	for toolbar_node in ["SnapToggle", "ZoomIn", "ZoomOut", "DeleteSelection"]:
		if panel.get_node("%" + str(toolbar_node)) == null:
			failures.append("timeline_panel toolbar should contain %" + str(toolbar_node))

	# --- guided gating: the unchanged stage map (spec §6, ruling 2) ---------
	var am := lab.assignment_manager
	am.go_to(AnimationProductionLab.STAGE_LIGHTING)
	if panel.visible:
		failures.append("timeline should stay hidden before the FRAMES stage")
	for stage in [
		AnimationProductionLab.STAGE_FRAMES,
		AnimationProductionLab.STAGE_KEYFRAME,
		AnimationProductionLab.STAGE_TIMING,
	]:
		am.go_to(stage)
		if not panel.visible:
			failures.append("timeline should be visible at the %s stage" % AnimationProductionLab.STAGE_NAMES[stage])
		if not ed.is_visible_in_tree():
			failures.append("TimelineEditor should be visible in the tree at the %s stage" % AnimationProductionLab.STAGE_NAMES[stage])
	am.go_to(AnimationProductionLab.STAGE_LIGHTING)
	if panel.visible:
		failures.append("timeline should be hidden again at the LIGHTING stage")

	# Studio always: unlock while the guided map hides the panel and it must
	# show anyway.
	lab.guided_completed = true
	lab.unlock_creative_studio()
	if lab.mode != AnimationProductionLab.Mode.STUDIO:
		failures.append("unlock_creative_studio should enter STUDIO mode")
	if not panel.visible:
		failures.append("timeline should be visible in Studio")
	if not ed.is_visible_in_tree():
		failures.append("TimelineEditor should be visible in the tree in Studio")

	# --- staging: two object lanes for the routing asserts ------------------
	var prop_assets := lab.library.list("prop")
	if prop_assets.is_empty():
		failures.append("no prop starter asset to stage")
		return failures
	var id_a := lab.world.add_asset(prop_assets[0], Vector3(1, 0.5, 0))
	var id_b := lab.world.add_asset(prop_assets[0], Vector3(2, 0.5, 0))
	if id_a.is_empty() or id_b.is_empty():
		failures.append("world.add_asset should stage the two props")
		return failures

	# bind() must have wired the world into the editor's lane model: with no
	# set_sources call the model has no world, so the object lanes never
	# appear even though refresh() itself may run.
	var lane_ids: Array[String] = []
	for lane in ed._lanes:
		lane_ids.append(str(lane["id"]))
	if not lane_ids.has(id_b):
		failures.append("bind() should derive object lanes for the editor (missing lane %s)" % id_b)

	# --- routing: the forwarded signals land on the owning controllers ------
	panel.lane_pressed.emit(id_b, TimelineLaneModel.KIND_OBJECT)
	if lab.world.selected() != id_b:
		failures.append("lane_pressed should select the object lane on the world, got %s" % lab.world.selected())
	var light_ids := lab.lighting.light_ids()
	if light_ids.is_empty():
		failures.append("starter lights should register at boot")
	else:
		panel.lane_pressed.emit(light_ids[0], TimelineLaneModel.KIND_LIGHT)
		if lab.lighting.selected() != light_ids[0]:
			failures.append("lane_pressed should select the light lane on the lighting controller, got %s" % lab.lighting.selected())

	panel.playhead_requested.emit(2.0)
	if not is_equal_approx(lab.timeline.current_time, 2.0):
		failures.append("playhead_requested should scrub the timeline to 2.0, got %s" % lab.timeline.current_time)
	if not is_equal_approx(ed.get_playhead_time(), 2.0):
		failures.append("the editor playhead should follow time_changed (bind wires it), got %s" % ed.get_playhead_time())

	panel.snap_toggled.emit(false)
	if ed.get_snap():
		failures.append("snap_toggled(false) should turn the editor's snap off")
	panel.snap_toggled.emit(true)
	if not ed.get_snap():
		failures.append("snap_toggled(true) should turn the editor's snap back on")

	# key_add needs its key present before anything downstream can index it,
	# so the whole edit chain collapses into one failure if the handler is
	# missing (the RED state).
	panel.key_add_requested.emit(id_b, TimelineLaneModel.KIND_OBJECT, 1.0)
	if lab.keyframes.keyframes.size() != 1:
		failures.append("key_add_requested should add exactly one key, got %d" % lab.keyframes.keyframes.size())
	else:
		failures.append_array(_key_edit_chain(lab, panel, ed, id_b))

	# --- wiring identity (spec §6 injections) -------------------------------
	if lab.keyframes.history != lab.world.history:
		failures.append("keyframes.history should be the world's EditorHistory")
	if lab.keyframes.timeline != lab.timeline:
		failures.append("keyframes.timeline should be the lab's TimelineController")

	# --- the five refresh subscriptions (spec §6) + idempotency (ruling 1) --
	# The editor self-subscribes to keyframes_changed only (Task 3, load-
	# bearing for the bare-harness §7 test); the other four signals reach
	# refresh() solely through the root's subscriptions. refresh() must stay
	# idempotent: the same lane set rebuilds the same lanes and keeps the
	# selection (which is only cleared when the lane-id set changes).
	ed._selection["__probe"] = {"start": 0.0, "end": 1.0}
	var subs: Array[Signal] = [
		lab.keyframes.keyframes_changed,
		lab.frames.frames_changed,
		lab.lighting.lights_changed,
		lab.world.objects_changed,
		lab.world.layer_order_changed,
	]
	for sub in subs:
		var rc := ed.get_refresh_count()
		var lanes_before := ed._lanes.size()
		sub.emit()
		if ed.get_refresh_count() < rc + 1:
			failures.append("%s should rebuild the editor (refresh count stuck at %d)" % [sub.get_name(), rc])
		if ed._lanes.size() != lanes_before:
			failures.append("%s refresh must rebuild the same lane count (%d -> %d)" % [sub.get_name(), lanes_before, ed._lanes.size()])
		if not ed._selection.has("__probe"):
			failures.append("%s refresh must keep the selection when the lane set is unchanged" % sub.get_name())

	# --- Loader quiet (Review-Focus #2 root half) ---------------------------
	# A 2-key synthetic save through the real _apply_project_data: set_all
	# pushes no history entry, so an undo after a load can never un-add the
	# loaded keys (Task 1's swap — asserted here, not re-implemented).
	var saved := AnimationLabSaveData.new()
	saved.keyframes = [
		{
			"time": 0.5, "target_id": id_b,
			"target_type": KeyframeController.TARGET_OBJECT,
			"property_path": "position", "value": Vector3(2, 0.5, 0),
			"interpolation": KeyframeController.LINEAR,
		},
		{
			"time": 1.5, "target_id": id_b,
			"target_type": KeyframeController.TARGET_OBJECT,
			"property_path": "position", "value": Vector3(3, 0.5, 0),
			"interpolation": KeyframeController.LINEAR,
		},
	]
	lab._apply_project_data(saved)
	if lab.world.history.can_undo():
		failures.append("a project load must leave the undo stack empty")
	if lab.keyframes.keyframes.size() != 2:
		failures.append("the load should install exactly 2 keys, got %d" % lab.keyframes.keyframes.size())
	elif not (is_equal_approx(_key_at(lab, 0), 0.5) and is_equal_approx(_key_at(lab, 1), 1.5)):
		failures.append("the loaded keys should sort to 0.5/1.5, got %s/%s" % [_key_at(lab, 0), _key_at(lab, 1)])

	# Scoring stays intact after the edits above (10/10, spec §7).
	lab.preview.evaluate_review()
	if lab.preview.review_checklist.size() != 10:
		failures.append("evaluate_review should fill all 10 checklist items, got %d" % lab.preview.review_checklist.size())

	lab.queue_free()
	await get_tree().process_frame
	return failures


## The key-edit chain behind key_add: spec §6 field checks (evaluate first,
## live position fallback), the flat index the editor would resolve at
## gesture press, the re-time, the top-bar undo/redo round trip through the
## injected history, and the span ops. Called only when key_add produced
## exactly one key; every failure path below reports instead of crashing even
## if an individual op turns out to be a no-op.
func _key_edit_chain(lab: AnimationProductionLab, panel: TimelinePanel, ed: TimelineEditor, target_id: String) -> Array[String]:
	var failures: Array[String] = []
	var kf := lab.keyframes.keyframes[0]
	if kf.target_id != target_id or kf.target_type != KeyframeController.TARGET_OBJECT:
		failures.append("key_add should target the pressed object, got %s/%d" % [kf.target_id, kf.target_type])
	if kf.property_path != "position":
		failures.append("key_add should write the position track, got %s" % kf.property_path)
	if not is_equal_approx(kf.time, 1.0):
		failures.append("key_add should place the key at 1.0, got %s" % kf.time)
	if kf.value != Vector3(2, 0.5, 0):
		failures.append("key_add should fall back to the live object position, got %s" % kf.value)

	# The editor resolves drag indices through the lane model; do the same to
	# fake the flat index the move handler receives.
	var model := TimelineLaneModel.new()
	model.world = lab.world
	model.keyframes = lab.keyframes
	model.frames = lab.frames
	model.timeline = lab.timeline
	model.lighting = lab.lighting
	var idx := model.key_index_at(target_id, 1.0, 0.25)
	if idx != 0:
		failures.append("key_index_at should resolve the fresh key at 1.0, got %d" % idx)

	panel.key_move_requested.emit(idx, 1.0, 2.0)
	if not is_equal_approx(_key_time(lab), 2.0):
		failures.append("key_move should re-time the key to 2.0, got %s" % _key_time(lab))

	# Undo/redo rides the root's top bar into the injected shared history: the
	# move reverses, the redo re-applies, and both refresh the editor.
	var rc_before := ed.get_refresh_count()
	lab.top_bar.undo_requested.emit()
	if not is_equal_approx(_key_time(lab), 1.0):
		failures.append("top-bar undo should reverse the key move back to 1.0, got %s" % _key_time(lab))
	lab.top_bar.redo_requested.emit()
	if not is_equal_approx(_key_time(lab), 2.0):
		failures.append("top-bar redo should re-apply the key move to 2.0, got %s" % _key_time(lab))
	if ed.get_refresh_count() <= rc_before:
		failures.append("undo/redo should refresh the editor (refresh count stuck at %d)" % rc_before)

	# Span ops carry flat-list indices (the editor's marquee resolves them;
	# here they are faked from the single key under test).
	var one: Array[int] = [idx]
	panel.span_slide_requested.emit(one, 0.5)
	if not is_equal_approx(_key_time(lab), 2.5):
		failures.append("span_slide should shift the key to 2.5, got %s" % _key_time(lab))
	panel.span_duplicate_requested.emit(one, 1.0)
	if lab.keyframes.keyframes.size() != 2:
		failures.append("span_duplicate should add a copy (2 keys), got %d" % lab.keyframes.keyframes.size())
	elif not (is_equal_approx(_key_at(lab, 0), 2.5) and is_equal_approx(_key_at(lab, 1), 3.5)):
		failures.append("span_duplicate should land the copy at 3.5 (got %s, %s)" % [_key_at(lab, 0), _key_at(lab, 1)])
	var second: Array[int] = [1]
	panel.keys_remove_requested.emit(second)
	if lab.keyframes.keyframes.size() != 1 or not is_equal_approx(_key_time(lab), 2.5):
		failures.append("keys_remove should drop the duplicate and keep 2.5 (got %d keys at %s)" % [
			lab.keyframes.keyframes.size(), _key_time(lab)])
	return failures


## Time of key `index`, or NAN when the list is that short — keeps failure
## paths reporting instead of crashing on an out-of-range index.
func _key_at(lab: AnimationProductionLab, index: int) -> float:
	if index < 0 or index >= lab.keyframes.keyframes.size():
		return NAN
	return lab.keyframes.keyframes[index].time


func _key_time(lab: AnimationProductionLab) -> float:
	return _key_at(lab, 0)
