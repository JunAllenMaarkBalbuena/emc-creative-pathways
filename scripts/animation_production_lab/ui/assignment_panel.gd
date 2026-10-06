extends Control

## Assignment brief panel (BRIEF stage): shows the loaded assignment's name,
## story beats, and target meta, then a single Begin button.

signal brief_acknowledged

@onready var name_label: Label = %AssignmentName
@onready var story_label: Label = %StoryText
@onready var meta_label: Label = %Meta

func set_brief(display_name: String, story_text: String, meta: String) -> void:
	name_label.text = display_name
	story_label.text = story_text
	meta_label.text = meta

func _on_start_pressed() -> void:
	brief_acknowledged.emit()