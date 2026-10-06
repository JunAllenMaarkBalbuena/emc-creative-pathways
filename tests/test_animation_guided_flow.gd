extends Node

## Task 14: end-to-end guided run, driven through the controllers (no UI
## clicks). Completes the level through LevelProgression, so the harness
## backs up user://level_progression.json before running and restores it
## after — same pattern as test_programming_lab.gd.
##
## Run 1 does everything measurable. Run 2 does nothing and must be
## refused by submission with no score and no Creative Studio unlock.

const LAB := "res://scenes/animation_production_lab/animation_production_lab.tscn"
const ASSIGN := "res://data/assignments/animation/day_in_emc_lab.tres"
const SAVE_GUIDED := "user://animation_lab/guided.tres"

var _failures: Array[String] = []


func _ready() -> void:
	var tree := get_tree()
	var backup := _backup_progress_file()
	var guided_backup := _backup_guided_file()
	_failures = await _run()
	_restore_progress_file(backup)
	_restore_guided_file(guided_backup)
	if _failures.is_empty():
		print("PASS: guided flow gates submission, scores, completes level, unlocks studio")
		tree.quit(0)
	else:
		for f in _failures:
			print("FAIL: ", f)
		tree.quit(1)


func _run() -> Array[String]:
	var failures: Array[String] = []
	var tree := get_tree()

	# --- Run 1: everything measured, done through the controllers ----------
	var lab := load(LAB).instantiate() as AnimationProductionLab
	add_child(lab)
	await tree.process_frame

	if not lab.assignment_manager.load_assignment(ASSIGN):
		failures.append("assignment should load")

	# Challenge A — story beats in the assignment order.
	var beats := lab.assignment_manager.assignment.story_beats.duplicate()
	beats.sort_custom(_by_story_order)
	var ids: Array[String] = []
	for b in beats:
		ids.append(str(b.get("id", "")))
	if not lab.assignment_manager.order_story_beats(ids):
		failures.append("story beats accepted in correct order")

	# Challenge E — scene staged: character + background + prop, character in
	# front, prop near the action.
	var char_id := lab.world.add_asset(_make_asset("character"), Vector3(0, 0.5, 0))
	lab.world.add_asset(_make_asset("background"), Vector3(0, 1, -6))
	lab.world.add_asset(_make_asset("prop"), Vector3(1.2, 0.45, 0))
	if not lab.assignment_manager.stage_scene_ok(true, true):
		failures.append("staging challenge should pass")

	# Challenge B — at least min_frames, with the correct missing frame.
	var assign := lab.assignment_manager.assignment
	var correct_tex := load(assign.correct_frame_path) as Texture2D
	var other_path := assign.candidate_frame_paths[0]
	if other_path == assign.correct_frame_path and assign.candidate_frame_paths.size() > 1:
		other_path = assign.candidate_frame_paths[1]
	var other_tex := load(other_path) as Texture2D
	lab.frames.add_frame(correct_tex, 0.1)
	lab.frames.add_frame(other_tex, 0.1)
	lab.frames.add_frame(other_tex, 0.1)
	if not lab.assignment_manager.missing_frame_ok(correct_tex):
		failures.append("missing-frame challenge should pass")

	# Challenge F — movement keyframe lands before the pose change.
	lab.keyframes.add_keyframe(0.0, char_id, KeyframeController.TARGET_OBJECT, "position", Vector3(0, 0.5, 0))
	lab.keyframes.add_keyframe(0.8, char_id, KeyframeController.TARGET_OBJECT, "visible", true)

	# Timing on target.
	lab.timeline.set_fps(12)
	lab.timeline.set_duration(5.0)

	# Completing must really fire, so clear this level from the live state.
	_reset_progression()

	lab.assignment_manager.go_to(AnimationAssignmentManager.Stage.SUBMIT)
	lab.on_submit_pressed()
	await tree.process_frame

	if lab.last_score == null:
		failures.append("submit should produce a score")
	else:
		var score := lab.last_score as AnimationScoreData
		if score.total_score < 90.0:
			failures.append("total score should be >= 90, got %.1f" % score.total_score)
	if not lab.score_panel.visible:
		failures.append("ScorePanel should be visible after submit")
	if not lab.guided_completed:
		failures.append("guided_completed should be true after submit")
	if not LevelProgression.is_level_completed("animation_production_lab"):
		failures.append("level should be completed after submit")
	lab.unlock_creative_studio()
	if lab.mode != AnimationProductionLab.Mode.STUDIO:
		failures.append("studio mode should unlock after guided completion")
	lab.queue_free()
	await tree.process_frame

	# --- Run 2: nothing done — submit refuses, no score, no unlock ---------
	# Boot as a fresh player: run 1 persisted its completed flag to
	# guided.tres, and the studio gate boots from that file (spec §15). The
	# end-of-test restore puts the developer's original file back.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_GUIDED))
	var lab2 := load(LAB).instantiate() as AnimationProductionLab
	add_child(lab2)
	await tree.process_frame
	lab2.assignment_manager.go_to(AnimationAssignmentManager.Stage.SUBMIT)
	lab2.on_submit_pressed()
	await tree.process_frame
	if lab2.guided_completed:
		failures.append("empty run must not complete the guided flow")
	if lab2.last_score != null:
		failures.append("empty run must not produce a score")
	if lab2.score_panel.visible:
		failures.append("ScorePanel must not show on a refused submit")
	lab2.unlock_creative_studio()
	if lab2.mode != AnimationProductionLab.Mode.GUIDED:
		failures.append("studio must stay locked without guided completion")
	lab2.queue_free()
	await tree.process_frame
	return failures


func _by_story_order(a: Dictionary, b: Dictionary) -> bool:
	return int(a.get("order", 0)) < int(b.get("order", 0))


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


func _reset_progression() -> void:
	LevelProgression._completed.erase("animation_production_lab")
	LevelProgression._unlocked.erase("animation_production_lab")


func _backup_progress_file() -> String:
	var path := "user://level_progression.json"
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


func _restore_progress_file(backup: String) -> void:
	var path := "user://level_progression.json"
	if backup.is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(backup)


## Task 16: the completed guided flag is persisted to guided.tres on submit,
## and the studio boot-reads it — so run 2 must not see run 1's completion.
func _backup_guided_file() -> String:
	if not FileAccess.file_exists(SAVE_GUIDED):
		return ""
	return FileAccess.get_file_as_string(SAVE_GUIDED)


func _restore_guided_file(backup: String) -> void:
	if backup.is_empty():
		if FileAccess.file_exists(SAVE_GUIDED):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_GUIDED))
		return
	var f := FileAccess.open(SAVE_GUIDED, FileAccess.WRITE)
	if f != null:
		f.store_string(backup)