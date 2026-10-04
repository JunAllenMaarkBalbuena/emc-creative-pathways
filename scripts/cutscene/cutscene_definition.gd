class_name CutsceneDefinition
extends Resource

## Full definition of a cutscene. Supports two modes:
## 1. Image frames (Array[CutsceneFrame]) — sequence of images with fades
## 2. Video playback (VideoStream) — single .ogv video file
## Set video_stream to use video mode; leave empty to use frame mode.

@export var cutscene_id := ""
@export var display_name := ""

@export_group("Video Mode")
@export var video_stream: VideoStream
@export var video_subtitle := ""

@export_group("Frame Mode")
@export var frames: Array[CutsceneFrame] = []

@export_group("Background Music")
@export var bgm: AudioStream
@export_range(0.0, 1.0, 0.05) var bgm_volume := 1.0

@export_group("Playback")
@export var allow_skip := true
@export var allow_pause := true
@export var loop := false

@export_group("Post-Cutscene")
@export_file("*.tscn") var next_scene_path := ""

func is_video() -> bool:
	return video_stream != null
