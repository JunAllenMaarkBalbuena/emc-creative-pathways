class_name SnapSettings
extends RefCounted

@export var position_snap: float = 0.25
## 5deg, not the Blender/Maya 15deg. At 0.004 rad/px one pixel is 0.229deg, so a
## 15deg step needed ~65px of drag per detent and a +/-32px dead band - the
## object would sit still for most of a correction and then jump. 5deg is ~22px
## per detent and +/-11px of stall, which still lands on round angles without
## the gizmo reading as stuck.
@export var rotation_snap: float = 5.0
@export var scale_snap: float = 0.1
@export var grid_visible: bool = true
@export var snap_enabled: bool = true
## Snap is applied to the live gesture angle on every mouse-motion event, the
## same way `apply_move` snaps position - not deferred to mouse release. This
## flag exists so rotation can be excluded without touching position/scale; it
## is on, so rotation snaps in real time like move does.
@export var rotation_snap_enabled: bool = true

func snap_value(value: float, snap: float) -> float:
	if not snap_enabled or snap <= 0:
		return value
	return round(value / snap) * snap

func snap_vector3(v: Vector3, snap: float) -> Vector3:
	if not snap_enabled or snap <= 0:
		return v
	return Vector3(snap_value(v.x, snap), snap_value(v.y, snap), snap_value(v.z, snap))
