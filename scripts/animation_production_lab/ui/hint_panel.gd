extends Control

## Hint panel (PREVIEW stage): shows the assignment's hints for the moment.

@onready var hint_text: Label = %HintText

func set_hints(hints: Array[String]) -> void:
	hint_text.text = hints[0] if not hints.is_empty() else ""

func clear_hints() -> void:
	hint_text.text = ""