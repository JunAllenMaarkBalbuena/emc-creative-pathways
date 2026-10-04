class_name CutsceneFrame
extends Resource

## A single frame in a cutscene. Each frame shows an image for a set duration
## with optional fade transitions and a sound effect.

@export var image: Texture2D
@export_range(0.1, 60.0, 0.1, "suffix:s") var duration := 3.0
@export_range(0.0, 5.0, 0.1, "suffix:s") var fade_in_duration := 0.5
@export_range(0.0, 5.0, 0.1, "suffix:s") var fade_out_duration := 0.5
@export var sfx: AudioStream
@export var subtitle := ""
