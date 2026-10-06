extends Node

## Regression test: snapping must step UNIFORMLY along the drag, not per world axis.
##
## The defect. `apply_move` built the new position and then rounded each world
## component to the grid independently:
##
##     var new_pos := _original_positions[i] + move
##     new_pos = _snap_settings.snap_vector3(new_pos, _snap_settings.position_snap)
##
## On an axis-aligned drag that is invisible, because the only component that
## changes is the one being dragged. Under the Local gizmo frame the move axis of
## any rotated object is DIAGONAL in world space, and then X and Z round
## independently: each advances in its own 0.25 steps, at different moments. The
## object staircases across the drag line instead of walking along it, and the
## sideways error reverses direction repeatedly as the two roundings fall in and
## out of step. That is the reported "the snap function makes the object wiggle".
##
## **45 degrees is the angle that HIDES this, and the first version of this test
## only tried 45** — and passed, against the broken code. At 45 the axis is
## (cos45, 0, -sin45), so X and Z change by equal and opposite amounts and round
## identically, which keeps every sample exactly on the diagonal. At any other yaw
## the two components round independently and the point leaves the line. So the
## test sweeps several angles; 45 is kept only as the case that must NOT regress.
##
## Two further consequences of the same line, both covered below:
##   - grabbing an off-grid object TELEPORTS it, because the very first frame
##     rounds its existing position rather than the travel. Measured:
##     (0.13, 0.07, 0.11) -> (0.25, 0, 0) on the first frame of a sub-step drag;
##   - a multi-selection loses its internal spacing, because each member's
##     already-different original position is rounded separately, so the same
##     displacement produces a different delta per member. Measured 0.7 -> 0.5.
##
## The fix snaps the scalar DISTANCE along the axis, so the displacement is always
## an exact integer multiple of the grid times a unit axis.
##
## Every sub-test that touches a node re-spawns what it needs, and `_done` is
## counted against SUB_TESTS: an engine script error aborts a sub-test without
## raising anything this file can see, so without the count the suite would print
## PASS and exit 0 having asserted almost nothing.

var _fail := 0
var _done := 0
var _lab: ModelingLab

## 30 and 60 are the cases where the two components' rates differ most; 45 is the
## degenerate one described above.
const YAWS: Array[float] = [20.0, 30.0, 45.0, 60.0, 70.0]
const SUB_TESTS := 6
const STEPS := 48


func _ready() -> void:
	var tree := get_tree()
	_lab = (load("res://scenes/modeling_lab/modeling_lab.tscn") as PackedScene).instantiate()
	add_child(_lab)
	tree.create_timer(60.0).timeout.connect(_on_watchdog)
	await tree.process_frame
	await tree.process_frame
	_lab._enter_creative_studio()
	await tree.process_frame

	await _test_snap_keeps_the_object_on_the_drag_line()
	await _test_snap_steps_are_uniform()
	await _test_snap_does_not_teleport_at_press()
	await _test_group_keeps_spacing_under_snap()
	await _test_axis_aligned_snap_still_hits_the_grid()
	await _test_body_drag_snap_is_uniform()

	_finish()


## The core assertion. A snapped drag is a straight line of travel, so every
## sampled position must lie ON the line through the start position along the
## drag axis. Any sideways component at all is the staircase; its magnitude is the
## size of the wiggle.
func _test_snap_keeps_the_object_on_the_drag_line() -> void:
	var worst := 0.0
	var worst_yaw := 0.0
	var total_flips := 0
	var per_yaw := ""
	for yaw in YAWS:
		var maybe_axis: Variant = await _start_diagonal_drag(yaw)
		if maybe_axis == null:
			return
		# Explicitly typed local. The helper is Variant-returning (GDScript cannot
		# return null from a typed Vector3 function) and this project treats a type
		# inferred from a Variant as a parse error.
		var axis: Vector3 = maybe_axis
		var orig: Vector3 = _lab.selection_manager.get_selected().position
		var side := _perpendicular(axis)
		var step := _step()
		var yaw_worst := 0.0
		var flips := 0
		var prev_signed := 0.0
		for i in range(1, STEPS + 1):
			_lab.transform_manager.apply_move(axis, float(i) * step)
			var disp: Vector3 = _lab.selection_manager.get_selected().position - orig
			var perp: Vector3 = disp - axis * disp.dot(axis)
			yaw_worst = maxf(yaw_worst, perp.length())
			# Sign of the sideways offset along one fixed perpendicular. Magnitude
			# alone would also pass for a constant offset; the reversals are the
			# part a hand actually reads as wiggling.
			var signed: float = perp.dot(side)
			if absf(prev_signed) > 1e-9 and absf(signed) > 1e-9 \
					and signf(signed) != signf(prev_signed):
				flips += 1
			if absf(signed) > 1e-9:
				prev_signed = signed
		per_yaw += " %d:%.3f/%d" % [int(yaw), yaw_worst, flips]
		total_flips += flips
		if yaw_worst > worst:
			worst = yaw_worst
			worst_yaw = yaw

	if worst > 1e-4:
		_fail += 1
		print("FAIL: a snapped diagonal drag wandered up to %.4f units off the drag "
			% worst + "line (worst at %d deg yaw) and reversed sideways %d times "
			% [worst_yaw, total_flips] + "across %d sampled drags.%s Rounding the "
			% [YAWS.size(), per_yaw] + "world components independently makes the "
			+ "object staircase across the drag axis instead of walking along it.")
	else:
		_done += 1
		print("      a snapped diagonal drag stays on the drag line at every yaw "
			+ "(%s)" % per_yaw)


## "Uniformly" means every advance is exactly one grid step OF TRAVEL ALONG THE
## AXIS. Irregular advances are the same staircase seen from the other side: the
## object speeds up and stalls in a pattern that has nothing to do with the hand.
## Note this also pins the diagonal projection: rounding components on a
## diagonal advances further than one grid step along the axis, because the
## component step is foreshortened by cos(theta).
func _test_snap_steps_are_uniform() -> void:
	var maybe_axis: Variant = await _start_diagonal_drag(30.0)
	if maybe_axis == null:
		return
	var axis: Vector3 = maybe_axis
	var grid := _grid()
	var orig: Vector3 = _lab.selection_manager.get_selected().position
	var step := _step()
	var last := 0.0
	var irregular := 0
	var advances := 0
	var steps_seen := ""
	for i in range(1, STEPS + 1):
		_lab.transform_manager.apply_move(axis, float(i) * step)
		var disp: Vector3 = _lab.selection_manager.get_selected().position - orig
		var along: float = disp.dot(axis)
		var advance: float = along - last
		if absf(advance) > 1e-4:
			advances += 1
			if absf(absf(advance) - grid) > 1e-4:
				irregular += 1
			if steps_seen.length() < 90:
				steps_seen += "%.3f " % advance
			last = along
	if irregular > 0:
		_fail += 1
		print("FAIL: %d of %d advances were not exactly one %.3f grid step of "
			% [irregular, advances, grid] + "travel along the axis. Observed: %s"
			% steps_seen)
	else:
		_done += 1
		print("      all %d advances are exactly %.3f - uniform" % [advances, grid])


## Pressing the handle must not move the object. Rounding the object's existing
## position moves it on the very first frame, so grabbing something that is not
## already on the grid snaps it out from under the cursor.
func _test_snap_does_not_teleport_at_press() -> void:
	var maybe_axis: Variant = await _start_diagonal_drag(30.0)
	if maybe_axis == null:
		return
	var axis: Vector3 = maybe_axis
	var grid := _grid()
	var cube := _lab.selection_manager.get_selected()
	cube.position = Vector3(0.13, 0.07, 0.11)
	# Re-snapshot so the off-grid start is what the drag is measured from.
	_lab.transform_manager.begin_move(axis)
	var before: Vector3 = cube.position
	_lab.transform_manager.apply_move(axis, grid * 0.1)
	var after: Vector3 = cube.position
	if before.distance_to(after) > 1e-4:
		_fail += 1
		print("FAIL: grabbing an off-grid object moved it %s -> %s (%.4f) on the "
			% [before, after, before.distance_to(after)] + "first frame of a drag "
			+ "shorter than half a grid step. Only the travel may be rounded, "
			+ "never the existing position.")
	else:
		_done += 1
		print("      an off-grid grab does not teleport the object")


## A group must move as one rigid body. Rounding each member's own already
## different position gives each member a different displacement, so the
## selection's internal spacing changes as you drag it.
func _test_group_keeps_spacing_under_snap() -> void:
	_lab.selection_manager.deselect_all()
	_lab._on_spawn_selected(PrimitiveDef.Type.CUBE)
	await get_tree().process_frame
	var a := _lab.selection_manager.get_selected() as MeshInstance3D
	_lab._on_spawn_selected(PrimitiveDef.Type.CUBE)
	await get_tree().process_frame
	var b := _lab.selection_manager.get_selected() as MeshInstance3D
	# Spawning the second object re-selects it, so `a` is carried across explicitly
	# and its validity re-checked: a freed MeshInstance3D throws on property
	# access rather than comparing equal to null.
	if a == null or b == null or not is_instance_valid(a):
		_fail += 1
		print("FAIL: could not produce two live objects for the group snap test")
		return
	a.position = Vector3(0.0, 0.0, 0.0)
	# 0.7 is deliberately not a whole number of grid steps, which is what makes
	# the two members round differently and the defect observable.
	b.position = Vector3(0.7, 0.0, 0.0)
	var pair: Array[MeshInstance3D] = [a, b]
	_lab.selection_manager.select_multi(pair)
	await get_tree().process_frame
	if _lab.selection_manager.selected_count() < 2:
		_fail += 1
		print("FAIL: select_multi held %d object(s), needed 2"
			% _lab.selection_manager.selected_count())
		return
	var before: float = b.position.distance_to(a.position)
	var axis := Vector3.RIGHT
	_lab.transform_manager.begin_move(axis)
	for i in range(1, 13):
		_lab.transform_manager.apply_move(axis, float(i) * _step())
	var after: float = b.position.distance_to(a.position)
	if absf(after - before) > 1e-4:
		_fail += 1
		print("FAIL: dragging a snapped pair changed their spacing %.4f -> %.4f. "
			% [before, after] + "A selection must move as one rigid body.")
	else:
		_done += 1
		print("      a snapped group keeps its spacing exactly (%.4f)" % after)


## The axis-aligned case must be unchanged, or the fix has broken the ordinary
## one. From the origin on a world axis, snapping the distance and snapping the
## component are the same thing, so every position is still a whole number of
## grid steps. This is the no-regression guard for the common case.
func _test_axis_aligned_snap_still_hits_the_grid() -> void:
	_lab.set_gizmo_orientation(0)  # GLOBAL
	_lab.selection_manager.deselect_all()
	_lab._on_spawn_selected(PrimitiveDef.Type.CUBE)
	await get_tree().process_frame
	var cube := _lab.selection_manager.get_selected() as MeshInstance3D
	if cube == null:
		_fail += 1
		print("FAIL: could not spawn a cube")
		return
	cube.rotation_degrees = Vector3.ZERO
	cube.position = Vector3.ZERO
	await get_tree().process_frame
	cube = _lab.selection_manager.get_selected() as MeshInstance3D
	cube.position = Vector3.ZERO
	var grid := _grid()
	var axis := Vector3.RIGHT
	_lab.transform_manager.begin_move(axis)
	var off_grid := 0
	for i in range(1, 25):
		_lab.transform_manager.apply_move(axis, float(i) * _step())
		var x: float = cube.position.x
		if absf(x / grid - roundf(x / grid)) > 1e-4:
			off_grid += 1
	if off_grid > 0:
		_fail += 1
		print("FAIL: %d sampled positions on a plain world-axis drag were not on "
			% off_grid + "the %.3f grid" % grid)
	else:
		_done += 1
		print("      a world-axis drag still lands exactly on the grid")


## The body drag is the other way to move things and it had the same defect: a
## free 2D displacement rounded per component staircases the same way. It gets
## the same rule, so both move paths step uniformly.
func _test_body_drag_snap_is_uniform() -> void:
	_lab.selection_manager.deselect_all()
	_lab._on_spawn_selected(PrimitiveDef.Type.CUBE)
	await get_tree().process_frame
	var cube := _lab.selection_manager.get_selected() as MeshInstance3D
	if cube == null:
		_fail += 1
		print("FAIL: could not spawn a cube")
		return
	cube.position = Vector3(0.0, 0.0, 0.0)
	await get_tree().process_frame
	cube = _lab.selection_manager.get_selected() as MeshInstance3D
	cube.position = Vector3.ZERO
	# A diagonal direction, where component rounding disagrees most.
	var dir := Vector3(0.7071, 0.0, 0.7071).normalized()
	_lab.transform_manager.begin_move(Vector3.ZERO)
	var grid := _grid()
	var step := _step()
	var last := 0.0
	var irregular := 0
	var advances := 0
	var seen := ""
	for i in range(1, STEPS + 1):
		_lab.transform_manager.apply_move_delta(dir * float(i) * step)
		var disp: Vector3 = cube.position
		var along: float = disp.dot(dir)
		var advance: float = along - last
		if absf(advance) > 1e-4:
			advances += 1
			if absf(absf(advance) - grid) > 1e-4:
				irregular += 1
			if seen.length() < 90:
				seen += "%.3f " % advance
			last = along
	if irregular > 0:
		_fail += 1
		print("FAIL: body drag produced %d irregular advances of %d. It must step "
			% [irregular, advances] + "uniformly along the press-to-cursor "
			+ "direction. Observed: %s" % seen)
	else:
		_done += 1
		print("      body drag also steps uniformly (%d advances of %.3f)"
			% [advances, grid])


## Spins up a cube yawed `deg` under the LOCAL gizmo frame, so the X handle is a
## genuine world diagonal, and opens a move gesture on it.
##
## Returns null on failure, after recording it. `Variant` rather than `Vector3`
## because GDScript will not return null from a typed Vector3 function — that is
## a parse error, and a script that fails to parse still exits 0, so a wrong
## signature here would look like a passing run that asserted nothing.
func _start_diagonal_drag(deg: float) -> Variant:
	_lab.selection_manager.deselect_all()
	_lab._on_spawn_selected(PrimitiveDef.Type.CUBE)
	await get_tree().process_frame
	var cube := _lab.selection_manager.get_selected() as MeshInstance3D
	if cube == null:
		_fail += 1
		print("FAIL: could not spawn a cube")
		return null
	_lab.set_gizmo_orientation(1)  # LOCAL: this is what makes the axis diagonal
	cube.rotation_degrees = Vector3(0.0, deg, 0.0)
	cube.position = Vector3.ZERO
	# Writing the rotation re-derives children, so the selection reference has to
	# be taken again or the rest of the sub-test measures a freed node.
	await get_tree().process_frame
	cube = _lab.selection_manager.get_selected() as MeshInstance3D
	if cube == null:
		_fail += 1
		print("FAIL: the cube vanished after being rotated")
		return null
	cube.rotation_degrees = Vector3(0.0, deg, 0.0)
	cube.position = Vector3.ZERO
	# The gizmo frame is derived from the selection's basis AT THE MOMENT it is
	# set, and is only refreshed per frame while a drag is live. This test never
	# sets `_dragging`, so the orientation has to be re-applied after the rotation
	# is in place — applied before it, the frame is identity, the axis comes out
	# world-aligned, and the sub-test quietly stops testing a diagonal at all.
	if _lab.has_method("_apply_gizmo_orientation"):
		_lab._apply_gizmo_orientation()
	var axis: Vector3 = _lab.gizmo.axis_to_world(Vector3.RIGHT)
	if absf(axis.dot(Vector3.RIGHT)) > 0.999:
		_fail += 1
		print("FAIL: the Local gizmo frame produced a world-aligned axis (%s) at "
			% axis + "%d deg, so this sub-test would not exercise a diagonal drag"
			% int(deg))
		return null
	_lab.transform_manager.begin_move(axis)
	return axis


func _perpendicular(axis: Vector3) -> Vector3:
	var seed := Vector3.RIGHT if absf(axis.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	return axis.cross(seed).normalized()


func _grid() -> float:
	return _lab.transform_manager._snap_settings.position_snap


## A fraction of the grid that is never a whole number of steps, so every frame
## forces a fresh rounding decision.
func _step() -> float:
	return _grid() / 8.0


func _finish() -> void:
	if _done < SUB_TESTS:
		_fail += SUB_TESTS - _done
		print("FAIL: only %d of %d sub-tests completed - the rest died on an "
			% [_done, SUB_TESTS] + "unreported engine error, so the run above is "
			+ "NOT a pass")
	if _fail == 0:
		print("PASS: snap steps uniformly along the drag at every yaw, does not "
			+ "teleport on press, keeps group spacing, a world-axis drag still hits "
			+ "the grid, and body drag steps uniformly")
	get_tree().quit(1 if _fail else 0)


func _on_watchdog() -> void:
	print("FAIL: watchdog fired, test did not complete")
	get_tree().quit(2)