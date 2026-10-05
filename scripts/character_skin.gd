@tool
class_name CharacterSkin
extends Resource

## Data-driven character skin. Maps logical direction keys to animation names
## in the assigned SpriteFrames, enabling different characters with different
## frame counts, naming conventions, and optional diagonal support.

@export var skin_name: String = ""
@export var sprite_frames: SpriteFrames

@export_group("Directional Animations")
## Maps direction key (e.g. "up", "down_left") to an animation name in sprite_frames.
@export var walk_animations: Dictionary[String, String] = {}
@export var idle_animations: Dictionary[String, String] = {}

@export_group("Appearance")
## Scale of the AnimatedSprite3D when this skin is active (per-character sizing).
@export var avatar_scale := Vector3.ONE
## Local position offset of the AnimatedSprite3D when this skin is active.
@export var avatar_offset := Vector3.ZERO

@export_group("Settings")
## Enable for 8-directional input (diagonals). Disable for 4-directional only.
@export var has_diagonals: bool = false
## Frames per second for walk animations.
@export var walk_speed: float = 10.0
## Frames per second for idle animations.
@export var idle_speed: float = 5.0

func get_walk_animation(direction_key: String) -> String:
	return walk_animations.get(direction_key, _fallback_walk())

func get_idle_animation(direction_key: String) -> String:
	return idle_animations.get(direction_key, _fallback_idle())

func _fallback_walk() -> String:
	if walk_animations.is_empty():
		return ""
	return walk_animations.values()[0]

func _fallback_idle() -> String:
	if idle_animations.is_empty():
		return ""
	return idle_animations.values()[0]
