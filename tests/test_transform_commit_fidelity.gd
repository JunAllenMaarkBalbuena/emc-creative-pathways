extends Node

## Regression test for the play report:
##
##   "bug when moving or scaling the object it will rotate"
##
## Root cause: `CommandFactory.transform()` serialised a Transform3D into
## `position` + `rotation_degrees` + `scale` by pulling the euler angles out
## with `basis.get_euler()`. `Basis.get_euler()` is only valid for an
## ORTHONORMAL basis - on a basis that carries scale it returns the wrong
## angles. Measured on a cube at (45, 45, 0)deg with a uniform 1.5 scale,
## `get_euler()` reported the X angle as 90deg instead of 45deg: a 45deg
## phantom rotation. With a non-uniform (2, 1, 0.5) scale it reported
## 20.7deg instead of 45deg.
##
## `basis.get_scale()` was NOT at fault - it is exact for R*S (measured: the
## stored scale matched the node's own `scale` in every case).
##
## Every move, scale and rotate gesture ends in `end_move()` / `end_scale()` /
## `end_rotate()`, which build that snapshot and then `execute()` it. So the
## lossy decomposition was not confined to undo - it rewrote the live object
## at the end of every single drag. Moving an object rotated it. That is the
## report.
##
## Why the previous test missed it: `test_modeling_rotate.gd` checked a
## 30deg Y rotation on a (2,3,4) scale, and `get_euler()` happens to be exact
## for a Y-only rotation. The error needs rotation on more than one axis.
##
## The invariant asserted here is stronger and simpler than "the numbers match
## a formula": a move must not change the basis at all, and a scale must change
## the column lengths only. Any rotation introduced by the commit path fails.

var _fail := 0
var _lab: ModelingLab

func _ready() -> void:
	var tree := get_tree()
	_lab = (load("res://scenes/modeling_lab/modeling_lab.tscn") as PackedScene).instantiate()
	add_child(_lab)
	tree.create_timer(20.0).timeout.connect(_on_watchdog)
	await tree.process_frame
	await tree.process_frame
	_lab._enter_creative_studio()
	await tree.process_frame
	_lab._on_spawn_selected(PrimitiveDef.Type.CUBE)
	await tree.process_frame

	var cube: MeshInstance3D = _lab.selection_manager.get_selected()
	if cube == null:
		_fail += 1
		print("FAIL: could not spawn a cube to test with")
		_finish()
		return

	await _test_move_preserves_basis(cube)
	await _test_scale_preserves_orientation(cube)
	await _test_undo_restores_basis(cube)
	_finish()

## A move translates. It cannot change orientation or size, so any basis
## difference at all is a defect - no tolerance is needed or granted.
func _test_move_preserves_basis(cube: MeshInstance3D) -> void:
	var cases: Array = [
		["rot 45/45/0  scale 1", Vector3(45, 45, 0), Vector3.ONE],
		["rot 45/45/0  scale 1.5 uniform", Vector3(45, 45, 0), Vector3(1.5, 1.5, 1.5)],
		["rot 45/45/0  scale 2/1/0.5", Vector3(45, 45, 0), Vector3(2, 1, 0.5)],
		["rot 30/20/10 scale 2/1/0.5", Vector3(30, 20, 10), Vector3(2, 1, 0.5)],
		["rot 10/80/170 scale 3/2/1", Vector3(10, 80, 170), Vector3(3, 2, 1)],
		["rot 0/0/0    scale 2/3/4", Vector3.ZERO, Vector3(2, 3, 4)],
	]
	for c in cases:
		var label: String = c[0]
		cube.rotation_degrees = c[1]
		cube.scale = c[2]
		cube.position = Vector3(0, 0, 0)
		await get_tree().process_frame
		var want: Basis = cube.basis

		_lab.transform_manager.begin_move(Vector3.RIGHT)
		_lab.transform_manager.apply_move(Vector3.RIGHT, 1.5)
		_lab.transform_manager.end_move()
		await get_tree().process_frame

		var got: Basis = cube.basis
		var delta := _basis_delta(want, got)
		if delta > 0.0001:
			_fail += 1
			print("FAIL: move altered the basis of [%s] by %.6f (phantom rotation %.3f deg)" % [
				label, delta, _rot_delta_deg(want, got)])
		if not is_equal_approx(cube.position.x, 1.5):
			_fail += 1
			print("FAIL: move did not translate [%s], position.x = %.4f" % [label, cube.position.x])

## A scale changes the basis' column lengths and nothing else: the orientation
## must survive, and the result must stay a clean R*S with no shear.
func _test_scale_preserves_orientation(cube: MeshInstance3D) -> void:
	var cases: Array = [
		["rot 45/45/0  scale 1", Vector3(45, 45, 0), Vector3.ONE],
		["rot 45/45/0  scale 1.5 uniform", Vector3(45, 45, 0), Vector3(1.5, 1.5, 1.5)],
		["rot 45/45/0  scale 2/1/0.5", Vector3(45, 45, 0), Vector3(2, 1, 0.5)],
		["rot 30/20/10 scale 2/1/0.5", Vector3(30, 20, 10), Vector3(2, 1, 0.5)],
		["rot 10/80/170 scale 3/2/1", Vector3(10, 80, 170), Vector3(3, 2, 1)],
	]
	for c in cases:
		var label: String = c[0]
		cube.rotation_degrees = c[1]
		cube.scale = c[2]
		cube.position = Vector3.ZERO
		await get_tree().process_frame
		var want_basis: Basis = cube.basis

		_lab.transform_manager.begin_scale(true)
		_lab.transform_manager.apply_scale(Vector3.ZERO, 40.0, true)
		_lab.transform_manager.end_scale()
		await get_tree().process_frame

		var got: Basis = cube.basis
		var rot_delta := _rot_delta_deg(want_basis, got)
		if rot_delta > 0.05:
			_fail += 1
			print("FAIL: scale rotated [%s] by %.4f deg" % [label, rot_delta])
		# No shear: the basis must be exactly rotation * diag(scale).
		var ideal: Basis = Basis(want_basis.get_rotation_quaternion()) * Basis.from_scale(got.get_scale())
		var delta := _basis_delta(ideal, got)
		if delta > 0.001:
			_fail += 1
			print("FAIL: scale introduced shear into [%s] (delta %.6f)" % [label, delta])
		if not got.get_scale().is_equal_approx(cube.scale):
			_fail += 1
			print("FAIL: scale disagreed with the node on [%s]: basis %s vs node %s" % [
				label, str(got.get_scale()), str(cube.scale)])

## The undo record must restore the basis bit-for-bit, not approximately.
func _test_undo_restores_basis(cube: MeshInstance3D) -> void:
	cube.rotation_degrees = Vector3(45, 45, 0)
	cube.scale = Vector3(2, 1, 0.5)
	cube.position = Vector3(0, 0, 0)
	await get_tree().process_frame
	var want: Basis = cube.basis
	var want_pos: Vector3 = cube.position

	_lab.transform_manager.begin_move(Vector3.UP)
	_lab.transform_manager.apply_move(Vector3.UP, 3.0)
	_lab.transform_manager.end_move()
	await get_tree().process_frame

	_lab.undo_redo.undo()
	await get_tree().process_frame

	var delta := _basis_delta(want, cube.basis)
	if delta > 0.0001:
		_fail += 1
		print("FAIL: undo did not restore the basis (delta %.6f, phantom rotation %.3f deg)" % [
			delta, _rot_delta_deg(want, cube.basis)])
	if not cube.position.is_equal_approx(want_pos):
		_fail += 1
		print("FAIL: undo did not restore the position: %s vs %s" % [str(cube.position), str(want_pos)])

func _basis_delta(a: Basis, b: Basis) -> float:
	var m := 0.0
	for r in 3:
		for c in 3:
			m = maxf(m, absf(a[r][c] - b[r][c]))
	return m

func _rot_delta_deg(a: Basis, b: Basis) -> float:
	return rad_to_deg(a.get_rotation_quaternion().angle_to(b.get_rotation_quaternion()))

func _finish() -> void:
	if _fail == 0:
		print("PASS: move / scale / undo leave the basis untouched")
	get_tree().quit(1 if _fail else 0)

func _on_watchdog() -> void:
	print("FAIL: watchdog fired, test did not complete")
	get_tree().quit(2)