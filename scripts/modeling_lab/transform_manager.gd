class_name TransformManager
extends RefCounted

var _selection_manager: SelectionManager
var _snap_settings: SnapSettings
var _original_transform: Transform3D
var _original_scale: Vector3
var _transforming: bool = false

func _init(sm: SelectionManager, ss: SnapSettings):
	_selection_manager = sm
	_snap_settings = ss

func begin_move(_axis: Vector3) -> bool:
	var sel := _selection_manager.get_selected()
	if not sel: return false
	_original_transform = sel.transform
	_transforming = true
	return true

func apply_move(axis: Vector3, delta_distance: float):
	var sel := _selection_manager.get_selected()
	if not sel or not _transforming: return
	var move := axis * delta_distance
	var new_pos := _original_transform.origin + move
	if _snap_settings.snap_enabled:
		new_pos = _snap_settings.snap_vector3(new_pos, _snap_settings.position_snap)
	sel.position = new_pos

func end_move():
	_transforming = false

func begin_rotate(_axis: Vector3) -> bool:
	var sel := _selection_manager.get_selected()
	if not sel: return false
	_original_transform = sel.transform
	_transforming = true
	return true

func apply_rotate(axis: Vector3, delta_angle: float):
	var sel := _selection_manager.get_selected()
	if not sel or not _transforming: return
	var snap := _snap_settings.rotation_snap if _snap_settings.snap_enabled else 0.0
	var angle := delta_angle
	if snap > 0:
		angle = _snap_settings.snap_value(rad_to_deg(delta_angle), snap)
		angle = deg_to_rad(angle)
	var rot := Basis(axis, angle)
	sel.transform = Transform3D(rot * _original_transform.basis, _original_transform.origin)

func end_rotate():
	_transforming = false

func begin_scale(_uniform: bool = true) -> bool:
	var sel := _selection_manager.get_selected()
	if not sel: return false
	_original_transform = sel.transform
	_original_scale = sel.scale
	_transforming = true
	return true

func apply_scale(axis: Vector3, delta: float, uniform: bool = true):
	var sel := _selection_manager.get_selected()
	if not sel or not _transforming: return
	var s := _original_scale
	var factor: float = max(0.01, 1.0 + delta * 0.003)
	if uniform:
		s *= factor
	else:
		if axis.x != 0: s.x *= factor
		if axis.y != 0: s.y *= factor
		if axis.z != 0: s.z *= factor
	if _snap_settings.snap_enabled:
		s = _snap_settings.snap_vector3(s, _snap_settings.scale_snap)
	s = s.max(Vector3(0.01, 0.01, 0.01))
	sel.scale = s

func end_scale():
	_transforming = false

func is_transforming() -> bool:
	return _transforming

func duplicate_selected() -> Node3D:
	var sel := _selection_manager.get_selected()
	if not sel: return null
	var parent: Node = sel.get_parent()
	var copy: MeshInstance3D = sel.duplicate() as MeshInstance3D
	copy.position += Vector3(0.5, 0.5, 0.5)
	parent.add_child(copy)
	copy.owner = parent.owner if parent.owner else parent
	_selection_manager.select(copy)
	return copy

func delete_selected():
	var sel := _selection_manager.get_selected()
	if not sel: return
	sel.queue_free()
	_selection_manager.deselect_all()

func reset_selected():
	var sel := _selection_manager.get_selected()
	if not sel: return
	sel.transform = Transform3D.IDENTITY

func center_selected():
	var sel := _selection_manager.get_selected()
	if not sel: return
	var aabb := sel.mesh.get_aabb() if sel.mesh else AABB(Vector3.ZERO, Vector3.ONE)
	var offset := aabb.get_center()
	sel.position = -offset
