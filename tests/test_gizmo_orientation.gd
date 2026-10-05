extends Node

## Regression test for the gizmo orientation work.
## Plan: docs/plans/2026-10-06-gizmo-orientation.md
## Decisions: docs/decisions/2026-10-05-gizmo-orientation.md
##
## The defect being fixed is a MISMATCH, not a missing mode. Measured before
## any of this was designed:
##
##   move   : position += world_axis * d            -> WORLD
##   rotate : Basis(world_axis, a) * original_basis  -> WORLD
##   scale  : node.scale *= component               -> LOCAL  (basis = R * S)
##   gizmo  : handles drawn from AXES, never rotated -> WORLD
##
## So the red X handle looks world-aligned and moves world-aligned, but the
## stretch it produces runs along the object's OWN local X. Rotate 45deg and the
## handle and the effect point in different directions.
##
## The discriminator used throughout is FRAME-INDEPENDENT, so it does not depend
## on any particular angle:
##
##   Global scale of the original basis B:  new = S * B     =>  new * B^-1 is DIAGONAL
##   Local  scale of the original basis B:  new = B * S'    =>  new * B^-1 is NOT diagonal
##
## `new * B^-1` is diagonal if and only if the scale was applied in world space.
## That is exactly the property under test, stated once.
##
## Feature-detects rather than assuming: before the implementation this reports a
## clean FAIL instead of crashing, so the RED is legible.

var _fail := 0
var _lab: ModelingLab
var _cube: MeshInstance3D

## Yaw chosen because every axis then has a non-trivial world direction, so a
## world-axis scale and a local-axis scale cannot coincide by accident.
const YAW := 45.0

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

	_cube = _lab.selection_manager.get_selected()
	if _cube == null:
		_fail += 1
		print("FAIL: could not spawn a cube to test with")
		_finish()
		return

	await _test_apply_scale_accepts_a_world_frame()
	await _test_gizmo_handles_actually_rotate()
	await _test_orientation_survives_the_sizing_pass()
	await _test_axis_to_world_follows_the_frame()
	await _test_global_scale_is_world_axis()
	await _test_local_scale_stays_local()
	await _test_shear_survives_undo()
	await _test_inspector_reports_effective_lengths()
	await _test_inspector_edit_preserves_shear()
	await _test_global_is_the_default()
	_finish()

## The panel's Scale fields must report the object's real axis lengths.
##
## Worth pinning down even though it turns out `node.scale` already reported the
## same thing: `Basis.get_scale()` returns the column lengths, verified equal to
## the last digit on a sheared basis, so the readout was never the broken half.
## This locks the number in so a future refactor to `node.scale` on the write
## side cannot quietly start rounding the display to a decomposition.
func _test_inspector_reports_effective_lengths() -> void:
	await _reset_cube()
	_lab.transform_manager.begin_scale(false)
	_apply_scale(Vector3.RIGHT, 40.0, false, true)
	_lab.transform_manager.end_scale()
	await get_tree().process_frame

	if not _is_sheared(_cube.basis):
		_fail += 1
		print("FAIL: setup produced no shear; this sub-test is not testing anything")
		return

	_lab._update_inspector(_cube)
	var expected := _effective_axis_lengths(_cube.basis)
	var shown := Vector3(_spin("ScaleX"), _spin("ScaleY"), _spin("ScaleZ"))
	# The Scale fields are SpinBoxes with step 0.01, so they quantise whatever they
	# are given. That was equally true when they were fed `node.scale` — it is the
	# widget's resolution, not a fault in this change — so the invariant is that
	# the readout is correct TO the widget's resolution, i.e. within half a step.
	if shown.distance_to(expected) > 0.005:
		_fail += 1
		print("FAIL: inspector shows %s but the object's axes are %s" % [shown, expected])
	else:
		print("      inspector reports effective axis lengths %s (widget quantises to "
			% shown + "0.01; true values %s)" % expected)

## Read and write must be the same quantity. The old write orthonormalised first,
## so touching the panel flattened a sheared object back to R*S; and it read
## `sel.scale` while the readout uses real lengths, so a round trip through the
## panel turned one basis into a different one.
func _test_inspector_edit_preserves_shear() -> void:
	await _reset_cube()
	_lab.transform_manager.begin_scale(false)
	_apply_scale(Vector3.RIGHT, 40.0, false, true)
	_lab.transform_manager.end_scale()
	await get_tree().process_frame
	if not _is_sheared(_cube.basis):
		_fail += 1
		print("FAIL: setup produced no shear; this sub-test is not testing anything")
		return

	var before: Basis = _cube.basis
	var before_len := _effective_axis_lengths(before)
	# Move the Y axis. X and Z must be untouched and the shear must survive.
	_lab._on_inspector_scale_changed(before_len.y * 2.0, "y")
	await get_tree().process_frame
	# The command rebuilds node instances, so re-fetch rather than trust the old
	# reference (same trap as the undo sub-test).
	var after_node := _lab.selection_manager.get_selected()
	if after_node == null:
		_fail += 1
		print("FAIL: selection lost after the inspector edit")
		return
	var after: Basis = after_node.basis
	var after_len := _effective_axis_lengths(after)

	if not _is_sheared(after):
		_fail += 1
		print("FAIL: editing an inspector scale field flattened the shear")
	if absf(after_len.y - before_len.y * 2.0) > 0.0005:
		_fail += 1
		print("FAIL: Y length went %.4f -> %.4f, expected %.4f"
			% [before_len.y, after_len.y, before_len.y * 2.0])
	if absf(after_len.x - before_len.x) > 0.0005 \
			or absf(after_len.z - before_len.z) > 0.0005:
		_fail += 1
		print("FAIL: editing Y also moved X or Z (%.4f,%.4f -> %.4f,%.4f)"
			% [before_len.x, before_len.z, after_len.x, after_len.z])

## A 90-degree yaw about UP sends the X handle to world -Z (Godot's Y rotation
## is right-handed: X -> (cos, 0, -sin)).
const YAWED_X := Vector3(0.0, 0.0, -1.0)

func _handles() -> Node3D:
	return _lab.gizmo.get_node_or_null("Handles") as Node3D

## Reads the NODE, not the stored variable. An implementation that stashed the
## basis and never applied it would pass a test that only checked the field.
func _test_gizmo_handles_actually_rotate() -> void:
	if not _lab.gizmo.has_method("set_orientation"):
		_fail += 1
		print("FAIL: Gizmo3D has no set_orientation()")
		return
	var handles := _handles()
	if handles == null:
		_fail += 1
		print("FAIL: gizmo has no Handles node to rotate")
		return

	_lab.gizmo.set_orientation(Basis(Quaternion(Vector3.UP, deg_to_rad(90.0))))
	var got := (handles.basis * Vector3.RIGHT).normalized()
	if got.distance_to(YAWED_X) > 0.001:
		_fail += 1
		print("FAIL: set_orientation(90deg yaw) left the X handle at %s, expected %s"
			% [got, YAWED_X])
	else:
		print("      set_orientation rotates the handles in the node tree")

## SMOKE CHECK, not a regression test - and the distinction matters.
##
## The plan predicted that the constant-on-screen sizing, which runs every frame,
## would write `.scale`, decompose the basis, and snap the handles back to world
## axes while the code still believed it was in Local mode. That was tested by
## reverting the implementation to a plain `.scale` assignment: the assertion
## still passed, rotation delta 0.0000. `Basis.set_scale` preserves the rotation
## part, so the predicted bug does not exist.
##
## Kept as a cheap invariant on the one thing that IS real - `set_orientation`
## writes immediately and stays written for as long as the gizmo is shown at any
## camera distance. It does not distinguish `.scale` from composition, and should
## not be read as if it did.
func _test_orientation_survives_the_sizing_pass() -> void:
	if not _lab.gizmo.has_method("set_orientation"):
		return
	var handles := _handles()
	if handles == null:
		return

	_lab.gizmo.set_orientation(Basis(Quaternion(Vector3.UP, deg_to_rad(90.0))))
	var applied: Basis = handles.basis
	# Two frames, not one: the sizing pass also needs a visible gizmo and a
	# camera distance above zero to write at all.
	await get_tree().process_frame
	await get_tree().process_frame
	var after: Basis = handles.basis

	# Compare the ROTATION, not the whole basis. The constant-on-screen sizing
	# legitimately rescales the handles every frame - the gizmo grows as the
	# camera pulls back - so comparing raw matrices measures that intended size
	# change, not an orientation rewrite. (An earlier version of this assertion
	# compared raw bases and reported delta 0.4375 for a gizmo that had simply
	# resized: the test was wrong, the code was right.)
	#
	# Orthonormalising strips the uniform size and leaves the frame, which is
	# exactly the property under test: a `.scale` write decomposes the basis and
	# would restore the rotation part to the world axes.
	var d := _basis_delta(applied.orthonormalized(), after.orthonormalized())
	if d > 0.0001:
		_fail += 1
		print("FAIL: the per-frame sizing pass rewrote the handle orientation "
			+ "(rotation delta %.6f after 2 frames) - it is assigning .scale "
			% d + "instead of composing the basis")
	else:
		print("      handle orientation survives the per-frame sizing pass")

## The Area meta stores the LOCAL axis, so every consumer that needs a world
## direction has to convert it. Under Global that must be a no-op, or move and
## rotate would change behaviour just by adding the toggle.
func _test_axis_to_world_follows_the_frame() -> void:
	if not _lab.gizmo.has_method("axis_to_world"):
		_fail += 1
		print("FAIL: Gizmo3D has no axis_to_world()")
		return

	_lab.gizmo.set_orientation(Basis.IDENTITY)
	if _lab.gizmo.axis_to_world(Vector3.RIGHT).distance_to(Vector3.RIGHT) > 0.001:
		_fail += 1
		print("FAIL: axis_to_world is not a no-op under Global")

	_lab.gizmo.set_orientation(Basis(Quaternion(Vector3.UP, deg_to_rad(90.0))))
	if _lab.gizmo.axis_to_world(Vector3.RIGHT).distance_to(YAWED_X) > 0.001:
		_fail += 1
		print("FAIL: axis_to_world did not rotate the local X handle into world space")
	else:
		print("      axis_to_world converts local handle axes into world space")

## The world-frame argument is what distinguishes the two modes. If it is
## missing the implementation has not started, so say that rather than crashing
## on an argument-count error halfway through the suite.
##
## Dispatch goes through a Callable on purpose: GDScript validates call arity at
## PARSE time, so a direct 4-argument call makes the whole script fail to load
## and the RED says nothing about which behaviour is wrong. Dynamic dispatch
## turns it into a runtime check this function can report.
func _test_apply_scale_accepts_a_world_frame() -> void:
	var n := _arity(_lab.transform_manager, "apply_scale")
	if n < 4:
		_fail += 1
		print("FAIL: apply_scale takes %d args, needs 4 (axis, delta, uniform, world_frame)" % n)
	else:
		print("      apply_scale arity %d - world-frame parameter present" % n)

## Dynamic call to apply_scale.
##
## When the world-frame parameter does not exist yet, a Global request cannot be
## satisfied and this returns false so the caller reports a legible FAIL. A Local
## request is different: local IS the pre-existing behaviour, so it falls back to
## the 3-argument call and is genuinely asserted from the start. That asymmetry
## matters - it means this sub-test proves the discriminator works (Local is
## measurably NOT a world-axis scale) instead of merely asserting it.
func _apply_scale(axis: Vector3, delta: float, uniform: bool, world_frame: bool) -> bool:
	if _arity(_lab.transform_manager, "apply_scale") >= 4:
		Callable(_lab.transform_manager, "apply_scale").call(axis, delta, uniform, world_frame)
		return true
	if world_frame:
		return false
	Callable(_lab.transform_manager, "apply_scale").call(axis, delta, uniform)
	return true

## Global: the scale must be applied in WORLD space, so the basis change is a
## pure left-multiplication and carries shear.
func _test_global_scale_is_world_axis() -> void:
	await _reset_cube()
	var orig: Basis = _cube.basis
	_lab.transform_manager.begin_scale(false)
	if not _apply_scale(Vector3.RIGHT, 40.0, false, true):
		_fail += 1
		print("FAIL: apply_scale has no world-frame parameter, so a Global scale "
			+ "cannot be expressed")
		return
	_lab.transform_manager.end_scale()
	await get_tree().process_frame

	var got: Basis = _cube.basis
	if _is_diagonal(got * orig.inverse(), 0.0001):
		print("      Global X scale is a world-axis (sheared) basis - correct")
	else:
		_fail += 1
		print("FAIL: Global X scale on a yawed node was not a world-axis scale "
			+ "(new * orig^-1 is not diagonal, off-diagonal max %.6f)"
			% _offdiagonal(got * orig.inverse()))

## Local: the scale must be applied in the object's OWN frame, which is exactly
## what the code does today. This asserts the existing behaviour is PRESERVED,
## so the fix cannot quietly regress the mode it is meant to leave alone.
func _test_local_scale_stays_local() -> void:
	await _reset_cube()
	var orig: Basis = _cube.basis
	_lab.transform_manager.begin_scale(false)
	if not _apply_scale(Vector3.RIGHT, 40.0, false, false):
		_fail += 1
		print("FAIL: Local scale could not be applied at all")
		return
	_lab.transform_manager.end_scale()
	await get_tree().process_frame

	var got: Basis = _cube.basis
	if _offdiagonal(got * orig.inverse()) > 0.01:
		print("      Local X scale is a local-axis basis - correct")
	else:
		_fail += 1
		print("FAIL: Local X scale came out as a world-axis scale; the local "
			+ "mode is not distinct from global (off-diagonal %.6f)"
			% _offdiagonal(got * orig.inverse()))

	# Local scale must not shear: the basis has to stay a clean R * S.
	var ideal: Basis = Basis(orig.get_rotation_quaternion()) * Basis.from_scale(got.get_scale())
	var d := _basis_delta(ideal, got)
	if d > 0.001:
		_fail += 1
		print("FAIL: Local scale introduced shear (delta %.6f)" % d)

## A sheared basis has no TRS representation, so it is the case most likely to
## be destroyed in transit. Undo replays a stored snapshot; the result must come
## back as the same matrix.
func _test_shear_survives_undo() -> void:
	await _reset_cube()
	var orig: Basis = _cube.basis
	var orig_pos: Vector3 = _cube.position

	_lab.transform_manager.begin_scale(false)
	if not _apply_scale(Vector3.RIGHT, 40.0, false, true):
		_fail += 1
		print("FAIL: apply_scale has no world-frame parameter, so a sheared "
			+ "basis cannot be produced to test")
		return
	_lab.transform_manager.end_scale()
	await get_tree().process_frame

	var sheared: Basis = _cube.basis
	# "Is this sheared?" is NOT the `new * orig^-1` diagonal test used above. That
	# test asks "was the scale applied in world space", and a Global scale — the
	# very thing being set up here — is DIAGONAL by definition. Asking it that
	# question made this sub-test reject its own setup.
	#
	# The right question is whether the basis is still expressible as R * S. Shear
	# exists exactly when it is not.
	if not _is_sheared(sheared):
		_fail += 1
		print("FAIL: setup did not produce a sheared basis; this sub-test is "
			+ "not testing anything")
		return

	_lab.undo_redo.undo()
	await get_tree().process_frame

	var d := _basis_delta(orig, _cube.basis)
	if d > 0.0001:
		_fail += 1
		print("FAIL: undo did not restore a sheared basis (delta %.6f)" % d)
	elif not _cube.position.is_equal_approx(orig_pos):
		_fail += 1
		print("FAIL: undo did not restore the position")
	else:
		print("      a sheared basis survives an undo round trip")

## The decision record makes Global the default. A Local default would mean the
## default drawing lies in the other direction, which is the bug being fixed.
func _test_global_is_the_default() -> void:
	if not _lab.has_method("set_gizmo_orientation"):
		_fail += 1
		print("FAIL: ModelingLab has no set_gizmo_orientation() - the orientation "
			+ "toggle does not exist yet")
		return
	if not _lab.has_method("gizmo_orientation"):
		_fail += 1
		print("FAIL: ModelingLab exposes no gizmo_orientation to read the default from")
		return

	var orient: int = _lab.gizmo_orientation()
	if orient == 0:
		print("      default orientation is GLOBAL - correct")
	else:
		_fail += 1
		print("FAIL: default orientation is %d, expected 0 (GLOBAL)" % orient)

## Same quantity the production read path uses: a basis's columns ARE its axes,
## so their lengths are the real scale even under shear.
func _effective_axis_lengths(basis: Basis) -> Vector3:
	return Vector3(basis[0].length(), basis[1].length(), basis[2].length())


func _spin(name: String) -> float:
	var box := _lab.get_node_or_null("%" + name) as SpinBox
	if box == null:
		_fail += 1
		print("FAIL: no inspector field named %s" % name)
		return NAN
	return box.value


func _reset_cube() -> void:
	_cube.rotation_degrees = Vector3(0, YAW, 0)
	_cube.scale = Vector3.ONE
	_cube.position = Vector3.ZERO
	await get_tree().process_frame

## True when every off-diagonal entry is within `eps` of zero.
func _is_diagonal(m: Basis, eps: float) -> bool:
	return _offdiagonal(m) <= eps

## True when the basis cannot be written as a clean rotation * uniform/non-uniform
## scale. Rebuilding R*S from the basis's own rotation part and column lengths and
## comparing is the direct test: any shear shows up as the difference.
##
## This is the complement of `_is_diagonal(got * orig^-1)`. Both are used, for
## different questions — see `_test_shear_survives_undo`, where using the wrong
## one made the sub-test reject its own setup.
func _is_sheared(b: Basis, eps: float = 0.001) -> bool:
	var rotation := Basis(b.get_rotation_quaternion())
	var ideal := rotation * Basis.from_scale(b.get_scale())
	return _basis_delta(ideal, b) > eps

func _offdiagonal(m: Basis) -> float:
	var worst := 0.0
	for r in 3:
		for c in 3:
			if r != c:
				worst = maxf(worst, absf(m[r][c]))
	return worst

func _basis_delta(a: Basis, b: Basis) -> float:
	var m := 0.0
	for r in 3:
		for c in 3:
			m = maxf(m, absf(a[r][c] - b[r][c]))
	return m

func _arity(obj: Object, method: String) -> int:
	for m in obj.get_method_list():
		if m.get("name", "") == method:
			return (m.get("args", []) as Array).size()
	return -1

func _finish() -> void:
	if _fail == 0:
		print("PASS: global scale is world-axis with shear, local scale is local, "
			+ "shear survives undo, global is the default")
	get_tree().quit(1 if _fail else 0)

func _on_watchdog() -> void:
	print("FAIL: watchdog fired, test did not complete")
	get_tree().quit(2)