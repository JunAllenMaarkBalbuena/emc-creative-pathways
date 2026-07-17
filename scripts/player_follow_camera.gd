class_name PlayerFollowCamera
extends Camera3D

## A reusable 2.5D follow camera. Configure these values per level in the
## Inspector without changing player movement code.
@export_category("Follow Target")
@export var target: Node3D
@export var target_path: NodePath

@export_category("Camera Framing")
## When enabled, position and rotate this Camera3D directly in the scene.
## Its starting position becomes its follow offset and its rotation is kept.
@export var use_scene_transform := true
@export var follow_offset := Vector3(9.0, 10.0, 12.0)
@export var look_at_offset := Vector3(0.0, 1.0, 0.0)
@export_range(0.1, 20.0, 0.1) var tracking_speed := 6.0
@export_range(10.0, 110.0, 1.0, "suffix:°") var camera_fov := 55.0

var _scene_offset := Vector3.ZERO
var _scene_rotation := Vector3.ZERO

func _ready() -> void:
	if target == null and not target_path.is_empty():
		target = get_node_or_null(target_path) as Node3D
	if target != null:
		if use_scene_transform:
			_scene_offset = global_position - target.global_position
			_scene_rotation = global_rotation
		else:
			global_position = target.global_position + follow_offset
			look_at(target.global_position + look_at_offset, Vector3.UP)
	fov = camera_fov
	current = true

func _physics_process(delta: float) -> void:
	if target == null:
		return
	var desired_offset := _scene_offset if use_scene_transform else follow_offset
	var desired_position := target.global_position + desired_offset
	global_position = global_position.lerp(desired_position, 1.0 - exp(-tracking_speed * delta))
	if use_scene_transform:
		global_rotation = _scene_rotation
	else:
		look_at(target.global_position + look_at_offset, Vector3.UP)
