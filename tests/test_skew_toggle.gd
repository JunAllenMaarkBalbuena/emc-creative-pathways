extends Node

## Regression test: the inspector's Skew switch - the explicit enable/disable
## that replaces "rotate the object to remove the skew" (see
## docs/decisions/2026-10-06-skew-toggle.md, audit section 5r).
##
## The contract:
##   - creating shear (a World-axis scale of a rotated object) auto-enables the
##     switch: it is a report of reality, not a permission gate. A freshly
##     sheared object is therefore in "skew on" mode.
##   - while the switch is ON a rotation edit PRESERVES the shear (the rigid
##     rotation delta): column lengths, volume and skew all survive, and the
##     field reads back what was typed.
##   - toggling the switch OFF is the "remove the skew" action: the basis is
##     rebuilt as R * S right there, shear goes to zero, and the object's volume
##     lands on the column-length product - the same intended one-time growth 5q
##     locks (on a sheared basis that product always exceeds |det|).
##   - undoing a toggle-off restores the sheared shape AND the switch state.
##   - a sheared object whose switch is OFF (a legacy save, or an explicit opt
##     out) keeps the 5q behaviour: the next rotation edit flattens it.
##   - a clean object hides the switch entirely; a clean object with a stale ON
##     flag still rotates cleanly (deltas and R*S rebuilds agree on clean bases).
##   - the flag round-trips through PrimitiveSaveData (save/load), and legacy
##     data that predates the field loads as OFF.

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

	await _test_world_scale_auto_enables_the_switch()
	await _test_enabled_rotation_preserves_the_shear()
	await _test_toggling_off_flattens_exactly_once()
	await _test_toggle_off_is_undoable_to_sheared()
	await _test_disabled_rotation_still_flattens()
	await _test_switch_is_hidden_for_clean_objects()
	await _test_save_load_round_trips_the_flag()

	_finish()


func _settle(n := 3) -> void:
	for _i in n:
		await get_tree().process_frame


# ── sub-tests ─────────────────────────────────────────────────────

func _test_world_scale_auto_enables_the_switch() -> void:
	if not await _ready_or_fail():
		return
	var obj := await _sheared()
	if obj == null:
		return
	var toggle := _lab.get_node_or_null("%SkewToggle") as CheckBox
	if toggle == null:
		_fail += 1
		print("FAIL: there is no %SkewToggle CheckBox in the inspector")
		return
	if not toggle.visible:
		_fail += 1
		print("FAIL: the Skew switch is hidden on a sheared object")
		return
	if not toggle.button_pressed:
		_fail += 1
		print("FAIL: world-scaling a rotated object sheared it, but the switch "
			+ "did not flip on - shear creation should enable the switch")
		return
	if not bool(obj.get_meta(&"skew_enabled", false)):
		_fail += 1
		print("FAIL: the skew_enabled flag was not written on the node")
		return
	_done += 1
	print("      a world-scale that shears flips the Skew switch on (and it shows)")


func _test_enabled_rotation_preserves_the_shear() -> void:
	if not await _ready_or_fail():
		return
	var obj := await _sheared()
	if obj == null:
		return
	# The switch was auto-enabled by the shear-creating scale in _sheared().
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
		print("FAIL: after toggling off, |det| is %.4f but the column length product "
			% v_after + "is %.4f - flattening must land on their product, the "
			% product + "intended one-time growth.")
		return
	if not (v_after > v_before):
		_fail += 1
		print("FAIL: toggling off should grow the object once (Hadamard gap), but "
			+ "|det| went %.4f -> %.4f" % [v_before, v_after])
		return
	var toggle := _lab.get_node_or_null("%SkewToggle") as CheckBox
	if toggle == null or toggle.visible:
		_fail += 1
		print("FAIL: the Skew switch should be hidden after the object is clean")
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


## The 5q regression guard, restated for the switch: a sheared object whose
## switch is OFF (legacy save / explicit opt-out) still flattens on rotation.
func _test_disabled_rotation_still_flattens() -> void:
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
	print("      switch off: the 5q flatten survives - rotation removes the shear "
		+ "and lands on the column product %.4f" % product)


func _test_switch_is_hidden_for_clean_objects() -> void:
	if not await _ready_or_fail():
		return
	_lab.selection_manager.deselect_all()
	_lab._on_spawn_selected(PrimitiveDef.Type.CUBE)
	await _settle()
	var obj := _sel()
	if obj == null:
		return
	var toggle := _lab.get_node_or_null("%SkewToggle") as CheckBox
	if toggle == null:
		_fail += 1
		print("FAIL: there is no %SkewToggle CheckBox in the inspector")
		return
	if toggle.visible:
		_fail += 1
		print("FAIL: the Skew switch is visible on a clean object")
		return
	# A stale ON flag on a clean object must be behaviour-neutral: the delta and
	# the R*S rebuild agree on clean bases, so nothing shears and nothing grows.
	obj.set_meta(&"skew_enabled", true)
	_lab._on_inspector_rot_changed(30.0, "x")
	await _settle()
	_lab._on_inspector_rot_changed(50.0, "y")
	await _settle()
	var after := _sel()
	if after == null:
		return
	var b := after.basis
	if _shear(b) > REL_EPS:
		_fail += 1
		print("FAIL: a clean object with a stale ON flag gained shear %.4f"
			% _shear(b))
		return
	var cols := _lab._effective_axis_lengths(b)
	if not _approx_eq(cols, Vector3.ONE):
		_fail += 1
		print("FAIL: a clean object with a stale ON flag changed its Scale to %s"
			% _v(cols))
		return
	_done += 1
	print("      clean object: switch hidden, and a stale ON flag rotates cleanly")


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

## Spawns a cube, rotates it through the panel, then stretches it along a WORLD
## axis through the panel - the one path that creates shear. Under the switch
## this also auto-enables skew (sub-test 1 locks that), so the returned object
## is a sheared, switch-ON object - the natural post-scale state.
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
		print("PASS: the Skew switch - auto-enables on shear, preserves through "
			+ "rotation while on, flattens (grown once) when toggled off, survives "
			+ "undo and save/load, and keeps the 5q flatten for off objects")
	get_tree().quit(1 if _fail else 0)