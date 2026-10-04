extends Node

## Attach to any AudioStreamPlayer to force loop behavior at runtime.
## Works with MP3/OGG where editor loop property may not apply.

@export var loop := true

func _ready() -> void:
	var player := get_parent() as AudioStreamPlayer
	if player != null and player.stream != null:
		player.stream.loop = loop
