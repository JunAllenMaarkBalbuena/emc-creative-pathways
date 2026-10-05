class_name TransformManager
extends RefCounted

var _selection_manager: SelectionManager
var _snap_settings: SnapSettings
var _hierarchy_manager: HierarchyManager
var _undo_redo: CommandManager
var _spawner: PrimitiveSpawner
var _material_mgr: MaterialManager
var _nodes: Array[MeshInstance3D] = []
var _original_positions: Array[Vector3] = []
var _original_bases: Array[Basis] = []
var _group_center: Vector3 = Vector3.ZERO
var _transforming: bool = false
## Axis and total angle of the rotation gesture in progress. See apply_rotate.
var _rot_axis: Vector3 = Vector3.ZERO
var _rot_accumulated: float = 0.0

func _init(sm: SelectionManager, ss: SnapSettings, hm: HierarchyManager, ur: CommandManager, sp: PrimitiveSpawner, mm: MaterialManager):
	_selection_manager = sm
	_snap_settings = ss
	_hierarchy_manager = hm
	_undo_redo = ur
	_spawner = sp
	_material_mgr = mm

func _snapshot() -> bool:
	var nodes := _selected_nodes()
	if nodes.is_empty():
		return false
	_nodes = nodes
	_original_positions.clear()
	_original_bases.clear()
	var acc := Vector3.ZERO
	for n in _nodes:
		# Local position. The workspace root carries a world Y-offset, so
		# global_position would smear that offset into the delta the caller
		# compares against the object's local position.
		_original_positions.append(n.position)
		_original_bases.append(n.transform.basis)
		acc += n.position
	_group_center = acc / _nodes.size()
	return true

func _selected_nodes() -> Array[MeshInstance3D]:
	var multi := _selection_manager.selected_nodes()
	if multi.size() > 0:
		return multi
	var sel := _selection_manager.get_selected()
	if sel:
		return [sel]
	return []

func begin_move(_axis: Vector3) -> bool:
	_transforming = _snapshot()
	return _transforming

func apply_move(axis: Vector3, delta_distance: float):
	if not _transforming: return
	var move := axis * delta_distance
	for i in _nodes.size():
		var new_pos := _original_positions[i] + move
		if _snap_settings.snap_enabled:
			new_pos = _snap_settings.snap_vector3(new_pos, _snap_settings.position_snap)
		_nodes[i].position = new_pos

func apply_move_delta(delta: Vector3):
	if not _transforming: return
	for i in _nodes.size():
		var new_pos := _original_positions[i] + delta
		if _snap_settings.snap_enabled:
			new_pos = _snap_settings.snap_vector3(new_pos, _snap_settings.position_snap)
		_nodes[i].position = new_pos

func end_move():
	if _transforming:
		var paths: Array[NodePath] = []
		var befores: Array[Transform3D] = []
		var afters: Array[Transform3D] = []
		for i in _nodes.size():
			paths.append(_hierarchy_manager.get_container().get_path_to(_nodes[i]))
			befores.append(Transform3D(_original_bases[i], _original_positions[i]))
			afters.append(_nodes[i].transform)
		var action := CommandFactory.transform(paths, befores, afters,
			_hierarchy_manager.get_container(), _spawner, _material_mgr, _hierarchy_manager)
		_undo_redo.execute_command(action)
		# transform mutates the live nodes in place, so the IDs handed back are
		# the ones already selected. Re-pointing is idempotent and keeps this
		# call site correct if that ever changes.
		_selection_manager.reselect_from_ids(action.get_last_created_ids())
	_transforming = false

func begin_rotate(_axis: Vector3) -> bool:
	_transforming = _snapshot()
	_rot_axis = Vector3.ZERO
	_rot_accumulated = 0.0
	return _transforming

## `gesture_angle` is the ABSUTE rotation for this drag, measured from the grab
## point - NOT an increment. modeling_lab.gd computes
## `(mouse_pos - _drag_start_mouse).dot(perp) * SENSITIVITY`, which is the
## cursor's whole offset from where the button went down.
##
## Accumulating it here was a real bug: feeding an absolute offset into an
## accumulator adds the whole gesture once per motion event, so the rotation
## accelerated (40px of drag produced 22.9deg instead of 9.2deg) and dragging
## BACK toward the grab point still rotated forward - 40px to 20px went 22.9deg
## to 27.5deg. It only reversed once the cursor crossed back past the grab
## point. Treat the value as absolute and the mapping is 1:1 and reversible.
##
## The snap is applied to that total ON EVERY MOUSE-MOTION EVENT, exactly as
## `apply_move` snaps position - there is no deferred snap on mouse release, and
## `end_rotate()` only commits the undo record. So the object visibly clicks
## between detents as you drag rather than jumping once you let go.
func apply_rotate(axis: Vector3, gesture_angle: float):
	if not _transforming: return
	# A different axis mid-gesture means a fresh rotation, not a continuation.
	if _rot_axis != Vector3.ZERO and _rot_axis != axis:
		_rot_accumulated = 0.0
	_rot_axis = axis
	_rot_accumulated = gesture_angle
	var total := _rot_accumulated
	var snap := 0.0
	if _snap_settings.snap_enabled and _snap_settings.rotation_snap_enabled:
		snap = _snap_settings.rotation_snap
	if snap > 0.0:
		total = deg_to_rad(_snap_settings.snap_value(rad_to_deg(total), snap))
	var rot := Basis(axis, total)
	for i in _nodes.size():
		# Compose the rotation onto the ORIGINAL basis rather than the live
		# one. The live basis already carries the rotation from the previous
		# frame, so composing onto it compounds the rotation every frame.
		#
		# Scale lives in the basis too, so `rot * original_basis` carries the
		# snapshotted scale through - a scale change made while the rotation
		# drag is live is reverted, which is the "rotating resets the object"
		# half of the report.
		var new_basis := rot * _original_bases[i]
		var rel := _original_positions[i] - _group_center
		var new_pos := _group_center + rot * rel
		_nodes[i].transform = Transform3D(new_basis, new_pos)

func end_rotate():
	if _transforming:
		var paths: Array[NodePath] = []
		var befores: Array[Transform3D] = []
		var afters: Array[Transform3D] = []
		for i in _nodes.size():
			paths.append(_hierarchy_manager.get_container().get_path_to(_nodes[i]))
			befores.append(Transform3D(_original_bases[i], _original_positions[i]))
			afters.append(_nodes[i].transform)
		var action := CommandFactory.transform(paths, befores, afters,
			_hierarchy_manager.get_container(), _spawner, _material_mgr, _hierarchy_manager)
		_undo_redo.execute_command(action)
		_selection_manager.reselect_from_ids(action.get_last_created_ids())
	_transforming = false
	_rot_axis = Vector3.ZERO
	_rot_accumulated = 0.0

func begin_scale(_uniform: bool = true) -> bool:
	_transforming = _snapshot()
	return _transforming

## Scales the gesture's nodes.
##
## `world_frame` picks the frame the scale acts in. Global (the gizmo's default)
## scales along WORLD axes; Local scales along the object's OWN axes.
##
## The two differ only in the ORDER of the same multiply — `factor_v * basis`
## scales column i by factor_v[i], `basis * factor_v` likewise, but left vs
## right multiplication is the whole difference between "stretched along world X"
## and "stretched along the object's X". Both preserve shear; neither can be
## expressed as a `.scale` write.
##
## `axis` must be the handle axis in the GIZMO's frame, not in world space. The
## `axis.x != 0` component test below picks *which* handle was grabbed, and under
## Local a 45deg-yawed local-X handle has a world direction with both x and z
## non-zero — feeding that in would scale two axes at once.
##
## NEVER route this through `node.scale`. That setter decomposes the basis into
## rotation + scale and discards the shear, which is the same bug class as the
## get_euler() commit bug: measured, a round trip through `.scale` moves a
## sheared basis by 0.707 while a direct basis write moves it by 0.
func apply_scale(axis: Vector3, delta: float, uniform: bool = true,
		world_frame: bool = false):
	if not _transforming: return
	var factor: float = max(0.01, 1.0 + delta * 0.003)
	var factor_v := Vector3(factor, factor, factor)
	if not uniform:
		factor_v = Vector3.ONE
		if axis.x != 0: factor_v.x = factor
		if axis.y != 0: factor_v.y = factor
		if axis.z != 0: factor_v.z = factor
	for i in _nodes.size():
		var orig: Basis = _original_bases[i]
		# Column lengths, not `node.scale`. For a clean R*S basis the two are
		# identical, but `node.scale` is only a DECOMPOSITION of a sheared basis
		# and loses the shear, so it is the wrong quantity to scale from.
		#
		# `orig[i]` is Basis column indexing - there is no `get_column()` in
		# GDScript.
		var orig_len := Vector3(
				orig[0].length(),
				orig[1].length(),
				orig[2].length())
		orig_len = orig_len.max(Vector3(0.0001, 0.0001, 0.0001))
		var target := orig_len * factor_v
		if _snap_settings.snap_enabled:
			target = _snap_settings.snap_vector3(target, _snap_settings.scale_snap)
		target = target.max(Vector3(0.01, 0.01, 0.01))
		# Snapping works on absolute axis lengths, so the applied factor has to be
		# recomputed from the snapped length back through the original.
		var applied := Vector3(
				target.x / orig_len.x,
				target.y / orig_len.y,
				target.z / orig_len.z)
		var scale_basis := Basis.from_scale(applied)
		var node := _nodes[i]
		node.basis = scale_basis * orig if world_frame else orig * scale_basis
		var rel := _original_positions[i] - _group_center
		if not rel.is_zero_approx():
			node.position = _group_center + rel * factor_v

func end_scale():
	if _transforming:
		var paths: Array[NodePath] = []
		var befores: Array[Transform3D] = []
		var afters: Array[Transform3D] = []
		for i in _nodes.size():
			paths.append(_hierarchy_manager.get_container().get_path_to(_nodes[i]))
			befores.append(Transform3D(_original_bases[i], _original_positions[i]))
			afters.append(_nodes[i].transform)
		var action := CommandFactory.transform(paths, befores, afters,
			_hierarchy_manager.get_container(), _spawner, _material_mgr, _hierarchy_manager)
		_undo_redo.execute_command(action)
		_selection_manager.reselect_from_ids(action.get_last_created_ids())
	_transforming = false

func is_transforming() -> bool:
	return _transforming

func reset_selected():
	var nodes := _selected_nodes()
	if nodes.is_empty():
		return
	var paths: Array[NodePath] = []
	var befores: Array[Transform3D] = []
	var afters: Array[Transform3D] = []
	for n in nodes:
		if not is_instance_valid(n):
			continue
		paths.append(_hierarchy_manager.get_container().get_path_to(n))
		befores.append(n.transform)
		afters.append(Transform3D.IDENTITY)
	var action := CommandFactory.transform(paths, befores, afters,
		_hierarchy_manager.get_container(), _spawner, _material_mgr, _hierarchy_manager)
	_undo_redo.execute_command(action)
	_selection_manager.reselect_from_ids(action.get_last_created_ids())

func center_selected():
	var sel := _selection_manager.get_selected()
	if not sel: return
	var aabb := sel.mesh.get_aabb() if sel.mesh else AABB(Vector3.ZERO, Vector3.ONE)
	var offset := aabb.get_center()
	var after: Transform3D = sel.transform
	after.origin = -offset
	var action := CommandFactory.transform(
		[_hierarchy_manager.get_container().get_path_to(sel)], [sel.transform], [after],
		_hierarchy_manager.get_container(), _spawner, _material_mgr, _hierarchy_manager)
	_undo_redo.execute_command(action)
	_selection_manager.reselect_from_ids(action.get_last_created_ids())