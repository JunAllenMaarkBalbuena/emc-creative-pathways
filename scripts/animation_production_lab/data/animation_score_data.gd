class_name AnimationScoreData
extends Resource

## One measurable score report. Nine 0..100 category scores (spec §4.2), the
## weighted total, and one template feedback sentence per category under 100
## plus condition-specific hint lines.

@export var story_score: float = 0.0
@export var staging_score: float = 0.0
@export var camera_score: float = 0.0
@export var lighting_score: float = 0.0
@export var frame_animation_score: float = 0.0
@export var keyframe_score: float = 0.0
@export var timing_score: float = 0.0
@export var technical_score: float = 0.0
@export var creativity_score: float = 0.0
@export var total_score: float = 0.0
@export var feedback: Array[String] = []