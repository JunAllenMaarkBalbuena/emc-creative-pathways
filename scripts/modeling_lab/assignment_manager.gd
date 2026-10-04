class_name AssignmentManager
extends RefCounted

const ASSIGNMENT_DIR := "res://data/assignments/"

var assignment_ids: Array[String] = [
	"crate", "traffic_cone", "chair", "table",
	"lamp", "robot", "mascot"
]

var _current_index: int = 0
var _current_assignment: AssignmentData = null
var progress: AssignmentProgress = null

func _init():
	progress = _load_progress()

func load_assignment(id: String) -> AssignmentData:
	var path := ASSIGNMENT_DIR + id + ".tres"
	if not ResourceLoader.exists(path):
		push_error("Assignment not found: ", path)
		return null
	_current_assignment = ResourceLoader.load(path) as AssignmentData
	_current_index = assignment_ids.find(id)
	if _current_index < 0:
		_current_index = 0
	return _current_assignment

func load_index(index: int) -> AssignmentData:
	if index < 0 or index >= assignment_ids.size():
		return null
	_current_index = index
	return load_assignment(assignment_ids[index])

func get_current() -> AssignmentData:
	return _current_assignment

func advance() -> AssignmentData:
	return load_index(_current_index + 1)

func has_next() -> bool:
	return _current_index + 1 < assignment_ids.size()

func is_last() -> bool:
	return _current_index >= assignment_ids.size() - 1

func get_lesson_number() -> int:
	return _current_index + 1

func get_current_id() -> String:
	if _current_assignment:
		return _current_assignment.assignment_id
	return ""

func mark_current_completed(score: float):
	if _current_assignment:
		var id := _current_assignment.assignment_id
		if not id in progress.completed_ids:
			progress.completed_ids.append(id)
		var existing: float = progress.best_scores.get(id, 0.0)
		if score > existing:
			progress.best_scores[id] = score
		_save_progress()
		if progress.completed_ids.size() >= 7:
			progress.creative_studio_unlocked = true
			_save_progress()

func is_completed(id: String) -> bool:
	return id in progress.completed_ids

func get_best_score(id: String) -> float:
	return progress.best_scores.get(id, 0.0)

func is_creative_studio_unlocked() -> bool:
	return progress.creative_studio_unlocked

func reset_progress():
	progress = AssignmentProgress.new()
	_save_progress()

func get_total_assignments() -> int:
	return assignment_ids.size()

func get_current_index() -> int:
	return _current_index

func _load_progress() -> AssignmentProgress:
	var path := "user://modeling_lab_progress.tres"
	if ResourceLoader.exists(path):
		return ResourceLoader.load(path) as AssignmentProgress
	return AssignmentProgress.new()

func _save_progress():
	var path := "user://modeling_lab_progress.tres"
	var _discarded_save: Error = ResourceSaver.save(progress, path)
