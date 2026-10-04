class_name PrimitiveDef
extends Resource

enum Type { CUBE, SPHERE, CYLINDER, CONE, CAPSULE, PLANE, TORUS }

@export var type: Type
@export var target_position: Vector3
@export var target_rotation: Vector3
@export var target_scale: Vector3 = Vector3.ONE
@export var parent_id: String = ""
@export var material_color: Color = Color.WHITE
@export var material_metallic: float = 0.0
@export var material_roughness: float = 0.5
