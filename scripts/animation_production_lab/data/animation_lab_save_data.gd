class_name AnimationLabSaveData
extends Resource

## One serializable snapshot of the animation lab session (spec §3). Stored as
## .tres by SaveController — the guided autosave overwrites guided.tres, and
## Creative Studio projects live in projects/<sanitized>.tres. All fields are
## plain serializable Variants (arrays of dictionaries, no Resource refs) so a
## .tres round-trip is lossless and hand-edits stay safe to read back.

@export var guided_completed := false
@export var current_assignment_id := ""
@export var scene_objects: Array[Dictionary] = []
@export var camera_data: Dictionary = {}
@export var lighting_data: Dictionary = {}
@export var frames: Array[Dictionary] = []
@export var keyframes: Array[Dictionary] = []
@export var fps := 12
@export var duration := 5.0
@export var score_data: Dictionary = {}
@export var hints_used := 0
@export var creative_projects: Array[Dictionary] = []