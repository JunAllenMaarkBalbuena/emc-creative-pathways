extends Node

## Regression test: editing a rotation must not destroy the shear, inflate the
## object, or rewrite the Scale row.
##
## The defect. Both rotation handlers REBUILT the basis as `R * S` from an euler
## and a vector of lengths. On a sheared basis that reconstruction has no inverse:
##
##   shear  0.5612 -> 0.0000      <- "removes the skew", which ShearWarning admits
##   |det|  2.0000 -> 2.7356      <- the object inflates 37%, ADMITTED NOWHERE
##
## The volume is the one nobody disclosed. `_effective_axis_lengths` returns the
## basis's COLUMN lengths, and for a sheared basis their product is NOT the
## determinant - so the rebuild swapped in a volume that was never there. The
## World rotation row is worse: its first edit silently rewrites the Scale row
## from (1.497, 1.200, 1.523) to (2, 1, 1), and a second edit inflates volume
## another 20%.
##
## The fix replaces the rebuild with a rotation DELTA:
##
##     B_new = R_new * R_old^-1 * B_old,   R_old = basis.orthonormalized()
##
## Left-multiplying by a rotation is rigid, and a rigid map does three things at
## once: it preserves every pairwise column dot (so shear survives), it has
## determinant 1 (so volume survives), and it commutes with `orthonormalized()`
## (so what you typed reads back exactly).
##
## The no-regression argument, which sub-test 8 locks down: for a CLEAN basis
## `B = R * S`, so `R_old^-1 * B_old = S` and the delta collapses to exactly the
## old `R_new * S`. Clean objects are unchanged; only sheared ones are affected.
##
## This also executes a RECORDED decision rather than making a new one. See
## docs/decisions/2026-10-05-gizmo-orientation.md:
##   | Global scale of a rotated object | Keep true shear (basis = S*R) |
## The rotation write path was silently violating that row every time it fired.

var _fail := 0
var _done := 0
var _lab: ModelingLab

const SUB_TESTS := 8

## Float32 residue on basis round-trips is ~2e-7, so anything above 1e-2 in a
## degree means a real disagreement rather than rounding.
const ANGLE_EPS := 0.01
## The SpinBoxes quantise at 0.01, so a widget round-trip cannot beat 0.005.
const QUANT := 0.006
## For quantity ratios - volume, length, shear - a relative test is the only one
## that means the same thing at every object size.
const REL_EPS := 0.001


func _ready() -> void:
	_lab = (load("res://scenes/modeling_lab/modeling_lab.tscn") as PackedScene).instantiate()
	add_child(_lab)
	await _settle()
	_lab._enter_creative_studio()
	await _settle()

	await _test_local_rotation_edit_preserves_shear()
	await _test_local_rotation_edit_preserves_volume()
	await _test_local_rotation_edit_reads_back_what_was_typed()
	await _test_local_rotation_edit_leaves_the_scale_row_alone()
	await _test_world_rotation_edit_preserves_shear_and_scale_row()
	await _test_world_rotation_edit_preserves_volume_across_edits()
	await _test_repeated_local_edits_do_not_drift()
	await _test_a_clean_object_is_unchanged()

	_finish()


func _settle(n := 3) -> void:
	for _i in n:
		await get_tree().process_frame


# ── sub-tests ─────────────────────────────────────────────────────

func _test_local_rotation_edit_preserves_shear() -> void:
	if not await _ready_or_fail():
		return
	var before := await _sheared()
	if before == null:
		return
	var shear_before := _shear(before.basis)
	_lab._on_inspector_rot_changed(45.0, "x")
	await _settle()
	var after := _sel()
	if after == null:
		return
	var shear_after := _shear(after.basis)
	if absf(shear_after - shear_before) > REL_EPS:
		_fail += 1
		print("FAIL: a Local rotation edit destroyed the shear: max column dot %.4f -> %.4f"
			% [shear_before, shear_after])
		print("      ShearWarning disclosed this, but the decision record says")
		print("      'keep true shear', so the write path was contradicting it.")
		return
	_done += 1
	print("      Local rotation keeps the shear (%.4f -> %.4f)"
		% [shear_before, shear_after])


func _test_local_rotation_edit_preserves_volume() -> void:
	if not await _ready_or_fail():
		return
	var before := await _sheared()
	if before == null:
		return
	var v_before := absf(before.basis.determinant())
	_lab._on_inspector_rot_changed(45.0, "x")
	await _settle()
	var after := _sel()
	if after == null:
		return
	var v_after := absf(after.basis.determinant())
	var ratio: float = v_after / maxf(v_before, 1e-6)
	if absf(ratio - 1.0) > REL_EPS:
		_fail += 1
		print("FAIL: one Local rotation edit changed the object's volume by %.1f%%"
			% [(ratio - 1.0) * 100.0])
		print("      |det| %.4f -> %.4f. A rotation cannot do this: the rebuild swapped"
			% [v_before, v_after])
		print("      the sheared basis's true volume for the product of its column")
		print("      lengths, which is a different number.")
		return
	_done += 1
	print("      Local rotation keeps the volume (%.4f -> %.4f)"
		% [v_before, v_after])


func _test_local_rotation_edit_reads_back_what_was_typed() -> void:
	if not await _ready_or_fail():
		return
	var obj := await _sheared()
	if obj == null:
		return
	_lab._on_inspector_rot_changed(45.0, "x")
	await _settle()
	var after := _sel()
	if after == null:
		return
	var got: float = _lab._read_rotation_degrees(after.basis).x
	if absf(got - 45.0) > ANGLE_EPS:
		_fail += 1
		print("FAIL: typed 45 into Rotation X on a sheared object and it reads back %.3f"
			% got)
		return
	# And the widget must agree with the helper, or the panel would report one
	# quantity and apply another.
	var field := _lab.get_node_or_null("%RotX") as SpinBox
	if field == null or absf(field.value - 45.0) > QUANT:
		_fail += 1
		print("FAIL: the Rotation X field shows %s after typing 45"
			% (str(field.value) if field != null else "<missing>"))
		return
	_done += 1
	print("      typed 45 reads back %.3f in the field and the helper" % got)


func _test_local_rotation_edit_leaves_the_scale_row_alone() -> void:
	if not await _ready_or_fail():
		return
	var before := await _sheared()
	if before == null:
		return
	var lengths_before := _lab._effective_axis_lengths(before.basis)
	_lab._on_inspector_rot_changed(45.0, "x")
	await _settle()
	var after := _sel()
	if after == null:
		return
	var lengths_after := _lab._effective_axis_lengths(after.basis)
	if not _approx_eq(lengths_before, lengths_after):
		_fail += 1
		print("FAIL: a Local rotation edit changed the Scale row from %s to %s"
			% [_v(lengths_before), _v(lengths_after)])
		return
	_done += 1
	print("      Local rotation leaves the Scale row at %s"
		% _v(lengths_after))


func _test_world_rotation_edit_preserves_shear_and_scale_row() -> void:
	if not await _ready_or_fail():
		return
	var before := await _sheared()
	if before == null:
		return
	var shear_before := _shear(before.basis)
	var lengths_before := _lab._effective_axis_lengths(before.basis)
	_lab._on_inspector_world_rot_changed(45.0, "x")
	await _settle()
	var after := _sel()
	if after == null:
		return
	var shear_after := _shear(after.basis)
	var lengths_after := _lab._effective_axis_lengths(after.basis)
	if absf(shear_after - shear_before) > REL_EPS:
		_fail += 1
		print("FAIL: a World rotation edit destroyed the shear: max column dot %.4f -> %.4f"
			% [shear_before, shear_after])
		return
	# The second property, checked on purpose: this row's first edit used to
	# rewrite the LOCAL Scale row to (2, 1, 1), so two rows silently disagreed
	# about an object the user only rotated.
	if not _approx_eq(lengths_before, lengths_after):
		_fail += 1
		print("FAIL: a World rotation edit silently rewrote the Scale row from %s to %s"
			% [_v(lengths_before), _v(lengths_after)])
		return
	_done += 1
	print("      World rotation keeps shear %.4f and the Scale row %s"
		% [shear_after, _v(lengths_after)])


func _test_world_rotation_edit_preserves_volume_across_edits() -> void:
	if not await _ready_or_fail():
		return
	var obj := await _sheared()
	if obj == null:
		return
	var v_before := absf(obj.basis.determinant())
	var worst := 1.0
	for i in 3:
		_lab._on_inspector_world_rot_changed(45.0 + 15.0 * i, "x")
		await _settle()
		var cur := _sel()
		if cur == null:
			return
		worst = maxf(worst, absf(cur.basis.determinant()) / maxf(v_before, 1e-6))
	if absf(worst - 1.0) > REL_EPS:
		_fail += 1
		print("FAIL: three World rotation edits drove the volume to %.1f%% of the original"
			% (worst * 100.0))
		print("      |det| started at %.4f. Rotating is rigid and cannot change volume."
			% v_before)
		return
	_done += 1
	print("      three World rotation edits hold the volume at %.1f%% of the original"
		% (worst * 100.0))


func _test_repeated_local_edits_do_not_drift() -> void:
	if not await _ready_or_fail():
		return
	var obj := await _sheared()
	if obj == null:
		return
	var shear_before := _shear(obj.basis)
	var v_before := absf(obj.basis.determinant())
	var first: Vector3 = Vector3.ZERO
	for i in 5:
		_lab._on_inspector_rot_changed(45.0, "x")
		await _settle()
		var cur := _sel()
		if cur == null:
			return
		var r := _lab._read_rotation_degrees(cur.basis)
		if i == 0:
			first = r
		elif not _approx_eq(first, r):
			_fail += 1
			print("FAIL: edit %d read %s where the first read %s - it ratchets"
				% [i + 1, _v(r), _v(first)])
			return
		if absf(_shear(cur.basis) - shear_before) > REL_EPS:
			_fail += 1
			print("FAIL: shear drifted from %.4f to %.4f over 5 edits"
				% [shear_before, _shear(cur.basis)])
			return
		if absf(absf(cur.basis.determinant()) - v_before) > REL_EPS * v_before:
			_fail += 1
			print("FAIL: volume drifted from %.4f to %.4f over 5 edits"
				% [v_before, absf(cur.basis.determinant())])
			return
	_done += 1
	print("      5 repeated edits settle with shear and volume unchanged")


## The no-regression guard for the fix's central claim: a clean object must come
## out of a rotation edit exactly as it did before the change - still clean, still
## its original scale, same volume - because for B = R*S the delta collapses to
## the old `R_new * S`.
func _test_a_clean_object_is_unchanged() -> void:
	if not await _ready_or_fail():
		return
	_lab.selection_manager.deselect_all()
	_lab._on_spawn_selected(PrimitiveDef.Type.CUBE)
	await _settle()
	var obj := _sel()
	if obj == null:
		return
	_lab._on_inspector_rot_changed(30.0, "x")
	await _settle()
	obj = _sel()
	if obj == null:
		return
	_lab._on_inspector_rot_changed(50.0, "y")
	await _settle()
	var after := _sel()
	if after == null:
		return
	var b := after.basis
	if _shear(b) > REL_EPS:
		_fail += 1
		print("FAIL: a rotation edit on a CLEAN object introduced shear %.4f"
			% _shear(b))
		return
	if absf(absf(b.determinant()) - 1.0) > REL_EPS:
		_fail += 1
		print("FAIL: a rotation edit on a clean object changed its volume to %.4f"
			% absf(b.determinant()))
		return
	var lens := _lab._effective_axis_lengths(b)
	if not _approx_eq(lens, Vector3.ONE):
		_fail += 1
		print("FAIL: a rotation edit on a clean unit cube left Scale %s"
			% _v(lens))
		return
	_done += 1
	print("      a clean object stays clean (shear %.4f, scale %s)"
		% [_shear(b), _v(lens)])


# ── helpers ───────────────────────────────────────────────────────

## Spawns a cube, rotates it through the panel, then stretches it along a WORLD
## axis through the panel - which is the only way this game creates shear, and
## exactly what the Global gizmo orientation does. Driving the real handlers
## rather than assigning `obj.basis` by hand means the test exercises the paths a
## user actually reaches.
##
## Returns null after incrementing `_fail`, so a dependent sub-test bails rather
## than crashing partway and being counted as a pass.
##
## Typed `-> Node3D` rather than left unannotated: `:= await _sheared()` would
## then infer from `Variant`, and this project treats that as a parse error.
func _sheared() -> Node3D:
	_lab.selection_manager.deselect_all()
	_lab._on_spawn_selected(PrimitiveDef.Type.CUBE)
	await _settle()
	var obj := _sel()
	if obj == null:
		return null
	_lab._on_inspector_rot_changed(30.0, "x")
	await _settle()
	_lab._on_inspector_rot_changed(50.0, "y")
	await _settle()
	_lab._on_inspector_world_scale_changed(2.0, "x")
	await _settle()
	var out := _sel()
	if out == null:
		return null
	if not _lab._is_sheared(out.basis):
		_fail += 1
		print("FAIL: setup failed - rotate + world-scale did not shear the object,")
		print("      so this sub-test is not exercising the broken path")
		return null
	return out


## Re-fetched every time because `CommandFactory.transform` can destroy and
## rebuild the object graph on a commit, so a cached Node3D may be dangling.
func _sel() -> Node3D:
	return _lab.selection_manager.get_selected() as Node3D


func _ready_or_fail() -> bool:
	if _lab == null or _lab.selection_manager == null:
		_fail += 1
		print("FAIL: the lab did not come up")
		return false
	return true


## The same measure `_is_sheared` thresholds at 1e-5, but continuous so drift and
## near-misses are visible instead of collapsing to a bool.
func _shear(b: Basis) -> float:
	var x := b[0].normalized()
	var y := b[1].normalized()
	var z := b[2].normalized()
	return maxf(absf(x.dot(y)), maxf(absf(x.dot(z)), absf(y.dot(z))))


func _approx_eq(a: Vector3, b: Vector3) -> bool:
	return absf(a.x - b.x) < REL_EPS and absf(a.y - b.y) < REL_EPS \
			and absf(a.z - b.z) < REL_EPS


func _v(v: Vector3) -> String:
	return "(%.3f, %.3f, %.3f)" % [v.x, v.y, v.z]


func _finish() -> void:
	if _done < SUB_TESTS:
		# Counted so a sub-test that dies mid-way cannot be reported as a pass -
		# which is the whole point of this check. But a sub-test that FAILED is a
		# completed run, not a dead one, so the two are told apart before saying
		# anything about engine errors. Claiming a crash that never happened would
		# send someone hunting for one.
		var deficit := SUB_TESTS - _done
		_fail += deficit
		if _fail == deficit:
			print("FAIL: only %d of %d sub-tests completed - the rest died on an "
				% [_done, SUB_TESTS] + "unreported engine error, so the run above "
				+ "is NOT a pass")
		else:
			print("FAIL: %d of %d sub-tests passed - see the failures above"
				% [_done, SUB_TESTS])
	if _fail == 0:
		print("PASS: rotating a sheared object now preserves its shear, its volume "
			+ "and its Scale row, reads back exactly what was typed, does not drift "
			+ "over repeated edits, and leaves clean objects untouched")
	get_tree().quit(1 if _fail else 0)
