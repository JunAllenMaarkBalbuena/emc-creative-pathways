extends Node

## Regression test: the inspector carries TWO transform sets, Local and World, and
## undo/redo survives every row of both.
##
## The panel previously had one set, and it was entirely local: `node.position`,
## `node.rotation_degrees`, and local axis lengths (the basis's column lengths).
## The World set is the same three quantities in world space, which is not a
## relabelling — the numbers genuinely differ, because a rotated object has
## different lengths along its own axes than along the world's:
##
##   rot 37deg about Y, scale (2,3,4)
##     column lengths = (2.000, 3.000, 4.000)   <- the Local Scale row
##     row lengths    = (2.889, 3.000, 3.414)   <- the World Scale row
##
## Row lengths are the world answer because scaling row i of a matrix scales
## exactly that row's length, which makes the read/write pair exactly invertible.
## They are also what the Global gizmo scale handle already does
## (`Basis.from_scale(f) * basis` pre-multiplies), so the panel and the gizmo
## cannot disagree.
##
## TWO REAL DEFECTS ARE ALSO COVERED HERE.
##
## 1. `Basis.get_euler()` is only valid on an ORTHONORMAL basis. The old Local
##    rotation readout used `node.rotation_degrees`, which is `get_euler()`. On a
##    rotation of (20,37,-11) with scale (2,3,4) it reported **(90.00, 35.52,
##    0.00)** — not a rounding difference, a completely different orientation.
##    Non-uniform scale breaks it exactly as shear does, and `ShearWarning` only
##    disclosed shear. Both rotation rows now read
##    `orthonormalized().get_euler()`, which recovers the set rotation exactly.
##
## 2. Each write must refresh BOTH sets. A two-set panel where editing the Local
##    row leaves the World row showing pre-edit numbers is the specific way this
##    feature goes wrong, so it is asserted directly rather than assumed.
##
## Undo/redo is checked per row, and bit-exactness is the point: the 5h fix made
## `CommandFactory.transform` store the basis verbatim instead of round-tripping
## it through Euler, and an edit made through a NEW write path is exactly where
## that could silently regress. The old defect was ~0.65 per component; the
## tolerance here is 1e-6, six orders of magnitude tighter.
##
## Every expected quantity in this file is computed independently of the
## production code, so the two cannot share a bug.

var _fail := 0
var _done := 0
var _lab: ModelingLab

const SUB_TESTS := 9

## Chosen so rotation and non-uniform scale COMBINE, which is the only case where
## the Local and World scale rows disagree and where `get_euler()` breaks.
const TARGET_EULER := Vector3(20.0, 37.0, -11.0)
const TARGET_SCALE := Vector3(2.0, 3.0, 4.0)
const TARGET_POS := Vector3(1.0, 2.0, 3.0)

## Bit-exact enough to catch any real regression, loose enough not to be flaky.
const EXACT := 1e-6

## Every SpinBox has step 0.01, so a displayed value is quantised to the nearest
## hundredth. Any quantity read OFF a widget has to be compared with that
## resolution in mind, or a correct implementation fails on its own rounding -
## row length 3.108 displays as 3.11 and is not an error.
const QUANT := 0.006

## One representative row per field, driving both directions of the undo stack.
const ROWS: Array = [
	{"label": "local position X", "handler": "_on_inspector_pos_changed",
		"spin": "PosX", "value": 3.5},
	{"label": "local rotation X", "handler": "_on_inspector_rot_changed",
		"spin": "RotX", "value": 15.0},
	{"label": "local scale X", "handler": "_on_inspector_scale_changed",
		"spin": "ScaleX", "value": 5.0},
	{"label": "world position X", "handler": "_on_inspector_world_pos_changed",
		"spin": "WPosX", "value": 7.5},
	{"label": "world rotation X", "handler": "_on_inspector_world_rot_changed",
		"spin": "WRotX", "value": 25.0},
	{"label": "world scale X", "handler": "_on_inspector_world_scale_changed",
		"spin": "WScaleX", "value": 6.0},
]


func _ready() -> void:
	var tree := get_tree()
	_lab = (load("res://scenes/modeling_lab/modeling_lab.tscn") as PackedScene).instantiate()
	add_child(_lab)
	tree.create_timer(90.0).timeout.connect(_on_watchdog)
	await tree.process_frame
	await tree.process_frame
	_lab._enter_creative_studio()
	await tree.process_frame
	# One cube for the whole run. Without it every sub-test would bail on "no
	# object selected" and the RED state would report the wrong reason.
	_lab.selection_manager.deselect_all()
	_lab._on_spawn_selected(PrimitiveDef.Type.CUBE)
	await tree.process_frame

	await _test_both_sets_exist()
	await _test_plain_object_agrees_across_both_sets()
	await _test_world_scale_is_row_lengths()
	await _test_rotation_rows_report_the_set_rotation()
	await _test_every_row_undo_restores_and_redo_reapplies()
	await _test_world_scale_edit_reports_what_it_applied()
	await _test_world_scale_edit_preserves_shear_through_undo()
	await _test_editing_one_set_refreshes_the_other()
	await _test_shear_warning_still_tracks_shear()

	_finish()


## The panel must carry twelve fields. Six of them are new, so a missing one is the
## expected RED state rather than a crash.
func _test_both_sets_exist() -> void:
	var missing: Array[String] = []
	for row in ROWS:
		var spin := _spin(String(row["spin"]))
		if spin == null:
			missing.append(String(row["spin"]))
			continue
		if not _lab.has_method(String(row["handler"])):
			missing.append(String(row["handler"]) + "()")
	if missing.size() > 0:
		_fail += 1
		print("FAIL: the inspector has no second transform set. Missing %s"
			% ", ".join(missing))
		return
	_done += 1
	print("      both sets are present - 6 fields and 6 write handlers")


## On an unrotated object the two sets must agree. This is the sanity property
## that catches a World row accidentally reading the local quantity: it is true
## only when nothing has rotated, so it cannot pass by coincidence on the rotated
## cases below.
func _test_plain_object_agrees_across_both_sets() -> void:
	if not await _ready_or_fail():
		return
	var cube := _sel()
	cube.basis = Basis()
	cube.position = Vector3(2.0, 0.0, -1.0)
	await _resync()
	var local_scale := _triplet("Scale")
	var world_scale := _triplet("WScale")
	if not local_scale.is_equal_approx(world_scale):
		_fail += 1
		print("FAIL: an unrotated object shows different scales in the two sets "
			+ "(local %s, world %s). One of the rows is reading the wrong quantity."
			% [_v(local_scale), _v(world_scale)])
		return
	var lp := _triplet("Pos")
	var wp := _triplet("WPos")
	# World position differs from local position by the Workspace node's own
	# 0.092358 Y offset, measured, so this compares only the axes that offset
	# cannot touch. Asserting exact equality here would be asserting the bug.
	if absf(lp.x - wp.x) > EXACT or absf(lp.z - wp.z) > EXACT:
		_fail += 1
		print("FAIL: world and local position disagree on X/Z (%s vs %s) even though "
			% [_v(lp), _v(wp)] + "the only ancestor offset is a Y translation.")
		return
	_done += 1
	print("      an unrotated object reports the same scale and the same X/Z in both sets")


## The distinguishing property. World scale must be row lengths, not a relabelling
## of the column lengths the Local row already shows.
func _test_world_scale_is_row_lengths() -> void:
	if not await _ready_or_fail():
		return
	var cube := _sel()
	cube.basis = _target_basis()
	cube.position = TARGET_POS
	await _resync()
	var local_scale := _triplet("Scale")
	var world_scale := _triplet("WScale")
	var expect_local := _column_lengths(_target_basis())
	var expect_world := _row_lengths(_target_basis())
	var local_drift := _vec_delta(local_scale, expect_local)
	if local_drift > QUANT:
		_fail += 1
		print("FAIL: the Local scale row reads %s, expected the column lengths %s "
			% [_v(local_scale), _v(expect_local)] + "(off by %.4f, allowed %.3f for "
			% [local_drift, QUANT] + "the widget's 0.01 step)")
		return
	var world_drift := _vec_delta(world_scale, expect_world)
	if world_drift > QUANT:
		_fail += 1
		print("FAIL: the World scale row reads %s, expected the row lengths %s "
			% [_v(world_scale), _v(expect_world)] + "(off by %.4f, allowed %.3f for "
			% [world_drift, QUANT] + "the widget's 0.01 step)")
		return
	# The two rows must genuinely DIFFER here. Quantisation is 0.01 and the real
	# gap is ~0.3-0.9, so this is far outside widget noise.
	if world_scale.distance_to(local_scale) <= QUANT:
		_fail += 1
		print("FAIL: both scale rows read %s. They can only agree on an unrotated "
			% _v(world_scale) + "object; here the object is rotated, so the World row "
			+ "is not actually in world space.")
		return
	_done += 1
	print("      world scale is row lengths (%s) vs local column lengths (%s)"
		% [_v(world_scale), _v(local_scale)])


## The `get_euler()` defect, on both rotation rows. Expected to read back the
## rotation that was actually set, not (90.00, 35.52, 0.00).
func _test_rotation_rows_report_the_set_rotation() -> void:
	if not await _ready_or_fail():
		return
	var cube := _sel()
	cube.basis = _target_basis()
	cube.position = TARGET_POS
	await _resync()
	for prefix in ["Rot", "WRot"]:
		var shown := _triplet(prefix)
		var want := TARGET_EULER
		# Euler decomposition is only unique up to representation: any equivalent
		# triple is a correct answer. Compare the ROTATION they produce, not the
		# numbers, so a legitimate gimbal-reordered triple is not called a failure.
		var got := Basis.from_euler(Vector3(deg_to_rad(shown.x), deg_to_rad(shown.y),
				deg_to_rad(shown.z)))
		var want_basis := Basis.from_euler(Vector3(deg_to_rad(want.x),
				deg_to_rad(want.y), deg_to_rad(want.z)))
		var drift: float = got.orthonormalized().get_rotation_quaternion() \
			.angle_to(want_basis.get_rotation_quaternion())
		if drift > 0.01:
			_fail += 1
			print("FAIL: the %s row reads %s but the rotation that was set was %s "
				% [prefix, _v(shown), _v(want)] + "(%.2f deg apart). This is the "
				% rad_to_deg(drift) + "get_euler()-on-a-scaled-basis defect.")
			return
	_done += 1
	print("      both rotation rows report the rotation that was set (%s)"
		% _v(TARGET_EULER))


## The undo guarantee, row by row. For each of the six fields: apply the edit,
## confirm it actually changed something (an inert row would make the rest of the
## check vacuous), undo and require an exact restore, then redo and require the
## edit to come back exactly.
func _test_every_row_undo_restores_and_redo_reapplies() -> void:
	if not await _ready_or_fail():
		return
	if not _lab.has_method("_on_undo"):
		_fail += 1
		print("FAIL: there is no _on_undo, so undo cannot be exercised")
		return
	for row in ROWS:
		var label := String(row["label"])
		var handler := String(row["handler"])
		var spin_name := String(row["spin"])
		var value := float(row["value"])
		var spin := _spin(spin_name)
		if spin == null:
			_fail += 1
			print("FAIL: %s has no field %s" % [label, spin_name])
			continue
		var cube := _sel()
		if cube == null:
			_fail += 1
			print("FAIL: no object selected for %s" % label)
			continue
		cube.basis = _target_basis()
		cube.position = TARGET_POS
		await get_tree().process_frame
		cube = _sel()
		if cube == null:
			_fail += 1
			print("FAIL: the object vanished before the %s edit" % label)
			continue
		cube.basis = _target_basis()
		cube.position = TARGET_POS
		var before := _flat(cube.transform)

		# Drive the widget the way a user does, so the value_changed wiring is
		# under test rather than bypassed.
		spin.value = value
		var edited_node := _sel()
		if edited_node == null:
			_fail += 1
			print("FAIL: the %s edit destroyed the object" % label)
			continue
		var edited := _flat(edited_node.transform)
		if edited == before:
			_fail += 1
			print("FAIL: setting %s to %.3f changed nothing, so its undo and redo "
				% [label, value] + "cannot be meaningfully tested.")
			continue

		_lab._on_undo()
		await get_tree().process_frame
		var undone := _sel()
		if undone == null:
			_fail += 1
			print("FAIL: undoing the %s edit left nothing selected" % label)
			continue
		var after_undo := _flat(undone.transform)
		var undo_delta := _max_delta(before, after_undo)
		if undo_delta > EXACT:
			_fail += 1
			print("FAIL: undo did not restore the %s edit. Max component error "
				% label + "%.6f (tolerance %.0e). Full before/after: %s vs %s"
				% [undo_delta, EXACT, _s(before), _s(after_undo)])
			continue

		_lab._on_redo()
		await get_tree().process_frame
		var redone := _sel()
		if redone == null:
			_fail += 1
			print("FAIL: redoing the %s edit left nothing selected" % label)
			continue
		var redo_delta := _max_delta(edited, _flat(redone.transform))
		if redo_delta > EXACT:
			_fail += 1
			print("FAIL: redo did not reapply the %s edit. Max component error "
				% label + "%.6f" % redo_delta)
			continue
		_lab._on_undo()
		await get_tree().process_frame
		_done += 1
		print("      %s: undo exact, redo exact" % label)
		if _fail > 0:
			return


## A world-axis scale must apply the stretch and react to the Skew switch (5s).
##
## This sub-test previously asserted that the row must read back whatever number
## the user typed AND that the shear it creates must be disclosed. 5s keep-clean
## splits that contract in two by the Skew switch:
##
##   - OFF (the default): the stretch is applied and the result is flattened to
##     R * S in real time, so a rotated object comes out CLEAN - there is no shear
##     to disclose, and the World row re-reads the cleaned frame rather than the
##     typed number (on a rotated basis the typed world-axis length cannot survive
##     a flatten; that is the price of keep-clean).
##   - ON: the edit keeps its shear and the row's old guarantee holds - the shear
##     is disclosed, and the World row reads back exactly what was typed.
##
## The read/write consistency check that matters ("the panel is not reporting one
## quantity and applying another") therefore lives in the ON state, asserted
## against an independently computed row length.
func _test_world_scale_edit_reports_what_it_applied() -> void:
	if not await _ready_or_fail():
		return
	var rot := Basis.from_euler(Vector3(deg_to_rad(30.0), deg_to_rad(50.0), 0.0))
	var cube := _sel()
	cube.basis = rot
	cube.position = TARGET_POS
	await get_tree().process_frame
	cube = _sel()
	cube.basis = rot
	_lab._update_inspector(cube)
	var spin := _spin("WScaleX")
	var label := _lab.get_node_or_null("%ShearWarning") as Label
	if spin == null or label == null:
		_fail += 1
		print("FAIL: the world scale row or the shear warning is missing")
		return
	if label.visible:
		_fail += 1
		print("FAIL: a clean rotated basis already shows the shear warning")
		return
	var typed := _row_lengths(cube.basis).x * 2.0
	spin.value = typed
	var node := _sel()
	if node == null:
		_fail += 1
		print("FAIL: the world scale edit destroyed the object")
		return
	# Part 1 - switch OFF (default): keep-clean. The stretch happened, the result
	# is clean, and nothing is disclosed because there is no shear to disclose.
	if _shear_amount(node.basis) > 0.001:
		_fail += 1
		print("FAIL: with the Skew switch OFF a world scale left shear %.4f - off "
			% _shear_amount(node.basis) + "must flatten the result in real time")
		return
	if label.visible:
		_fail += 1
		print("FAIL: a kept-clean world scale shows the shear warning - the object "
			+ "was flattened, so there is no shear to disclose")
		return
	# Part 2 - switch ON: the edit keeps the shear, discloses it, and the row
	# reads back exactly what was typed (computed independently of the write path).
	_lab._on_skew_toggle_toggled(true)
	await get_tree().process_frame
	node = _sel()
	if node == null:
		_fail += 1
		print("FAIL: arming the Skew switch lost the selection")
		return
	var typed2 := _row_lengths(node.basis).x * 1.5
	spin.value = typed2
	node = _sel()
	if node == null:
		_fail += 1
		print("FAIL: the armed world scale edit destroyed the object")
		return
	var applied := _row_lengths(node.basis).x
	if absf(applied - typed2) > QUANT:
		_fail += 1
		print("FAIL: with the switch ON, typed %.4f into World Scale X and the row "
			% typed2 + "now measures %.4f. The field is not reporting the quantity "
			% applied + "it applies.")
		return
	if not label.visible:
		_fail += 1
		print("FAIL: with the switch ON a world scale sheared the object (max column "
			+ "dot %.4f) but no warning is shown" % _shear_amount(node.basis))
		return
	_done += 1
	print("      world scale: OFF flattens to clean (no warning), ON keeps the "
		+ "shear and reads back what it applied (%.4f)" % applied)


## Shear must survive a trip through the NEW write path. This is the 5j-i
## regression re-checked through `Basis.from_scale(f) * basis`, which scales rows
## rather than columns and so changes the shear ANGLE without removing the skew.
##
## 5s keep-clean re-scopes it: while the Skew switch is OFF a world-scale edit is
## flattened in real time, so a sheared object can only exist (and be edited) with
## the switch ON. Arm it - exactly the state a user is in when they have a sheared
## object - and the guarantee is unchanged: a world-scale edit and its undo must
## both preserve the shear.
func _test_world_scale_edit_preserves_shear_through_undo() -> void:
	if not await _ready_or_fail():
		return
	var cube := _sel()
	cube.basis = Basis()
	cube.position = TARGET_POS
	await get_tree().process_frame
	cube = _sel()
	cube.basis = Basis()
	# A global-axis scale on a yawed object is what produces shear in the first
	# place, so build it the same way the gizmo does.
	cube.basis = Basis.from_euler(Vector3(0.0, deg_to_rad(45.0), 0.0))
	await get_tree().process_frame
	cube = _sel()
	cube.basis = Basis.from_euler(Vector3(0.0, deg_to_rad(45.0), 0.0))
	cube.basis = Basis.from_scale(Vector3(2.0, 1.0, 1.0)) * cube.basis
	var sheared := _shear_amount(cube.basis)
	if sheared < 0.1:
		_fail += 1
		print("FAIL: could not build a sheared basis (shear %.4f), so this test "
			% sheared + "would pass without exercising anything.")
		return
	# 5s: a sheared object is worked on with the Skew switch ON - arm it (the
	# flag only allows the shear; it does not change this basis).
	cube.set_meta(&"skew_enabled", true)
	var spin := _spin("WScaleX")
	if spin == null:
		_fail += 1
		print("FAIL: no WScaleX field")
		return
	var rows_before := _row_lengths(cube.basis)
	spin.value = rows_before.x * 1.5
	var node := _sel()
	if node == null:
		_fail += 1
		print("FAIL: the world scale edit destroyed the object")
		return
	if _shear_amount(node.basis) < 0.1:
		_fail += 1
		print("FAIL: with the Skew switch ON a world scale edit removed the shear. "
			+ "It must change the skew, not flatten the object to R*S.")
		return
	_lab._on_undo()
	await get_tree().process_frame
	node = _sel()
	if node == null:
		_fail += 1
		print("FAIL: undoing the world scale edit left nothing selected")
		return
	if _shear_amount(node.basis) < 0.1:
		_fail += 1
		print("FAIL: undoing a world scale edit removed the shear")
		return
	_done += 1
	print("      shear survives a world scale edit and its undo (%.4f -> %.4f)"
		% [sheared, _shear_amount(node.basis)])


## A two-set panel is only correct if the two sets stay in step. Editing one row
## must repopulate the other, in both directions.
func _test_editing_one_set_refreshes_the_other() -> void:
	if not await _ready_or_fail():
		return
	var cube := _sel()
	cube.basis = _target_basis()
	cube.position = TARGET_POS
	await _resync()

	# Local position edit -> the World row must follow.
	var pos := _spin("PosX")
	var wpos := _spin("WPosX")
	if pos == null or wpos == null:
		_fail += 1
		print("FAIL: the position fields are missing")
		return
	var expected_world := 9.5
	pos.value = expected_world
	var node := _sel()
	if node == null:
		_fail += 1
		print("FAIL: the local position edit destroyed the object")
		return
	if absf(wpos.value - node.global_position.x) > 1e-3:
		_fail += 1
		print("FAIL: after setting local Position X to %.2f the World row still "
			% expected_world + "shows %.3f but global_position.x is %.3f. The two sets "
			% [wpos.value, node.global_position.x] + "are out of step.")
		return

	# And the other direction: a World scale edit must move the Local row.
	var wscale := _spin("WScaleX")
	var lscale := _spin("ScaleX")
	if wscale == null or lscale == null:
		_fail += 1
		print("FAIL: the scale fields are missing")
		return
	wscale.value = _row_lengths(node.basis).x * 3.0
	node = _sel()
	if node == null:
		_fail += 1
		print("FAIL: the world scale edit destroyed the object")
		return
	var expected_local := _column_lengths(node.basis).x
	if absf(lscale.value - expected_local) > 1e-2:
		_fail += 1
		print("FAIL: after scaling the World row the Local row shows %.3f but the "
			% lscale.value + "local axis length is %.3f. The two sets are out of step."
			% expected_local)
		return
	_done += 1
	print("      editing either set refreshes the other, in both directions")


## The existing disclosure must still work. Two rotation rows now exist, so it
## matters more than ever: both of them run `orthonormalized()`, which is exact
## for a clean basis and approximate for a sheared one.
func _test_shear_warning_still_tracks_shear() -> void:
	if not await _ready_or_fail():
		return
	var label := _lab.get_node_or_null("%ShearWarning") as Label
	if label == null:
		_fail += 1
		print("FAIL: there is no ShearWarning label")
		return
	var cube := _sel()
	cube.basis = Basis.from_scale(Vector3(2.0, 1.0, 1.0)) \
			* Basis.from_euler(Vector3(0.0, deg_to_rad(45.0), 0.0))
	await _resync()
	if not label.visible:
		_fail += 1
		print("FAIL: the object is sheared but the warning is hidden, so two sets of "
			+ "rotation numbers are being shown with no caveat")
		return
	cube.basis = Basis.from_euler(Vector3(0.0, deg_to_rad(20.0), 0.0))
	await _resync()
	if label.visible:
		_fail += 1
		print("FAIL: a clean basis still shows the shear warning")
		return
	_done += 1
	print("      the shear warning still tracks shear on a two-set panel")


# ── helpers ───────────────────────────────────────────────────────

## True when every row of ROWS has its field and its handler. Each dependent
## sub-test bails on this rather than crashing partway and reporting PASS.
func _ready_or_fail() -> bool:
	var cube := _sel()
	if cube == null:
		_fail += 1
		print("FAIL: no object is selected")
		return false
	for row in ROWS:
		if _spin(String(row["spin"])) == null:
			_fail += 1
			print("FAIL: the second transform set is missing (%s)"
				% String(row["spin"]))
			return false
		if not _lab.has_method(String(row["handler"])):
			_fail += 1
			print("FAIL: missing handler %s()" % String(row["handler"]))
			return false
	return true


func _spin(name: String) -> SpinBox:
	return _lab.get_node_or_null("%" + name) as SpinBox


func _sel() -> MeshInstance3D:
	if _lab == null:
		return null
	return _lab.selection_manager.get_selected() as MeshInstance3D


func _triplet(prefix: String) -> Vector3:
	var out := Vector3.ZERO
	for axis in ["X", "Y", "Z"]:
		var spin := _spin(prefix + axis)
		if spin == null:
			return Vector3(NAN, NAN, NAN)
		match axis:
			"X": out.x = spin.value
			"Y": out.y = spin.value
			"Z": out.z = spin.value
	return out


## Pushes a basis onto the object and repopulates the panel from it. Writing
## `basis` re-derives children in this lab, so the selection has to be taken
## again afterwards or the next access measures a freed instance.
func _resync() -> void:
	var cube := _sel()
	if cube == null:
		return
	_lab._update_inspector(cube)
	await get_tree().process_frame
	cube = _sel()
	if cube != null:
		_lab._update_inspector(cube)


func _target_basis() -> Basis:
	return Basis.from_euler(Vector3(deg_to_rad(TARGET_EULER.x),
			deg_to_rad(TARGET_EULER.y), deg_to_rad(TARGET_EULER.z))) \
			* Basis.from_scale(TARGET_SCALE)


## Column lengths: the lengths of the basis's own axes, which is what Godot's
## `get_scale()` returns and what the Local scale row has always shown.
func _column_lengths(b: Basis) -> Vector3:
	return Vector3(b[0].length(), b[1].length(), b[2].length())


## Row lengths: the lengths of the basis's rows, i.e. how much each WORLD axis is
## scaled. Row i scaled by f gives length f * |row i|, so this is the world-axis
## quantity and is what the World scale row shows.
func _row_lengths(b: Basis) -> Vector3:
	return Vector3(
		Vector3(b[0][0], b[1][0], b[2][0]).length(),
		Vector3(b[0][1], b[1][1], b[2][1]).length(),
		Vector3(b[0][2], b[1][2], b[2][2]).length())


## Largest absolute difference between two transforms, flattened to 13 floats so
## the failure message can show exactly which numbers moved.
func _flat(t: Transform3D) -> PackedFloat64Array:
	return PackedFloat64Array([
		t.basis[0][0], t.basis[0][1], t.basis[0][2],
		t.basis[1][0], t.basis[1][1], t.basis[1][2],
		t.basis[2][0], t.basis[2][1], t.basis[2][2],
		t.origin.x, t.origin.y, t.origin.z])


## Largest absolute component difference between two vectors. Used where one side
## comes off a SpinBox and so carries the widget's 0.01 quantisation.
func _vec_delta(a: Vector3, b: Vector3) -> float:
	return maxf(absf(a.x - b.x), maxf(absf(a.y - b.y), absf(a.z - b.z)))


func _max_delta(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	if a.size() != b.size():
		return INF
	var worst := 0.0
	for i in a.size():
		worst = maxf(worst, absf(a[i] - b[i]))
	return worst


## How far the basis is from R*S: the largest absolute dot between normalised
## columns. Zero for a clean rotation*scale basis.
func _shear_amount(b: Basis) -> float:
	var cols := [b[0].normalized(), b[1].normalized(), b[2].normalized()]
	var worst := 0.0
	for i in 3:
		for j in range(i + 1, 3):
			worst = maxf(worst, absf(cols[i].dot(cols[j])))
	return worst


func _v(x: Vector3) -> String:
	return "(%.3f, %.3f, %.3f)" % [x.x, x.y, x.z]


func _s(a: PackedFloat64Array) -> String:
	var parts: Array[String] = []
	for f in a:
		parts.append("%.6f" % f)
	return "[" + ", ".join(parts) + "]"


func _finish() -> void:
	if _done < SUB_TESTS:
		_fail += SUB_TESTS - _done
		print("FAIL: only %d of %d sub-tests completed - the rest died on an "
			% [_done, SUB_TESTS] + "unreported engine error, so the run above is "
			+ "NOT a pass")
	if _fail == 0:
		print("PASS: the inspector carries a Local and a World transform set, both "
			+ "rotation rows report the rotation that was set, and every row of both "
			+ "sets undoes and redoes exactly")
	get_tree().quit(1 if _fail else 0)


func _on_watchdog() -> void:
	print("FAIL: watchdog fired, test did not complete")
	get_tree().quit(2)