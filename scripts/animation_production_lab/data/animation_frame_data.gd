class_name AnimationFrameData
extends Resource

## One frame of the frame channel: a Texture2D shown for `duration` seconds.
## frame_index is the position in the FrameController.frames list and stays
## contiguous via FrameController.reindex() after any list mutation.

@export var frame_index: int = 0
@export var texture: Texture2D
@export var duration: float = 0.1
@export var pose_name: String = ""
@export var notes: String = ""