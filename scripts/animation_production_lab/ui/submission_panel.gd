extends Control

## Submission panel (SUBMIT stage). Task 14 extends this with the Submit
## button and the live requirement checklist from stage_requirements().

@onready var status_label: Label = %SubmitStatus

func set_status(text: String) -> void:
	status_label.text = text