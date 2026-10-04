class_name AssignmentData
extends Resource

@export var assignment_id: String
@export var display_name: String
@export var lesson_number: int = 1
@export var skills_taught: Array[String] = []
@export var instruction_text: String = ""
@export var primitives: Array[PrimitiveDef] = []
