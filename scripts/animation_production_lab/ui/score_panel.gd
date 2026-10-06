extends Control

## Full submission feedback overlay (Task 14): category breakdown, total
## score, and improvement notes from AnimationScoreData, plus the path into
## the Creative Studio once the guided run is submitted.

signal continue_to_studio

@onready var total_label: Label = %TotalLabel
@onready var detail_label: Label = %DetailLabel
@onready var feedback_header: Label = %FeedbackHeader
@onready var feedback_list: VBoxContainer = %FeedbackList

const CATEGORY_NAMES := [
	"Story", "Staging", "Camera", "Lighting", "Frame animation",
	"Keyframes", "Timing", "Technical", "Creativity",
]


func show_score(score: AnimationScoreData) -> void:
	show()
	total_label.text = "TOTAL  %d / 100" % int(score.total_score)
	detail_label.text = "\n".join(_category_lines(score))
	feedback_header.visible = not score.feedback.is_empty()
	for child in feedback_list.get_children():
		child.queue_free()
	for line in score.feedback:
		var row := Label.new()
		row.text = "• " + line
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		feedback_list.add_child(row)


func _category_lines(score: AnimationScoreData) -> Array[String]:
	var out: Array[String] = []
	var values: Array[float] = [
		score.story_score, score.staging_score, score.camera_score,
		score.lighting_score, score.frame_animation_score, score.keyframe_score,
		score.timing_score, score.technical_score, score.creativity_score,
	]
	for i in range(values.size()):
		out.append("%s  %d" % [CATEGORY_NAMES[i], int(values[i])])
	return out


func _on_continue_pressed() -> void:
	continue_to_studio.emit()