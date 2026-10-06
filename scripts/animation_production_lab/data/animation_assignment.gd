class_name AnimationAssignment
extends Resource

## Data-driven assignment for the guided animation lab. All challenge
## parameters (story beats, required categories, frame/fps/duration targets,
## required keyframes, hints) live here; AnimationAssignmentManager turns the
## data into per-stage requirements and challenge checks.

@export var assignment_id := ""
@export var display_name := ""
@export var story_beats: Array[Dictionary] = []          # {id, text, order}
@export var required_categories := PackedStringArray()
@export var min_frames: int = 3
@export var candidate_frame_paths: Array[String] = []    # shuffled starter PNGs
@export var correct_frame_path := ""
@export var required_keyframes: Array[Dictionary] = []   # {target_type, property_path}
@export var target_fps: int = 12
@export var fps_tolerance: int = 2
@export var target_duration: float = 5.0
@export var final_pose_keyframe: bool = true
@export var hints: Array[String] = []
@export var review_checklist_hint := ""