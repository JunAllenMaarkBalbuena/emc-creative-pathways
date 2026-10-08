extends Node

## Starter-scene mask test (post-round UX fix): the authored starter nodes
## (StarterBackdrop / StarterCharacter / StarterWorkstation) are scenery that
## sits OUTSIDE the composition registry, so they must never be visible during
## the guided working stages (ASSETS..SUBMIT) — the scene the player sees there
## must be exactly the registered composition the Layers docker, rename,
## reorder, and the STAGING gate operate on. They DO stay visible at the intro
## stages (BRIEF/PLAN — the "here's the lab" look) and in Studio mode (the
## furnished default world).
##
## This encodes the coherence contract behind the round's bug reports
## (rename had nothing to select, Continue was blocked by an already-staged
## but unregistered scene, and the scene order could not mirror a panel that
## listed none of the visible objects).

const LAB := "res://scenes/animation_production_lab/animation_production_lab.tscn"

const STARTER_PATHS := {
	"backdrop": "UI/SceneViewportContainer/SceneViewport/World/BackgroundRoot/StarterBackdrop",
	"character": "UI/SceneViewportContainer/SceneViewport/World/CharacterRoot/StarterCharacter",
	"workstation": "UI/SceneViewportContainer/SceneViewport/World/PropRoot/StarterWorkstation",
}

var lab: AnimationProductionLab


func _ready() -> void:
	var tree := get_tree()
	var failures := await _run()
	if failures.is_empty():
		print("PASS: authored starters hidden during guided working stages, shown at intro + studio")
		tree.quit(0)
	else:
		for f in failures:
			print("FAIL: ", f)
		tree.quit(1)


func _run() -> Array[String]:
	var failures: Array[String] = []
	var tree := get_tree()
	lab = load(LAB).instantiate() as AnimationProductionLab
	lab.autosave_enabled = false
	lab.enable_creative_studio = true
	add_child(lab)
	for i in 3:
		await tree.process_frame

	# The starter nodes must exist in the tree (engine drops orphans silently).
	for key in STARTER_PATHS:
		if _starter(key) == null:
			failures.append("starter %s missing from the tree" % key)

	# Intro stages: visible.
	if not _starters_visible():
		failures.append("starters should be visible at the BRIEF intro")

	# Working stages: hidden — the scene must show only the registered
	# composition. Sweep every stage the guided flow can reach.
	var hidden := []
	for i in lab.STAGE_NAMES.size():
		var stage := i
		if stage == AnimationAssignmentManager.Stage.BRIEF or stage == AnimationAssignmentManager.Stage.PLAN:
			continue
		lab.assignment_manager.go_to(stage)
		await tree.process_frame
		if _starters_visible():
			failures.append("starters must hide at %s" % lab.STAGE_NAMES[stage])
		hidden.append(lab.STAGE_NAMES[stage])
	if hidden.size() != lab.STAGE_NAMES.size() - 2:
		failures.append("stage sweep should cover every working stage")

	# Intro stages still show them after the sweep.
	lab.assignment_manager.go_to(AnimationAssignmentManager.Stage.BRIEF)
	await tree.process_frame
	if not _starters_visible():
		failures.append("starters should re-show at BRIEF")

	# Studio mode shows the furnished lab world again.
	lab.guided_completed = true
	lab.unlock_creative_studio()
	await tree.process_frame
	if lab.mode != AnimationProductionLab.Mode.STUDIO:
		failures.append("studio mode should engage")
	elif not _starters_visible():
		failures.append("starters should be visible in studio mode")

	lab.queue_free()
	return failures


func _starter(key: String) -> Node3D:
	return lab.get_node_or_null(STARTER_PATHS[key]) as Node3D


func _starters_visible() -> bool:
	for key in STARTER_PATHS:
		var n := _starter(key)
		if n != null and not n.visible:
			return false
	return true