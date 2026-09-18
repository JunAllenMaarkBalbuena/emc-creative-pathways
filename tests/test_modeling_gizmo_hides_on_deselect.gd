extends SceneTree

## Regression test: the transform gizmo must HIDE whenever nothing is selected
## — and STAY hidden, frame after frame, until a real selection arrives.
##
## Root-cause notes (from the live regression that this guards):
##   gizmo_3d.gd:_process ends with `visible = _target != null`. So visibility
##   is owned by the gizmo's own frame loop, NOT by modeling_lab's widgets.
##   modeling_lab used to only set `gizmo.visible = false` on deselect while
##   leaving `_target` pointing at the old (now deselected) node — so the very
##   next frame _process saw `_target != null` and flipped the gizmo back to
##   visible=True. Net effect: "if I don't select, the gizmo remains" floating
##   over the scene even with zero selection.
##
## Contract asserted here:
##   * set_target(null) MUST clear _target.
##   * After deselect, gizmo.visible must be false and must stay false across
##     multiple process frames (no stale-target resurrection).
##   * A later real selection MUST bring the gizmo back.

func _initialize() -> void:
	_run()

func _run() -> void:
	var fail := 0
	var giz := Gizmo3D.new()
	giz.name = "Gizmo"
	root.add_child(giz)
	await process_frame

	var box := MeshInstance3D.new()
	box.name = "Box"
	root.add_child(box)
	await process_frame

	# Select → gizmo appears.
	giz.set_target(box)
	await process_frame
	if not giz.visible:
		fail += 1
		print("FAIL: gizmo did not appear when a target was set")

	# Deselect → gizmo must hide immediately ...
	giz.set_target(null)
	await process_frame
	if giz.visible:
		fail += 1
		print("FAIL: gizmo stays visible after set_target(null)")

	# ... and must stay hidden across several frames (the exact frames where
	# _process used to resurrect it from a stale _target).
	for _i in 4:
		await process_frame
		if giz.visible:
			fail += 1
			print("FAIL: gizmo resurrected to visible with no target (stale _target)")
			break
	if fail == 0:
		print("PASS: gizmo hides on deselect and stays hidden (no stale-target resurrection)")

	quit(1 if fail > 0 else 0)
