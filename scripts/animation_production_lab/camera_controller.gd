class_name AnimationCameraController
extends Node

## Drives the lab's Camera3D. All movement is relative to the current
## transform; zoom travels along the camera's view axis and clamps its
## distance from the origin to [MIN_DISTANCE, MAX_DISTANCE]. framing_ok()
## is the measurable framing check the scoring layer consumes: the camera
## must sit within max_distance of the scene center and stage every target
## inside its frustum.

const HOME_POSITION := Vector3(0, 0.8, 4)
const HOME_ROTATION := Vector3.ZERO
const HOME_FOV := 60.0
const MIN_DISTANCE := 0.5
const MAX_DISTANCE := 12.0

@export_node_path("Camera3D") var camera_path: NodePath


func camera() -> Camera3D:
	return get_node_or_null(camera_path) as Camera3D


func set_transform(pos: Vector3, rot_deg: Vector3) -> void:
	var cam := camera()
	if cam == null:
		return
	cam.position = pos
	cam.rotation_degrees = rot_deg


func move_offset(offset: Vector3) -> void:
	var cam := camera()
	if cam == null:
		return
	cam.position += offset


func rotate_offset(delta_deg: Vector3) -> void:
	var cam := camera()
	if cam == null:
		return
	cam.rotation_degrees += delta_deg


func set_zoom(factor: float) -> void:
	var cam := camera()
	if cam == null:
		return
	var target := cam.global_position - cam.global_transform.basis.z * factor
	var dist := target.length()
	if dist < MIN_DISTANCE:
		target = target.normalized() * MIN_DISTANCE
	elif dist > MAX_DISTANCE:
		target = target.normalized() * MAX_DISTANCE
	cam.global_position = target


func reset() -> void:
	var cam := camera()
	if cam == null:
		return
	cam.position = HOME_POSITION
	cam.rotation_degrees = HOME_ROTATION
	cam.fov = HOME_FOV


func framing_ok(center: Vector3, targets: Array[Vector3], max_distance: float) -> bool:
	var cam := camera()
	if cam == null:
		return false
	if center.distance_to(cam.global_position) > max_distance:
		return false
	for target in targets:
		if not cam.is_position_in_frustum(target):
			return false
	return true