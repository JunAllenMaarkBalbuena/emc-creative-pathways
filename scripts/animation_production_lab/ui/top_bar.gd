extends Control

## Top bar: always visible. Mode + stage labels, exit button, and a Creative
## Studio button that only appears once the guided run is completed (Task 16
## — unlock gate is the lab's own save flag, spec §15). No class_name on
## purpose (the root types this via a preload const).

signal exit_requested
signal studio_requested

@onready var mode_label: Label = %ModeLabel
@onready var stage_label: Label = %StageLabel
@onready var studio_button: Button = %StudioButton

func set_mode_label(text: String) -> void:
	mode_label.text = text

func set_stage_label(text: String) -> void:
	stage_label.text = text

func set_studio_unlocked(unlocked: bool) -> void:
	studio_button.visible = unlocked

func _on_studio_pressed() -> void:
	studio_requested.emit()

func _on_exit_pressed() -> void:
	exit_requested.emit()