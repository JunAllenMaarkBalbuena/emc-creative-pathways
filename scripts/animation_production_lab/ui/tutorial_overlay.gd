extends Control

## Tutorial overlay: pages through the manager's built-in 12-step walk; Done
## hides it and records tutorial_done on the manager.

signal tutorial_closed

var _steps: Array[String] = []
var _index := 0

@onready var text_label: Label = %TutorialText
@onready var page_label: Label = %PageLabel

func set_steps(steps: Array[String]) -> void:
	_steps = steps
	_index = 0
	_show()

func _show() -> void:
	if _steps.is_empty():
		hide()
		return
	text_label.text = _steps[_index]
	page_label.text = "%d / %d" % [_index + 1, _steps.size()]

func _on_prev_pressed() -> void:
	_index = maxi(_index - 1, 0)
	_show()

func _on_next_pressed() -> void:
	_index = mini(_index + 1, _steps.size() - 1)
	_show()

func _on_done_pressed() -> void:
	tutorial_closed.emit()