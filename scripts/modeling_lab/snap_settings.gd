class_name SnapSettings
extends RefCounted

@export var position_snap: float = 0.25
@export var rotation_snap: float = 15.0
@export var scale_snap: float = 0.1
@export var grid_visible: bool = true
@export var snap_enabled: bool = true

func snap_value(value: float, snap: float) -> float:
	if not snap_enabled or snap <= 0:
		return value
	return round(value / snap) * snap

func snap_vector3(v: Vector3, snap: float) -> Vector3:
	if not snap_enabled or snap <= 0:
		return v
	return Vector3(snap_value(v.x, snap), snap_value(v.y, snap), snap_value(v.z, snap))
