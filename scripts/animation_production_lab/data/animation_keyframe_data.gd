class_name AnimationKeyframeData
extends Resource

## One key on a track. KeyframeController keeps the global list sorted by
## time; evaluate() looks up a (target_id, property_path) track and either
## holds (STEP) or lerps (LINEAR, Vector3/float/Color) between brackets.

@export var time: float = 0.0
@export var target_id: String = ""
@export var target_type: int = 0   # 0=object, 1=camera, 2=light
@export var property_path: String = "position"
@export var value: Variant
@export var interpolation: int = 0 # 0=LINEAR, 1=STEP