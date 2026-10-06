class_name AnimationProductionLab
extends CanvasLayer

## Root of the 2.5D Animation Production Lab (4th EMC Simulator tool lab).
## Holds the World (Node3D under UI/SceneViewport) and the Systems/UI
## controllers wired up by later tasks. The lab is fully self-contained:
## it boots from committed starter assets and never loads another lab's
## scenes, scripts, or UI. Saves live under user://animation_lab/.
##
## Independence contract (AGENTS.md): this file must import cleanly with an
## empty user://exports/ and user://drawings/, and must keep working when
## those directories are missing entirely.

signal lab_closed

@export_file("*.tscn") var fallback_scene := "res://scenes/main_menu.tscn"

# Tuning surface (spec §8). Controllers read these on _ready.
@export var default_fps := 12
@export var default_duration := 5.0
@export var max_duration := 30.0
@export var fps_min := 1
@export var fps_max := 60
@export var allow_custom_assets := true
@export var enable_hints := true
@export var enable_scoring := true
@export var enable_creative_studio := true
@export var autosave_enabled := true


func exit_lab() -> void:
	lab_closed.emit()
	SceneTransition.change_scene(fallback_scene)