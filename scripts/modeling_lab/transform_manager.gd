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
var _original_scales: Array[Vector3] = []
var _group_center: Vector3 = Vector3.ZERO
var _transforming: bool = false

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
	_original_scales.clear()
	var acc := Vector3.ZERO
	for n in _nodes:
		# Local position. The workspace root carries a world Y-offset, so
		# global_position would smear that offset into the delta the caller
		# compares against the object's local position.
		_original_positions.append(n.position)
		_original_bases.append(n.transform.basis)
		_original_scales.append(n.scale)
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
		var paths: Array = []
		var befores: Array = []
		var afters: Array = []
		for i in _nodes.size():
			paths.append(_hierarchy_manager.get_container().get_path_to(_nodes[i]))
			befores.append(Transform3D(_original_bases[i], _original_positions[i]))
			afters.append(_nodes[i].transform)
		var action := CommandFactory.transform(paths, befores, afters,
			_hierarchy_manager.get_container(), _spawner, _material_mgr, _hierarchy_manager)
		_undo_redo.execute_command(action)
		# The command rebuilds node instances (frees originals, materializes
		# fresh copies). Re-point the selection onto those new instances so the
		# gizmo keeps tracking live nodes instead of silently going stale.
		_selection_manager.reselect_from_ids(action.get_last_created_ids())
	_transforming = false

func begin_rotate(_axis: Vector3) -> bool:
	_transforming = _snapshot()
	return _transforming

func apply_rotate(axis: Vector3, delta_angle: float):
	if not _transforming: return
	var snap := _snap_settings.rotation_snap if _snap_settings.snap_enabled else 0.0
	var angle := delta_angle
	if snap > 0:
		angle = _snap_settings.snap_value(rad_to_deg(delta_angle), snap)
		angle = deg_to_rad(angle)
	var rot := Basis(axis, angle)
	for i in _nodes.size():
		var new_basis := rot * _original_bases[i]
		var rel := _original_positions[i] - _group_center
		var new_pos := _group_center + rot * rel
		_nodes[i].transform = Transform3D(new_basis, new_pos)

func end_rotate():
	if _transforming:
		var paths: Array = []
		var befores: Array = []
		var afters: Array = []
		for i in _nodes.size():
			paths.append(_hierarchy_manager.get_container().get_path_to(_nodes[i]))
			befores.append(Transform3D(_original_bases[i], _original_positions[i]))
			afters.append(_nodes[i].transform)
		var action := CommandFactory.transform(paths, befores, afters,
			_hierarchy_manager.get_container(), _spawner, _material_mgr, _hierarchy_manager)
		_undo_redo.execute_command(action)
		_selection_manager.reselect_from_ids(action.get_last_created_ids())
	_transforming = false

func begin_scale(_uniform: bool = true) -> bool:
	_transforming = _snapshot()
	return _transforming

func apply_scale(axis: Vector3, delta: float, uniform: bool = true):
	if not _transforming: return
	var factor: float = max(0.01, 1.0 + delta * 0.003)
	var factor_v := Vector3(factor, factor, factor)
	if not uniform:
		factor_v = Vector3.ONE
		if axis.x != 0: factor_v.x = factor
		if axis.y != 0: factor_v.y = factor
		if axis.z != 0: factor_v.z = factor
	for i in _nodes.size():
		var s := _original_scales[i]
		s *= factor_v
		if _snap_settings.snap_enabled:
			s = _snap_settings.snap_vector3(s, _snap_settings.scale_snap)
		s = s.max(Vector3(0.01, 0.01, 0.01))
		_nodes[i].scale = s
		var rel := _original_positions[i] - _group_center
		if not rel.is_zero_approx():
			_nodes[i].position = _group_center + rel * factor_v

func end_scale():
	if _transforming:
		var paths: Array = []
		var befores: Array = []
		var afters: Array = []
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
	var paths: Array = []
	var befores: Array = []
	var afters: Array = []
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