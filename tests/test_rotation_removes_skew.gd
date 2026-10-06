extends Node

## Regression test: editing a rotation field removes the shear, as a deliberate
## side effect of the edit - the behaviour that shipped before 5p and that the
## user chose to restore (see docs/audit-2026-10-05.md section 5q).
##
## The contract:
##   - a rotation edit rebuilds the basis as `R * S`, so the skew is gone on the
##     first rotation after an object is sheared
##   - the Local Scale row (column lengths) does not move - what you are reading
##     stays the number you typed
##   - the object's volume becomes the product of those column lengths - the
##     Hadamard gap. Whenever there is shear that product EXCEEDS the true
##     determinant, so the object grows (measured: 2.0000 -> 2.7356, +37%), and
##     the growth is intended, happens exactly once, then holds.
##   - what is deliberately NOT restored: the old World row's ratchet to 135.7%
##     of the original volume over three edits. That was caused by rebuilding
##     with ROW lengths; column lengths are idempotent, because the column
##     lengths of `R * diag(cols)` are `cols` again.
##
## The pre-5p alternative had growth AND a compounding ratchet. The restored
## behaviour has growth and no ratchet. The growth itself is a consequence of
## doing what the user asked: flattening a sheared basis by its own column
## lengths cannot preserve volume (Hadamard's inequality), so asserting the
## exact product is what locks the intended behaviour in - a future change that
## "helpfully" preserves volume would silently change this contract.
##
## 5r (docs/decisions/2026-10-06-skew-toggle.md) re-scopes the contract: shear
## creation now auto-enables the inspector's Skew switch, and while the switch is
## ON a rotation edit PRESERVES the shear. "Rotating flattens" therefore applies
## to sheared objects whose switch is OFF - legacy loads and explicit opt-outs -
## which is what `_sheared()` returns. The switch's own behaviour is locked by
## tests/test_skew_toggle.gd.

var _fail := 0
var _done := 0
var _lab: ModelingLab

const SUB_TESTS := 7

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

	await _test_local_rotation_removes_shear()
	await _test_local_rotation_leaves_the_scale_row_alone()
	await _test_local_rotation_reads_back_what_was_typed()
	await _test_local_rotation_growth_is_the_column_length_product()
	await _test_world_rotation_removes_shear_and_keeps_the_scale_row()
	await _test_repeated_edits_settle_after_the_first()
	await _test_a_clean_object_is_unchanged()

	_finish()


func _settle(n := 3) -> void:
	for _i in n:
		await get_tree().process_frame


# ── sub-tests ─────────────────────────────────────────────────────

func _test_local_rotation_removes_shear() -> void:
	if not await _ready_or_fail():
		return
	var obj := await _sheared()
	if obj == null:
		return
	# Read BEFORE the edit: the handler mutates the live node, so a cached
	# reference read after the call reports the post-edit basis.
	var shear_before := _shear(obj.basis)
	_lab._on_inspector_rot_changed(45.0, "x")
	await _settle()
	var after := _sel()
	if after == null:
		return
	var shear_after := _shear(after.basis)
	if shear_after > REL_EPS:
		_fail += 1
		print("FAIL: a Local rotation edit left the skew in place: max column dot %.4f"
			% shear_after)
		print("      The feature is: rotating flattens the shear. The delta kept it.")
		return
	_done += 1
	print("      Local rotation removes the shear (%.4f -> %.4f)"
		% [shear_before, shear_after])


func _test_local_rotation_leaves_the_scale_row_alone() -> void:
	if not await _ready_or_fail():
		return
	var obj := await _sheared()
	if obj == null:
		return
	var cols_before := _lab._effective_axis_lengths(obj.basis)
	_lab._on_inspector_rot_changed(45.0, "x")
	await _settle()
	var after := _sel()
	if after == null:
		return
	var cols_after := _lab._effective_axis_lengths(after.basis)
	if not _approx_eq(cols_before, cols_after):
		_fail += 1
		print("FAIL: a Local rotation edit changed the Scale row from %s to %s"
			% [_v(cols_before), _v(cols_after)])
		return
	_done += 1
	print("      Local rotation leaves the Scale row at %s" % _v(cols_after))


func _test_local_rotation_reads_back_what_was_typed() -> void:
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
		print("FAIL: typed 45 into Rotation X and it reads back %.3f" % got)
		return
	var field := _lab.get_node_or_null("%RotX") as SpinBox
	if field == null or absf(field.value - 45.0) > QUANT:
		_fail += 1
		print("FAIL: the Rotation X field shows %s after typing 45"
			% (str(field.value) if field != null else "<missing>"))
		return
	_done += 1
	print("      typed 45 reads back %.3f in the field and the helper" % got)


## The Hadamard identity this whole design rests on: flattening a basis by its
## own column lengths sets the volume to the product of those lengths, which
## exceeds the true determinant whenever there is shear. Locking the exact
## product is what keeps the growth from being "fixed" away by a future change.
func _test_local_rotation_growth_is_the_column_length_product() -> void:
	if not await _ready_or_fail():
		return
	var obj := await _sheared()
	if obj == null:
		return
	var cols := _lab._effective_axis_lengths(obj.basis)
	var product: float = cols.x * cols.y * cols.z
	var v_before := absf(obj.basis.determinant())
	_lab._on_inspector_rot_changed(45.0, "x")
	await _settle()
	var after := _sel()
	if after == null:
		return
	var v_after := absf(after.basis.determinant())
	if absf(v_after - product) > REL_EPS * product:
		_fail += 1
		print("FAIL: after flattening, |det| is %.4f but the column length product is %.4f"
			% [v_after, product])
		print("      |det| was %.4f before the edit. Flattening by column lengths" % v_before)
		print("      must land on their product - growth is the intended contract.")
		return
	_done += 1
	print("      flattening lands on the column product: |det| %.4f -> %.4f == %.4f"
		% [v_before, v_after, product])


func _test_world_rotation_removes_shear_and_keeps_the_scale_row() -> void:
	if not await _ready_or_fail():
		return
	var obj := await _sheared()
	if obj == null:
		return
	var cols_before := _lab._effective_axis_lengths(obj.basis)
	_lab._on_inspector_world_rot_changed(45.0, "x")
	await _settle()
	var after := _sel()
	if after == null:
		return
	if _shear(after.basis) > REL_EPS:
		_fail += 1
		print("FAIL: a World rotation edit left the skew in place: max column dot %.4f"
			% _shear(after.basis))
		return
	# The second property, checked on purpose: the pre-5p World row rewrote the
	# LOCAL Scale row to (2, 1, 1). Both rows flatten with column lengths now,
	# so this must not happen. Rotating is allowed to grow the object once; it
	# is not allowed to move the Scale numbers.
	var cols_after := _lab._effective_axis_lengths(after.basis)
	if not _approx_eq(cols_before, cols_after):
		_fail += 1
		print("FAIL: a World rotation edit changed the Scale row from %s to %s"
			% [_v(cols_before), _v(cols_after)])
		return
	_done += 1
	print("      World rotation removes shear and keeps the Scale row %s"
		% _v(cols_after))


## Growth happens exactly once: the first rotation after shearing grows the
## object to the column product, and every edit after that is idempotent. This
## is what distinguishes the restored feature from the old ratchet (135.7% over
## three World edits under row-length rebuilds).
func _test_repeated_edits_settle_after_the_first() -> void:
	if not await _ready_or_fail():
		return
	var obj := await _sheared()
	if obj == null:
		return
	var cols := _lab._effective_axis_lengths(obj.basis)
	var product: float = cols.x * cols.y * cols.z
	var first: Vector3 = Vector3.ZERO
	var volume := -1.0
	for i in 5:
		_lab._on_inspector_rot_changed(45.0, "x")
		await _settle()
		var cur := _sel()
		if cur == null:
			return
		var r := _lab._read_rotation_degrees(cur.basis)
		var v := absf(cur.basis.determinant())
		if i == 0:
			first = r
			volume = v
			continue
		if not _approx_eq(first, r):
			_fail += 1
			print("FAIL: edit %d read %s where the first read %s - it ratchets"
				% [i + 1, _v(r), _v(first)])
			return
		if absf(v - volume) > REL_EPS * volume:
			_fail += 1
			print("FAIL: |det| drifted from %.4f to %.4f after the first flattening"
				% [volume, v])
			return
		if _shear(cur.basis) > REL_EPS:
			_fail += 1
			print("FAIL: shear %.4f reappeared on edit %d" % [_shear(cur.basis), i + 1])
			return
	if absf(volume - product) > REL_EPS * product:
		_fail += 1
		print("FAIL: the first edit landed on |det| %.4f but the column product is %.4f"
			% [volume, product])
		return
	_done += 1
	print("      5 edits: grows once to %.4f, then holds; shear and readback stable"
		% volume)


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
	var cols := _lab._effective_axis_lengths(b)
	if not _approx_eq(cols, Vector3.ONE):
		_fail += 1
		print("FAIL: a rotation edit on a clean unit cube left Scale %s" % _v(cols))
		return
	_done += 1
	print("      a clean object stays clean (shear %.4f, scale %s)"
		% [_shear(b), _v(cols)])


# ── helpers ───────────────────────────────────────────────────────

## Spawns a cube, rotates it through the panel, then stretches it along a WORLD
## axis through the panel - which is the only way this game creates shear, and
## exactly what the Global gizmo orientation does. Driving the real handlers
## rather than assigning `obj.basis` by hand means the test exercises the paths a
## user actually reaches.
##
## Returns null after incrementing `_fail`, so a dependent sub-test bails rather
## than crashing partway and being counted as a pass. Typed `-> Node3D` so the
## `:= await _sheared()` call sites infer a concrete type (this project treats
## inference from `Variant` as a parse error).
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
		print("      so this sub-test is not exercising the feature")
		return null
	# 5r (docs/decisions/2026-10-06-skew-toggle.md): the world-scale that just
	# sheared the object AUTO-ENABLES the Skew switch, and while the switch is on
	# a rotation edit PRESERVES the shear. This suite locks the 5q contract, which
	# after 5r applies to sheared objects whose switch is OFF (legacy saves,
	# explicit opt-out). Step the object back to that state before returning it.
	out.set_meta(&"skew_enabled", false)
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


## Max absolute difference between two column-normalised basis dot products -
## the same measure `_is_sheared` thresholds at 1e-5, but continuous so drift and
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
	return "%.3f, %.3f, %.3f" % [v.x, v.y, v.z]


func _finish() -> void:
	if _done < SUB_TESTS:
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
		print("PASS: editing a rotation field removes the skew as a side effect - "
			+ "the Scale row stays put, growth lands exactly on the column length "
			+ "product once and then holds, and clean objects are untouched")
	get_tree().quit(1 if _fail else 0)