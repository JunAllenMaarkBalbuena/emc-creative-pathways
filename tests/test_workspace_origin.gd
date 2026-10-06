extends Node

## Regression test: the modeling workspace's coordinate frame sits on the world
## origin, so "local" and "world" agree about the floor.
##
## The bug. `workspace.tscn` had the `Workspace` root node saved with
##     transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.092357635, 0)
## - an editor nudge accidentally baked into the scene, present since the file
## was first committed (8f62c82, 2026-09-15). `ObjectContainer` is a child of it,
## so EVERY object's local frame was shifted 0.09 above the world origin.
##
## The visible symptom: type 0 into World Position Y and the object's world
## position is exactly 0 - but the Local Position Y row and the bottom bar both
## read -0.09, because the Local row is honest about a frame that is not on the
## origin. Measured: global y 0.000000000, local y -0.092357635.
##
## Secondary damage, which is the reason this is not cosmetic: setting World Y
## to 0 sank the object BELOW the floor. It reads as 0 in the World row while
## being buried in the ground plane.
##
## Two independent pieces of evidence say the origin is what was intended, and
## this test asserts both so the offset cannot silently come back:
##   - `GridPlane` sits at local y = -0.005, a deliberate gap that stops content
##     resting at y = 0 z-fighting with the ground
##   - the spawner places a unit cube at local y = 0.5, i.e. exactly half-height,
##     so its underside lands on local y = 0

var _fail := 0
var _done := 0
var _lab: ModelingLab
var _workspace: Node3D

const SUB_TESTS := 4

## Tight: these compare node transforms, not widget text, so there is no 0.01
## SpinBox quantisation to absorb.
const EPS := 1e-4


func _ready() -> void:
	_lab = (load("res://scenes/modeling_lab/modeling_lab.tscn") as PackedScene).instantiate()
	add_child(_lab)
	await _settle()
	_lab._enter_creative_studio()
	await _settle()
	_workspace = _lab.get_node_or_null(
			"SubViewportContainer/SubViewport/Workspace") as Node3D

	await _test_workspace_root_sits_on_the_world_origin()
	await _test_object_container_inherits_the_origin()
	await _test_a_fresh_primitive_rests_on_the_world_floor()
	await _test_zeroing_world_position_y_also_reads_zero_locally()

	_finish()


func _settle() -> void:
	for _i in 6:
		await get_tree().process_frame


# ── sub-tests ─────────────────────────────────────────────────────

## The fix itself, asserted on the node that carries the defect.
func _test_workspace_root_sits_on_the_world_origin() -> void:
	if not await _ready_or_fail():
		return
	var o := _workspace.transform.origin
	if absf(o.x) > EPS or absf(o.y) > EPS or absf(o.z) > EPS:
		_fail += 1
		print("FAIL: the Workspace root is offset to %s. Every object's Local "
			% str(o)
			+ "position is measured in that shifted frame, so Local and World "
			+ "disagree about where the floor is.")
		return
	# Position alone is not enough - a rotated or scaled frame would break the
	# Local/World agreement just as badly while leaving the origin at 0.
	var b := _workspace.transform.basis
	if not b.is_equal_approx(Basis.IDENTITY):
		_fail += 1
		print("FAIL: the Workspace root is rotated or scaled (%s), so the Local "
			% str(b) + "and World inspector rows mean different frames.")
		return
	_done += 1
	print("      the Workspace root is at identity")


func _test_object_container_inherits_the_origin() -> void:
	if not await _ready_or_fail():
		return
	var container := _workspace.get_node_or_null("ObjectContainer") as Node3D
	if container == null:
		_fail += 1
		print("FAIL: there is no ObjectContainer under Workspace")
		return
	var o := container.global_transform.origin
	if o.length() > EPS:
		_fail += 1
		print("FAIL: ObjectContainer is at world %s rather than the origin"
			% str(o))
		return
	_done += 1
	print("      ObjectContainer inherits the origin")


## The spawner's own assumption, checked as an outcome rather than as a constant:
## whatever primitive it places must come to rest ON the floor, not floating.
func _test_a_fresh_primitive_rests_on_the_world_floor() -> void:
	if not await _ready_or_fail():
		return
	_lab.selection_manager.deselect_all()
	_lab._on_spawn_selected(PrimitiveDef.Type.CUBE)
	await _settle()
	var obj := _lab.selection_manager.get_selected() as Node3D
	if obj == null:
		_fail += 1
		print("FAIL: nothing was selected after spawning")
		return
	# A unit cube centred at y = 0.5 has its underside at y = 0.
	var underside: float = obj.global_position.y - 0.5
	if absf(underside) > EPS:
		_fail += 1
		print("FAIL: a freshly spawned unit cube has its underside at world "
			+ "y=%.6f, so it is %.6f above the floor. It is floating."
			% [underside, underside])
		return
	# And the ground plane must stay just BELOW the floor, or content resting on
	# it z-fights. This is the independent check on the offset: -0.005 was always
	# a deliberate gap, and with a stray offset it drifted to +0.087.
	var grid := _workspace.get_node_or_null("GridPlane") as Node3D
	if grid != null:
		var gy: float = grid.global_position.y
		if gy > -EPS:
			_fail += 1
			print("FAIL: the GridPlane is at world y=%.6f, which is not below the "
				% gy + "floor, so objects resting at y=0 will z-fight with it.")
			return
	_done += 1
	print("      a fresh primitive rests on the world floor (underside y=%.6f)"
		% underside)


## The user's report, verbatim, at the level the user saw it: the World row and
## the Local row must not disagree about a position the user just typed.
func _test_zeroing_world_position_y_also_reads_zero_locally() -> void:
	if not await _ready_or_fail():
		return
	_lab.selection_manager.deselect_all()
	_lab._on_spawn_selected(PrimitiveDef.Type.CUBE)
	await _settle()
	var obj := _lab.selection_manager.get_selected() as Node3D
	if obj == null:
		_fail += 1
		print("FAIL: nothing was selected after spawning")
		return
	# Drive it the way a user does: through the widget, which emits value_changed.
	var world_field := _lab.get_node_or_null("%WPosY") as SpinBox
	world_field.value = 0.0
	await _settle()
	var local_field := _lab.get_node_or_null("%PosY") as SpinBox
	if absf(local_field.value) > 0.006:
		_fail += 1
		print("FAIL: World Position Y was set to 0 and the Local Position Y row "
			+ "reads %s. The two rows disagree about the same point, which is "
			% str(local_field.value)
			+ "what happens whenever the object's frame is not the world frame.")
		return
	var bar := _lab.get_node_or_null("%TransformLabel") as Label
	if bar.text.find("Y: 0.00") < 0:
		_fail += 1
		print("FAIL: the bottom bar reads \"%s\" after zeroing world Y"
			% bar.text)
		return
	_done += 1
	print("      world Y=0 reads 0.00 locally too (bottom bar \"%s\")" % bar.text)


# ── helpers ───────────────────────────────────────────────────────

## Every dependent sub-test bails here rather than crashing partway and being
## counted as a pass by the `_done < SUB_TESTS` check at the end.
func _ready_or_fail() -> bool:
	if _workspace == null:
		_fail += 1
		print("FAIL: there is no Workspace node")
		return false
	return true


func _finish() -> void:
	if _done < SUB_TESTS:
		_fail += SUB_TESTS - _done
		print("FAIL: only %d of %d sub-tests completed - the rest died on an "
			% [_done, SUB_TESTS] + "unreported engine error, so the run above is "
			+ "NOT a pass")
	if _fail == 0:
		print("PASS: the workspace frame sits on the world origin, so a primitive "
			+ "rests on the world floor and zeroing World Position Y reads 0.00 "
			+ "in the Local row and the bottom bar too")
	get_tree().quit(1 if _fail else 0)
