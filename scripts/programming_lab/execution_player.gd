class_name ExecutionPlayer
extends Control

signal execution_finished(success: bool)
signal step_changed(step_index: int, total_steps: int, slot_id: String)

var workspace: FlowchartWorkspace
var _path: Array[String] = []
var _current_step := 0
var _running := false
var _success := false
var _timer: Timer
var _step_delay := 0.8

@onready var overlay: ColorRect = $Overlay
@onready var step_label: Label = $StepLabel
@onready var progress_bar: ProgressBar = $ProgressBar

func _ready():
	hide()

func start_execution(ws: FlowchartWorkspace):
	workspace = ws
	_path = ws.get_execution_path()
	if _path.is_empty():
		return
	_current_step = 0
	_running = true
	_success = true
	workspace.clear_highlights()
	show()
	_process_step()

func _process_step():
	if _current_step >= _path.size():
		_finish()
		return

	var slot_id := _path[_current_step] as String
	workspace.clear_highlights()
	workspace.highlight_slots([slot_id])
	step_changed.emit(_current_step + 1, _path.size(), slot_id)

	var total = _path.size()
	var pct = float(_current_step) / float(total)
	progress_bar.value = pct * 100.0

	var slot_desc := ""
	for s in workspace.puzzle_data.slots:
		var s_id: String = s.get("id", "")
		if s_id == slot_id:
			var node: FlowchartNode = workspace.placed_nodes.get(slot_id) as FlowchartNode
			if node:
				slot_desc = FlowchartNode.TYPE_LABELS.get(node.node_type, "")
			break
	step_label.text = "Step " + str(_current_step + 1) + "/" + str(total) + ": " + slot_desc

	_current_step += 1
	if _timer == null:
		_timer = Timer.new()
		_timer.one_shot = true
		add_child(_timer)
	_timer.start(_step_delay)
	await _timer.timeout
	_process_step()

func _finish():
	_running = false
	execution_finished.emit(_success)
	await get_tree().create_timer(0.5).timeout
	hide()
	workspace.clear_highlights()

func stop():
	if _timer:
		_timer.stop()
	_running = false
	hide()
	workspace.clear_highlights()

func set_speed(delay: float):
	_step_delay = delay
