extends Control

## Top bar: always visible. Mode + stage labels, exit button. No class_name on
## purpose (the root types this via a preload const).

signal exit_requested

@onready var mode_label: Label = %ModeLabel
@onready var stage_label: Label = %StageLabel

func set_mode_label(text: String) -> void:
	mode_label.text = text

func set_stage_label(text: String) -> void:
	stage_label.text = text

func _on_exit_pressed() -> void:
	exit_requested.emit()