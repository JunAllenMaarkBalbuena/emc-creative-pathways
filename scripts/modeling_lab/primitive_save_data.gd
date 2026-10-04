class_name PrimitiveSaveData
extends Resource

const TYPE_MESH := 0
const TYPE_GROUP := 1

@export var node_type: int = TYPE_MESH   # MESH or GROUP
@export var type: int = 0
@export var node_name: String = ""
@export var display_name: String = ""    # Blender-style ("cube.001")
@export var position: Vector3
@export var rotation_degrees: Vector3
@export var scale: Vector3 = Vector3.ONE
@export var parent_name: String = ""     # display_name of the parent group
@export var material_albedo: Color = Color.WHITE
@export var material_metallic: float = 0.0
@export var material_roughness: float = 0.5
