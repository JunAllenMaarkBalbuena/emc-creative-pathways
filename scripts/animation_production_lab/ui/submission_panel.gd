extends Control

## SUBMIT-stage panel (Task 13 stub grown in Task 14): a live requirement
## checklist fed from AnimationAssignmentManager.stage_requirements() and a
## Submit button that stays disabled until every requirement passes.

signal submit_requested

@onready var checklist: VBoxContainer = %Checklist
@onready var status_label: Label = %StatusLabel
@onready var submit_button: Button = %SubmitButton


func set_status(text: String) -> void:
	status_label.text = text


## Rebuild the ✓/✗ rows; the Submit button enables only when all pass.
func set_requirements(requirements: Array[Dictionary]) -> void:
	for child in checklist.get_children():
		child.queue_free()
	var can_submit := true
	for req in requirements:
		var passed := bool(req.get("passed", false))
		var row := HBoxContainer.new()
		var mark := Label.new()
		mark.text = "✓" if passed else "✗"
		mark.add_theme_color_override(
			"font_color",
			Color(0.4, 0.9, 0.4) if passed else Color(0.95, 0.4, 0.4),
		)
		row.add_child(mark)
		var text := Label.new()
		text.text = str(req.get("label", ""))
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		checklist.add_child(row)
		if not passed:
			can_submit = false
	submit_button.disabled = not can_submit


func _on_submit_pressed() -> void:
	submit_requested.emit()