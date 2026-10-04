class_name AccuracyManager
extends RefCounted

@export var pos_max_error: float = 2.0
@export var rot_max_error_deg: float = 90.0
@export var scale_max_error: float = 2.0
@export var perfect_threshold: float = 98.0

func compare(player: Transform3D, ghost: Transform3D) -> Dictionary:
	var pos_error := player.origin.distance_to(ghost.origin)
	var pos_score: float = clampf(1.0 - (pos_error / max(pos_max_error, 0.01)), 0.0, 1.0) * 100.0

	var p_quat: Quaternion = player.basis.get_rotation_quaternion()
	var g_quat: Quaternion = ghost.basis.get_rotation_quaternion()
	var rot_error_rad: float = p_quat.angle_to(g_quat)
	var rot_error_deg: float = rad_to_deg(rot_error_rad)
	var rot_score: float = clampf(1.0 - (rot_error_deg / max(rot_max_error_deg, 0.01)), 0.0, 1.0) * 100.0

	var p_scale: Vector3 = player.basis.get_scale()
	var g_scale: Vector3 = ghost.basis.get_scale()
	var scale_error: float = p_scale.distance_to(g_scale)
	var scale_score: float = clampf(1.0 - (scale_error / max(scale_max_error, 0.01)), 0.0, 1.0) * 100.0

	var overall: float = (pos_score + rot_score + scale_score) / 3.0

	return {pos = pos_score, rot = rot_score, scale = scale_score, overall = overall}

func is_perfect(result: Dictionary) -> bool:
	return result.overall >= perfect_threshold

func is_close(result: Dictionary) -> bool:
	return result.overall >= 90.0
