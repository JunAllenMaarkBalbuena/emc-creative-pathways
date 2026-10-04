extends Node

## RED guard: multi-select + group transform in the modeling lab.
## User-facing behaviors under test (approved in brainstorming):
##   1. Box/rubber-band select: dragging a rect in the viewport selects every
##      object whose projected center lands inside it.
##   2. Multi-selection state: selected_count(), is_selected(), get_centroid().
##   3. Gizmo pivots to the group centroid when >1 object is selected.
##   4. Group Move / Rotate / Scale transform ALL selected objects, with
##      Rotate and Scale operating about the group centroid.
##   5. Body-drag: clicking any selected member (with >1 selected) moves the
##      whole group by the screen-plane delta WITHOUT collapsing the set.
##   6. Re-click on an already-selected member preserves the multi-set.

var _fail := 0

func _ready() -> void:
	var tree := get_tree()
	var lab: ModelingLab = (load("res://scenes/modeling_lab/modeling_lab.tscn") as PackedScene).instantiate()
	add_child(lab)
	tree.create_timer(30.0).timeout.connect(_on_watchdog)
	await tree.process_frame
	await tree.process_frame
	lab._enter_creative_studio()
	await tree.process_frame

	lab._on_spawn_selected(PrimitiveDef.Type.CUBE)
	lab._on_spawn_selected(PrimitiveDef.Type.CUBE)
	await tree.process_frame

	var cubes: Array[MeshInstance3D] = []
	for child in lab.object_container.get_children():
		if child is MeshInstance3D and not child.is_in_group("ghost_guides"):
			cubes.append(child)
	if cubes.size() != 2:
		_fail += 1
		print("FAIL: expected 2 selectable cubes, got %d" % cubes.size())
		_quit()
		return
	var a: MeshInstance3D = cubes[0]
	var b: MeshInstance3D = cubes[1]
	a.position = Vector3(-1, 0.5, 0)
	b.position = Vector3(1, 0.5, 0)
	await tree.process_frame

	var sm := lab.selection_manager
	var cam: Camera3D = lab.camera_controller.camera
	var tm := lab.transform_manager

	# 1) Box select via the same seam the left-release handler calls.
	#    The two cubes are apart; a rect spanning both screen projections must
	#    select exactly those two.
	var vp_a: Vector2 = cam.unproject_position(a.global_position)
	var vp_b: Vector2 = cam.unproject_position(b.global_position)
	lab._apply_selection_box(vp_a - Vector2(20, 20), vp_b + Vector2(20, 20))
	if sm.selected_count() != 2:
		_fail += 1
		print("FAIL: box select over 2 cubes should select 2, got %d" % sm.selected_count())
	if not sm.is_selected(a) or not sm.is_selected(b):
		_fail += 1
		print("FAIL: box select should include both cubes")

	# 2) Centroid is the average of the selected global positions.
	var expected_centroid: Vector3 = (a.global_position + b.global_position) / 2.0
	var centroid: Vector3 = sm.get_centroid()
	if centroid.distance_to(expected_centroid) > 0.001:
		_fail += 1
		print("FAIL: centroid %s != expected %s" % [centroid, expected_centroid])

	# 3) Gizmo pivots to the group centroid (not to any single member).
	if not lab.gizmo.visible:
		_fail += 1
		print("FAIL: gizmo should be visible with a multi-selection")
	if lab.gizmo.global_position.distance_to(centroid) > 0.01:
		_fail += 1
		print("FAIL: gizmo should sit at the group centroid, got %s, centroid %s"
			% [lab.gizmo.global_position, centroid])

	# 4a) Group MOVE: begin/apply/end moves BOTH cubes by the same delta;
	#     relative spacing between the pair is preserved.
	var a_pos_before: Vector3 = a.position
	var b_pos_before: Vector3 = b.position
	tm.begin_move(Vector3.RIGHT)
	tm.apply_move(Vector3.RIGHT, 1.0)
	tm.end_move()
	await tree.process_frame
	if a.position.distance_to(a_pos_before + Vector3.RIGHT) > 0.01:
		_fail += 1
		print("FAIL: group move should translate cube A by +X from its ORIGINAL %s -> %s"
			% [a_pos_before, a.position])
	if b.position.distance_to(b_pos_before + Vector3.RIGHT) > 0.01:
		_fail += 1
		print("FAIL: group move should translate cube B by +X from its ORIGINAL %s -> %s"
			% [b_pos_before, b.position])

	# 4b) Group ROTATE about the centroid: each member orbits the centroid, so
	#     its distance to the centroid is preserved and its basis changes.
	var centroid_before: Vector3 = sm.get_centroid()
	var dist_a: float = a.global_position.distance_to(centroid_before)
	tm.begin_rotate(Vector3.UP)
	tm.apply_rotate(Vector3.UP, PI / 2.0)
	tm.end_rotate()
	await tree.process_frame
	var dist_a_after: float = a.global_position.distance_to(centroid_before)
	if absf(dist_a_after - dist_a) > 0.01:
		_fail += 1
		print("FAIL: group rotate must orbit members about the centroid; "
			+ "distance to centroid changed %f -> %f" % [dist_a, dist_a_after])
	if a.basis.is_equal_approx(Basis.IDENTITY):
		_fail += 1
		print("FAIL: group rotate should rotate each member's basis")

	# 4c) Group SCALE about the centroid: same factor on every member, position
	#     scaled about the centroid so distance-from-centroid scales.
	var a_scale_before: Vector3 = a.scale
	var dist_before: float = a.global_position.distance_to(centroid_before)
	tm.begin_scale(true)
	tm.apply_scale(Vector3.ZERO, 100.0, true)  # factor = 1 + 100*0.003 = 1.3
	tm.end_scale()
	await tree.process_frame
	var a_scale_after: Vector3 = a.scale
	if not a_scale_after.is_equal_approx(a_scale_before * 1.3):
		_fail += 1
		print("FAIL: group scale should scale every member by the same factor 1.3, got %s" % a_scale_after)
	var dist_after: float = a.global_position.distance_to(centroid_before)
	if absf(dist_after - dist_before * 1.3) > 0.05:
		_fail += 1
		print("FAIL: group scale about centroid should grow distances by 1.3; %f -> %f"
			% [dist_before, dist_after])

	# 4d) Body-drag: clicking a selected member keeps the whole set selected and
	#     moves the group. `select_from_click` on an already-selected member must
	#     NOT collapse the multi-selection (that click starts a drag instead).
	tm.begin_move(Vector3.ZERO)  # reset bookkeeping
	tm.end_move()
	lab._on_tool_selected(ModelingLab.Tool.MOVE)
	# Recompute: rotate/scale above moved cube A; vp_a is stale.
	var vp_now: Vector2 = cam.unproject_position(a.global_position)
	var hit_ok: bool = sm.select_from_click(vp_now, cam)
	if not hit_ok:
		_fail += 1
		print("FAIL: click on a selected member should register as a hit")
	if sm.selected_count() != 2:
		_fail += 1
		print("FAIL: re-click on a member must NOT collapse the multi-set, got %d"
			% sm.selected_count())

	if _fail == 0:
		print("PASS: box select, group centroid gizmo, group move/rotate/scale, body-drag")

	_quit()

func _on_watchdog():
	get_tree().quit(2)

func _quit():
	get_tree().quit(1 if _fail > 0 else 0)