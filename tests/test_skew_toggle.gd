extends Node

## Regression test: the inspector's Skew switch (5s contract, which revises 5r
## per user clarification - see docs/decisions/2026-10-06-skew-toggle.md).
##
## The contract:
##   - the switch is ALWAYS visible for a selected object, sheared or clean, and
##     pressed exactly when the per-object skew flag is on
##   - the switch is default OFF, and OFF means keep-clean: nothing the user does
##     while it is off leaves a sheared object. A World-axis scale of a rotated
##     object is applied and the result is immediately rebuilt as clean R * S
##     (same math 5q applies on rotation, done at creation) - so a fresh
##     object can never become sheared without switching Skew on first
##   - while the switch is ON a rotation edit PRESERVES the shear (the rigid
##     rotation delta): column lengths, volume and skew all survive, and the
##     field reads back what was typed
##   - toggling the switch OFF is the "remove the skew" action: the basis is
##     rebuilt as R * S right there, shear goes to zero, and the object's volume
##     lands on the column-length product - the same intended one-time growth 5q
##     locks (on a sheared basis that product always exceeds |det|)
##   - undoing a toggle-off restores the sheared shape AND the switch state
##   - a sheared object whose switch is OFF (a legacy save) keeps the 5q
##     behaviour: the next rotation edit flattens it
##   - a clean object with the switch ON rotates cleanly (deltas and R*S
##     rebuilds agree on clean bases), and its next shear-producing scale IS kept
##   - the flag round-trips through PrimitiveSaveData (save/load), and legacy
##     data that predates the field loads as OFF

var _fail := 0
var _done := 0
var _lab: ModelingLab

const SUB_TESTS := 7

## Float32 residue on basis round-trips is ~2e-7, so anything above 1e-2 in a
## degree means a real disagreement rather than rounding.
const ANGLE_EPS := 0.01
## For quantity ratios - volume, shear, length - a relative test is the only one
## that means the same thing at every object size.
const REL_EPS := 0.001


func _ready() -> void:
	_lab = (load("res://scenes/modeling_lab/modeling_lab.tscn") as PackedScene).instantiate()
	add_child(_lab)
	await _settle()
	_lab._enter_creative_studio()
	await _settle()

	await _test_world_scale_keeps_clean_when_off()
	await _test_enabled_rotation_preserves_the_shear()
	await _test_toggling_off_flattens_exactly_once()
	await _test_toggle_off_is_undoable_to_sheared()
	await _test_legacy_off_shear_still_flattens_on_rotation()
	await _test_switch_visible_and_arms_on_clean()
	await _test_save_load_round_trips_the_flag()

	_finish()


func _settle(n := 3) -> void:
	for _i in n:
		await get_tree().process_frame


# ── sub-tests ─────────────────────────────────────────────────────

## OFF (the default) is keep-clean: stretching a rotated object through the World
## scale row must not leave a sheared object, and the switch must stay off.
func _test_world_scale_keeps_clean_when_off() -> void:
	if not await _ready_or_fail():
		return
	var obj := await _clean_rotated()
	if obj == null:
		return
	# The honest pre-flatten result of the edit this sub-test makes: S * R, which
	# on the 30/50-rotated cube is sheared and has column lengths ~1.497/1.200/
	# 1.523 (not (2,1,1): a world X scale stretches each COLUMN COMPONENT, so
	# off-axis columns change length nonlinearly). Keep-clean flattens that result
	# to R' * S with the SAME column lengths - so those are what the Scale row
	# must show afterwards, with zero shear.
	var raw: Basis = Basis.from_scale(Vector3(2.0, 1.0, 1.0)) * obj.basis
	var expect_cols := _lab._effective_axis_lengths(raw)
	_lab._on_inspector_world_scale_changed(2.0, "x")
	await _settle()
	var after := _sel()
	if after == null:
		return
	if _shear(after.basis) > REL_EPS:
		_fail += 1
		print("FAIL: with the switch off, world-scaling a rotated object left shear "
			+ "%.4f - off must keep the object clean in real time" % _shear(after.basis))
		return
	var cols := _lab._effective_axis_lengths(after.basis)
	if not _approx_eq(cols, expect_cols):
		_fail += 1
		print("FAIL: with the switch off, world-scaling 2x flattened to Scale %s, "
			% _v(cols) + "but the pre-flatten result had columns %s - the flatten "
			% _v(expect_cols) + "must keep the stretch it just applied")
		return
	if bool(after.get_meta(&"skew_enabled", false)):
		_fail += 1
		print("FAIL: the switch flipped on even though the object was never sheared")
		return
	var toggle := _lab.get_node_or_null("%SkewToggle") as CheckBox
	if toggle == null or not toggle.visible:
		_fail += 1
		print("FAIL: the Skew switch must be visible on a clean object")
		return
	if toggle.button_pressed:
		_fail += 1
		print("FAIL: the Skew switch shows pressed on a clean, switch-off object")
		return
	_done += 1
	print("      off = keep-clean: world-stretch of a rotated object stays clean "
		+ "(shear 0, Scale %s), switch visible + unpressed" % _v(cols))


## ON preserves the shear through rotation edits (5r behaviour, unchanged).
func _test_enabled_rotation_preserves_the_shear() -> void:
	if not await _ready_or_fail():
		return
	var obj := await _sheared()
	if obj == null:
		return
	var shear_before := _shear(obj.basis)
	var cols_before := _lab._effective_axis_lengths(obj.basis)
	_lab._on_inspector_rot_changed(45.0, "x")
	await _settle()
	var after := _sel()
	if after == null:
		return
	var shear_after := _shear(after.basis)
	if shear_after > shear_before + REL_EPS or shear_after < shear_before - REL_EPS:
		_fail += 1
		print("FAIL: with the switch on, rotating changed the shear from %.4f to %.4f"
			% [shear_before, shear_after])
		print("      The switch is on, so the rotation must be rigid: shear survives.")
		return
	var cols_after := _lab._effective_axis_lengths(after.basis)
	if not _approx_eq(cols_before, cols_after):
		_fail += 1
		print("FAIL: with the switch on, rotating moved the Scale row from %s to %s"
			% [_v(cols_before), _v(cols_after)])
		return
	var got: float = _lab._read_rotation_degrees(after.basis).x
	if absf(got - 45.0) > ANGLE_EPS:
		_fail += 1
		print("FAIL: typed 45 with the switch on and it reads back %.3f" % got)
		return
	_done += 1
	print("      switch on: rotation is rigid - shear %.4f (kept), Scale %s, "
		% [shear_after, _v(cols_after)] + "reads back 45.0")


func _test_toggling_off_flattens_exactly_once() -> void:
	if not await _ready_or_fail():
		return
	if not _lab.has_method("_on_skew_toggle_toggled"):
		_fail += 1
		print("FAIL: there is no _on_skew_toggle_toggled to turn the switch off")
		return
	var obj := await _sheared()
	if obj == null:
		return
	var cols := _lab._effective_axis_lengths(obj.basis)
	var product: float = cols.x * cols.y * cols.z
	var v_before := absf(obj.basis.determinant())
	_lab._on_skew_toggle_toggled(false)
	await _settle()
	var after := _sel()
	if after == null:
		return
	if _shear(after.basis) > REL_EPS:
		_fail += 1
		print("FAIL: toggling the switch off left shear %.4f - it is supposed to "
			% _shear(after.basis) + "remove the skew right there")
		return
	var v_after := absf(after.basis.determinant())
	if absf(v_after - product) > REL_EPS * product:
		_fail += 1
		print("FAIL: after toggling off, |det| is %.4f but the column length product is "
			% v_after + "%.4f - flattening must land on their product, the intended "
			% product + "one-time growth.")
		return
	if not (v_after > v_before):
		_fail += 1
		print("FAIL: toggling off should grow the object once (Hadamard gap), but "
			+ "|det| went %.4f -> %.4f" % [v_before, v_after])
		return
	_done += 1
	print("      toggling off flattens: shear 0, |det| %.4f -> %.4f == column "
		% [v_before, v_after] + "product (grown once, as designed)")


func _test_toggle_off_is_undoable_to_sheared() -> void:
	if not await _ready_or_fail():
		return
	if not _lab.has_method("_on_skew_toggle_toggled"):
		_fail += 1
		print("FAIL: there is no _on_skew_toggle_toggled to turn the switch off")
		return
	var obj := await _sheared()
	if obj == null:
		return
	var shear_before := _shear(obj.basis)
	_lab._on_skew_toggle_toggled(false)
	await _settle()
	var flattened := _sel()
	if flattened == null:
		return
	if _shear(flattened.basis) > REL_EPS:
		_fail += 1
		print("FAIL: the setup did not flatten - this sub-test is not exercising undo")
		return
	_lab._on_undo()
	await _settle()
	var restored := _sel()
	if restored == null:
		return
	if _shear(restored.basis) < shear_before - REL_EPS:
		_fail += 1
		print("FAIL: undoing the toggle-off did not bring the shear back "
			+ "(%.4f, expected ~%.4f)" % [_shear(restored.basis), shear_before])
		return
	if not bool(restored.get_meta(&"skew_enabled", false)):
		_fail += 1
		print("FAIL: undoing the toggle-off restored the shape but left the switch "
			+ "off - the undo should restore the sheared, skew-enabled state")
		return
	_done += 1
	print("      undo of toggle-off restores the sheared object with the switch on "
		+ "(shear %.4f)" % _shear(restored.basis))


## The 5q regression guard, restated for the re-scoped contract: a sheared object
## whose switch is OFF (a legacy save) still flattens on rotation.
func _test_legacy_off_shear_still_flattens_on_rotation() -> void:
	if not await _ready_or_fail():
		return
	var obj := await _sheared()
	if obj == null:
		return
	obj.set_meta(&"skew_enabled", false)
	var cols := _lab._effective_axis_lengths(obj.basis)
	var product: float = cols.x * cols.y * cols.z
	_lab._on_inspector_rot_changed(45.0, "x")
	await _settle()
	var after := _sel()
	if after == null:
		return
	if _shear(after.basis) > REL_EPS:
		_fail += 1
		print("FAIL: with the switch off, a rotation edit left shear %.4f - the 5q "
			% _shear(after.basis) + "flatten contract must hold for off objects")
		return
	if absf(absf(after.basis.determinant()) - product) > REL_EPS * product:
		_fail += 1
		print("FAIL: with the switch off, the flatten landed on |det| %.4f, not the "
			% absf(after.basis.determinant()) + "column product %.4f"
			% [product])
		return
	_done += 1
	print("      legacy switch-off: the 5q flatten survives - rotation removes the "
		+ "shear and lands on the column product %.4f" % product)


## The switch is always visible; on a clean object pressing it arms the object -
## its next shear-producing scale is kept, and rotation preserves it.
func _test_switch_visible_and_arms_on_clean() -> void:
	if not await _ready_or_fail():
		return
	_lab.selection_manager.deselect_all()
	_lab._on_spawn_selected(PrimitiveDef.Type.CUBE)
	await _settle()
	var obj := _sel()
	if obj == null:
		return
	var toggle := _lab.get_node_or_null("%SkewToggle") as CheckBox
	if toggle == null or not toggle.visible:
		_fail += 1
		print("FAIL: the Skew switch must be visible on a clean object")
		return
	if toggle.button_pressed:
		_fail += 1
		print("FAIL: the Skew switch shows pressed on a clean, switch-off object")
		return
	_lab._on_skew_toggle_toggled(true)
	await _settle()
	if not bool(obj.get_meta(&"skew_enabled", false)):
		_fail += 1
		print("FAIL: pressing the switch did not set the skew_enabled flag")
		return
	if _shear(obj.basis) > REL_EPS or not _approx_eq(
			_lab._effective_axis_lengths(obj.basis), Vector3.ONE):
		_fail += 1
		print("FAIL: pressing the switch changed the clean object's shape")
		return
	# A clean object with a stale ON flag rotates cleanly (deltas and R*S
	# rebuilds agree on clean bases).
	_lab._on_inspector_rot_changed(30.0, "x")
	await _settle()
	_lab._on_inspector_rot_changed(50.0, "y")
	await _settle()
	var rotated := _sel()
	if rotated == null:
		return
	if _shear(rotated.basis) > REL_EPS:
		_fail += 1
		print("FAIL: a clean object with ON gained shear %.4f on rotation"
			% _shear(rotated.basis))
		return
	# Armed ON, its next shear-producing scale IS kept (keep-clean only applies
	# while the switch is off). The Y rotation is what makes the world-X scale a
	# shearing edit: rotating about X alone keeps the X column aligned with world
	# X, so a world X stretch stays orthogonal and never creates shear.
	_lab._on_inspector_world_scale_changed(2.0, "x")
	await _settle()
	var sheared := _sel()
	if sheared == null:
		return
	var shear: float = _shear(sheared.basis)
	if not shear > REL_EPS:
		_fail += 1
		print("FAIL: armed ON, world-scaling a rotated object should keep the shear "
			+ "but it stayed clean")
		return
	_done += 1
	print("      clean object: switch visible + unpressed, ON arms it - next shear "
		+ "is kept (%.4f) and rotation preserves it" % shear)


func _test_save_load_round_trips_the_flag() -> void:
	if not await _ready_or_fail():
		return
	var obj := await _sheared()
	if obj == null:
		return
	var pd := _lab.save_manager._capture_mesh(obj, "")
	# Object.get() returns null for an absent property: a clean RED signal that
	# keeps this file compiling even before the field exists (unlike reading
	# pd.skew_enabled statically, which would be a parse error). PrimitiveSaveData
	# does not have Object.has() in Godot 4.
	var raw_flag = pd.get("skew_enabled")
	if raw_flag == null:
		_fail += 1
		print("FAIL: PrimitiveSaveData has no skew_enabled field - the flag cannot "
			+ "round-trip saves")
		return
	if not bool(raw_flag):
		_fail += 1
		print("FAIL: capturing a sheared, switch-on object did not store skew_enabled")
		return
	# A legacy save predates the field: a fresh PrimitiveSaveData is its stand-in,
	# and must load as OFF.
	var legacy := PrimitiveSaveData.new()
	if bool(legacy.get("skew_enabled")):
		_fail += 1
		print("FAIL: a legacy PrimitiveSaveData defaults to skew ENABLED - old saves "
			+ "must load with the switch off")
		return
	# Restore: the flag must come back onto the rebuilt node alongside the basis.
	var data := ModelData.new()
	data.primitives.append(pd)
	var container := Node3D.new()
	add_child(container)
	var created := _lab.save_manager.restore_model(container, data, _lab.spawner)
	if created.is_empty():
		_fail += 1
		print("FAIL: restore_model produced no node")
		return
	var restored := created[0]
	if not bool(restored.get_meta(&"skew_enabled", false)):
		_fail += 1
		print("FAIL: restore_model did not put the skew_enabled flag back on the node")
		return
	if _shear(restored.basis) < REL_EPS:
		_fail += 1
		print("FAIL: restore_model lost the shear on the saved basis")
		return
	_done += 1
	print("      save/load round-trips the flag (on stays on, legacy defaults off)")


# ── helpers ───────────────────────────────────────────────────────

## Spawns a cube, rotates it through the panel, switches Skew ON, then stretches
## it along a WORLD axis through the panel. With the switch on that edit creates
## and KEEPS the shear - the natural "deliberately skewed" working state.
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
	_lab._on_skew_toggle_toggled(true)
	await _settle()
	_lab._on_inspector_world_scale_changed(2.0, "x")
	await _settle()
	var out := _sel()
	if out == null:
		return null
	if not _lab._is_sheared(out.basis):
		_fail += 1
		print("FAIL: setup failed - rotate + armed world-scale did not keep the shear,")
		print("      so this sub-test is not exercising the feature")
		return null
	return out


## A rotated, CLEAN cube (switch off / default state).
func _clean_rotated() -> Node3D:
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
	var out := _sel()
	if out == null:
		return null
	if _lab._is_sheared(out.basis):
		_fail += 1
		print("FAIL: setup failed - plain rotation edits should leave the object clean")
		return null
	return out


func _sel() -> Node3D:
	return _lab.selection_manager.get_selected() as Node3D


func _ready_or_fail() -> bool:
	if _lab == null or _lab.selection_manager == null:
		_fail += 1
		print("FAIL: the lab did not come up")
		return false
	return true


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
		print("PASS: the Skew switch - always visible, default off, keeps objects "
			+ "clean in real time, preserves through rotation while on, flattens "
			+ "(grown once) when toggled off, survives undo and save/load, and "
			+ "keeps the 5q flatten for legacy off objects")
	get_tree().quit(1 if _fail else 0)