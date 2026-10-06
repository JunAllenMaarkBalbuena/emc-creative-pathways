extends Node

## Regression test for shear persistence and the shear warning.
##
## Two defects are covered, both consequences of the same thing — a sheared basis
## has no TRS representation:
##
##   1. save/load stored `rotation_degrees` + `scale` and restored them the same
##      way, so a Global-axis scale of a rotated object came back as its R*S
##      decomposition. Measured on a 45deg-yawed cube: the restored basis differs
##      from the saved one by up to 0.65 per component — the object silently
##      un-sheared on reload.
##
##   2. the inspector's RotX/Y/Z read `node.rotation_degrees`, which runs
##      `Basis.get_euler()` on a non-orthonormal matrix and so reports a rotation
##      the user never set (measured 45 -> 33.69 degrees, an 11.3 degree drift).
##      Writing one of those fields back flattens the shear to R*S.
##
## The warning is a disclosure, not a guard: the fields stay editable on purpose.
## So these tests assert that the warning is VISIBLE WHEN SHEARED and HIDDEN WHEN
## NOT — a warning that shows up on a clean object trains people to ignore it.
##
## Every sub-test that touches a node re-spawns its own cube. `restore_model()`
## frees the container's children, and a freed instance in GDScript throws on
## property access rather than comparing equal to null, so a stale reference is
## not catchable with a null check — it just kills the rest of the suite.
##
## That failure mode is why `_done` is counted and checked in `_finish()`: an
## engine script error aborts a sub-test without raising anything this file can
## see, so without the count the suite prints PASS and exits 0 having asserted
## almost nothing. A sub-test that dies is a failing test, not a passing one.

var _fail := 0
var _done := 0
var _lab: ModelingLab
var _cube: MeshInstance3D

## Yaw chosen so every axis has a non-trivial world direction and a world-axis
## scale cannot coincide with a local-axis one.
const YAW := 45.0
const SAVE_NAME := "shear_persistence_probe"
const SUB_TESTS := 6


func _ready() -> void:
	var tree := get_tree()
	_lab = (load("res://scenes/modeling_lab/modeling_lab.tscn") as PackedScene).instantiate()
	add_child(_lab)
	tree.create_timer(30.0).timeout.connect(_on_watchdog)
	await tree.process_frame
	await tree.process_frame
	_lab._enter_creative_studio()
	await tree.process_frame

	await _test_sheared_object_round_trips()
	await _test_legacy_save_still_restores()
	await _test_shear_warning_tracks_shear()
	await _test_shear_warning_hidden_on_clean_object()
	await _test_is_sheared_is_scale_invariant()
	await _test_is_sheared_survives_float32()

	_lab.save_manager.delete_model("user://models/%s.tres" % SAVE_NAME)
	_finish()


## The core fix: a sheared basis must come back as the same matrix.
##
## The shear is written straight onto the node as `S * R` rather than produced by
## dragging the gizmo, and deliberately so: this test is about persistence, not
## about how the skew got there, and building the matrix by hand keeps it
## independent of `apply_scale`'s signature. It is the exact basis a Global X
## scale of a yawed object produces.
func _test_sheared_object_round_trips() -> void:
	if _arity(_lab.save_manager, "basis_of") < 1:
		_fail += 1
		print("FAIL: SaveManager has no basis_of() - there is no way to read a "
			+ "stored basis, so a sheared object cannot survive a reload")
		return

	_cube = await _fresh_cube()
	_shear_the_cube()
	var original: Basis = _cube.basis
	var original_pos: Vector3 = _cube.position
	if not _is_sheared(original):
		_fail += 1
		print("FAIL: setup did not produce a sheared basis; this sub-test is not "
			+ "testing anything")
		return

	var data := _lab.save_manager.capture_model(_lab.object_container, SAVE_NAME)
	if data.primitives.size() != 1:
		_fail += 1
		print("FAIL: expected exactly 1 captured primitive, got %d"
			% data.primitives.size())
		return
	if not data.primitives[0].has_basis:
		_fail += 1
		print("FAIL: capture did not set has_basis; the save cannot carry shear")
		return

	var path := _lab.save_manager.save_model(data, SAVE_NAME)
	if path.is_empty():
		_fail += 1
		print("FAIL: save_model() returned an empty path")
		return
	var loaded := _lab.save_manager.load_model(path)
	if loaded == null:
		_fail += 1
		print("FAIL: could not load the model back from %s" % path)
		return

	# restore_model() frees every child of the container, so `_cube` dangles after
	# this call. It is not used again in this sub-test.
	var restored := _lab.save_manager.restore_model(
			_lab.object_container, loaded, _lab.spawner)
	if restored.size() != 1:
		_fail += 1
		print("FAIL: expected 1 restored node, got %d" % restored.size())
		return

	var got: Basis = restored[0].basis
	var d := _basis_delta(original, got)
	# float32 is the storage format for basis_rows, so this cannot be exact. The
	# point is that it stays near zero instead of losing the shear entirely.
	if d > 0.0001:
		_fail += 1
		print("FAIL: sheared basis did not survive the save round trip (delta %.6f)"
			% d)
	elif not restored[0].position.is_equal_approx(original_pos):
		_fail += 1
		print("FAIL: position did not survive the save round trip (%s -> %s)"
			% [original_pos, restored[0].position])
	elif not _is_sheared(got):
		_fail += 1
		print("FAIL: the restored object is no longer sheared - it came back as "
			+ "its R*S decomposition")
	else:
		_done += 1
		print("      a sheared basis survives save -> load -> restore (delta %.8f)"
			% d)


## Backward compatibility. A .tres written before `has_basis` existed has no such
## property, so it loads with the default false and must take the old
## rotation_degrees * scale path. If this regresses, every save a user already
## made silently loses its transform.
##
## Built in memory rather than by writing a fixture file, because the thing being
## tested is precisely "the field is absent" and an @export default already
## reproduces that exactly.
func _test_legacy_save_still_restores() -> void:
	_cube = await _fresh_cube()
	var legacy := PrimitiveSaveData.new()
	legacy.node_type = PrimitiveSaveData.TYPE_MESH
	legacy.type = PrimitiveSpawner.type_for_mesh(_cube.mesh)
	legacy.node_name = "LegacyCube"
	legacy.display_name = "LegacyCube"
	legacy.position = Vector3(2, -1, 0.5)
	legacy.rotation_degrees = Vector3(0, 30, 0)
	legacy.scale = Vector3(2, 1, 1)
	# has_basis is left at its default and basis_rows stays empty: the exact shape
	# of a pre-change save.
	#
	# Probed through the property list rather than read directly: against pre-fix
	# code the field does not exist, and reading it aborts this sub-test on an
	# engine error instead of reporting the reason it is being probed.
	if not _has_property(legacy, "has_basis") or not _has_property(legacy, "basis_rows"):
		_fail += 1
		print("FAIL: PrimitiveSaveData has no has_basis/basis_rows field, so a save "
			+ "cannot distinguish a basis-carrying entry from a legacy one")
		return

	if legacy.has_basis or legacy.basis_rows.size() != 0:
		_fail += 1
		print("FAIL: the legacy sentinel is wrong - a fresh PrimitiveSaveData must "
			+ "default to has_basis=false with no basis_rows")
		return

	var prims: Array[PrimitiveSaveData] = [legacy]
	var data := ModelData.new()
	data.primitives = prims
	var restored := _lab.save_manager.restore_model(
			_lab.object_container, data, _lab.spawner)
	if restored.size() != 1:
		_fail += 1
		print("FAIL: expected 1 restored node from the legacy save, got %d"
			% restored.size())
		return

	var want := Basis.from_euler(Vector3(0, deg_to_rad(30.0), 0)) \
			* Basis.from_scale(Vector3(2, 1, 1))
	var d := _basis_delta(want, restored[0].basis)
	if d > 0.001:
		_fail += 1
		print("FAIL: a legacy save no longer restores via rotation+scale (delta %.6f)"
			% d)
	elif not restored[0].position.is_equal_approx(legacy.position):
		_fail += 1
		print("FAIL: legacy save restored the wrong position (%s)"
			% restored[0].position)
	else:
		_done += 1
		print("      a save without a basis field still restores via rotation+scale")


## The whole point of the warning: the rotation readout is not trustworthy on a
## sheared basis, and saying so is the fix.
func _test_shear_warning_tracks_shear() -> void:
	var label := _warning_label()
	if label == null:
		return
	_cube = await _fresh_cube()
	_shear_the_cube()
	_lab._update_inspector(_cube)
	if not label.visible:
		_fail += 1
		print("FAIL: the object is sheared but no warning is shown, so a "
			+ "silently-wrong rotation readout is still being presented as fact")
	else:
		_done += 1
		print("      the shear warning is visible on a sheared object")


## A warning that appears on clean geometry is a warning nobody reads.
func _test_shear_warning_hidden_on_clean_object() -> void:
	var label := _warning_label()
	if label == null:
		return
	_cube = await _fresh_cube()
	_cube.basis = Basis.IDENTITY
	_cube.position = Vector3.ZERO
	_lab._update_inspector(_cube)
	if label.visible:
		_fail += 1
		print("FAIL: the shear warning is showing on an unrotated, unscaled object")
		return
	_done += 1
	print("      the shear warning stays hidden on a clean object")

	# And it must clear when nothing is selected at all.
	_lab._update_inspector(null)
	if label.visible:
		_fail += 1
		print("FAIL: the shear warning survived deselection")
	else:
		print("      the shear warning clears on deselect")


## The production test normalises the columns before applying its epsilon, so the
## answer must not depend on how big the object is. A raw dot-product cutoff
## would call a 1000-unit R*S cube sheared; this pins the scale independence.
func _test_is_sheared_is_scale_invariant() -> void:
	if not _lab.has_method("_is_sheared"):
		_fail += 1
		print("FAIL: ModelingLab has no _is_sheared() helper")
		return
	for size in [0.01, 1.0, 1000.0, 100000.0]:
		var clean: Basis = Basis.from_euler(Vector3(0, deg_to_rad(YAW), 0)) \
				* Basis.from_scale(Vector3(size, size, size))
		if _lab._is_sheared(clean):
			_fail += 1
			print("FAIL: a clean R*S basis at scale %f was reported as sheared"
				% size)
			return
		# Same shape, but skewed: S*R instead of R*S. Must be caught at every size.
		var sheared: Basis = Basis.from_scale(Vector3(size * 1.5, size, size)) \
				* Basis.from_euler(Vector3(0, deg_to_rad(YAW), 0))
		if not _lab._is_sheared(sheared):
			_fail += 1
			print("FAIL: a genuinely sheared basis at scale %f was not detected"
				% size)
			return
	_done += 1
	print("      shear detection is scale-independent from 0.01 to 100000")


## basis_rows is PackedFloat32Array, so a real saved object comes back with less
## precision than it went in with. The epsilon has to survive that: a basis that
## was legitimately stored and reloaded must still read as sheared, or the
## warning would appear and vanish across a save.
func _test_is_sheared_survives_float32() -> void:
	if not _lab.has_method("_is_sheared"):
		_fail += 1
		print("FAIL: ModelingLab has no _is_sheared() helper")
		return
	var clean: Basis = Basis.from_euler(Vector3(0, deg_to_rad(YAW), 0)) \
			* Basis.from_scale(Vector3(1.5, 1.0, 0.75))
	var sheared: Basis = Basis.from_scale(Vector3(2.25, 1.0, 1.0)) \
			* Basis.from_euler(Vector3(0, deg_to_rad(YAW), 0))

	if _lab._is_sheared(_through_float32(clean)):
		_fail += 1
		print("FAIL: a clean basis read back from float32 storage was reported as "
			+ "sheared - the epsilon is too tight")
		return
	if not _lab._is_sheared(_through_float32(sheared)):
		_fail += 1
		print("FAIL: a sheared basis read back from float32 storage was not "
			+ "detected - the epsilon is too loose")
		return
	_done += 1
	print("      shear detection survives the float32 storage round trip")


## Puts a basis through the exact serialisation the save format uses, float32
## quantisation included.
func _through_float32(b: Basis) -> Basis:
	var rows := PackedFloat32Array()
	rows.resize(9)
	var i := 0
	for r in 3:
		for c in 3:
			rows[i] = b[r][c]
			i += 1
	var out := Basis.IDENTITY
	i = 0
	for r in 3:
		for c in 3:
			out[r][c] = rows[i]
			i += 1
	return out


## Spawns a cube and returns it, so no sub-test depends on a node that an earlier
## `restore_model()` may have freed.
func _fresh_cube() -> MeshInstance3D:
	_lab.selection_manager.deselect_all()
	_lab._on_spawn_selected(PrimitiveDef.Type.CUBE)
	await get_tree().process_frame
	var cube := _lab.selection_manager.get_selected() as MeshInstance3D
	if cube == null:
		_fail += 1
		print("FAIL: could not spawn a cube for this sub-test")
	return cube


## Places a genuinely sheared basis on the live cube: S * R, which is what a
## Global X scale of a 45deg-yawed object produces.
func _shear_the_cube() -> void:
	_cube.position = Vector3(1, 2, 3)
	_cube.basis = Basis.from_scale(Vector3(1.5, 1, 1)) \
			* Basis.from_euler(Vector3(0, deg_to_rad(YAW), 0))


func _warning_label() -> Label:
	var label := _lab.get_node_or_null("%ShearWarning") as Label
	if label == null:
		_fail += 1
		print("FAIL: the inspector has no %ShearWarning label, so nothing tells "
			+ "the user the rotation readout is approximate")
	return label


## Shear exists exactly when the basis is not expressible as R * S, i.e. when its
## three columns are not mutually orthogonal. An independent implementation of
## that question, deliberately not the production helper's dot-product test, so
## the two do not share a bug.
func _is_sheared(b: Basis, eps: float = 0.001) -> bool:
	var ideal := Basis(b.get_rotation_quaternion()) * Basis.from_scale(b.get_scale())
	return _basis_delta(ideal, b) > eps


func _basis_delta(a: Basis, b: Basis) -> float:
	var m := 0.0
	for r in 3:
		for c in 3:
			m = maxf(m, absf(a[r][c] - b[r][c]))
	return m


## Whether a property exists on an Object. Used instead of reading the property
## where absence is a legitimate thing to test for.
func _has_property(obj: Object, prop: String) -> bool:
	for p in obj.get_property_list():
		if p.get("name", "") == prop:
			return true
	return false


func _arity(obj: Object, method: String) -> int:
	for m in obj.get_method_list():
		if m.get("name", "") == method:
			return (m.get("args", []) as Array).size()
	return -1


func _finish() -> void:
	# A sub-test that dies on an engine error increments neither counter, and the
	# suite would otherwise print PASS having asserted almost nothing.
	if _done < SUB_TESTS:
		_fail += SUB_TESTS - _done
		print("FAIL: only %d of %d sub-tests completed - the rest died on an "
			% [_done, SUB_TESTS] + "unreported engine error, so the run above is "
			+ "NOT a pass")
	if _fail == 0:
		print("PASS: shear survives save/load, legacy saves still load, the warning "
			+ "tracks shear, detection is scale- and float32-safe")
	get_tree().quit(1 if _fail else 0)


func _on_watchdog() -> void:
	print("FAIL: watchdog fired, test did not complete")
	get_tree().quit(2)
