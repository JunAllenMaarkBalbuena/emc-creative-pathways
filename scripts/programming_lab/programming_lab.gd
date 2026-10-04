class_name ProgrammingLab
extends CanvasLayer

signal lab_closed

@export_file("*.tscn") var fallback_scene := "res://scenes/main_menu.tscn"

## Puzzle order is read from res://data/sequences/<level_id>.tres by default.
## Falls back to auto-scanning data/puzzles/ alphabetically if no sequence file exists.

var current_puzzle_index := 0
var puzzle_list: Array[FlowchartPuzzleData] = []
var score := 0
var stars := 0
var hints_used := 0
var start_time := 0.0
var puzzle_scores: Array = []

@onready var workspace: FlowchartWorkspace = $Panel/Workspace
@onready var execution_player: ExecutionPlayer = $Panel/ExecutionPlayer
@onready var puzzle_title: Label = $Panel/TopBar/Margin/TitleLabel
@onready var difficulty_stars: Label = $Panel/TopBar/StarsLabel
@onready var puzzle_counter: Label = $Panel/TopBar/CounterLabel
@onready var problem_desc: RichTextLabel = $Panel/LeftPanel/ProblemSection/Description
@onready var ipo_input: Label = $Panel/LeftPanel/IPOSection/InputLabel
@onready var ipo_process: Label = $Panel/LeftPanel/IPOSection/ProcessLabel
@onready var ipo_output: Label = $Panel/LeftPanel/IPOSection/OutputLabel
@onready var palette_container: VBoxContainer = $Panel/LeftPanel/PaletteContainer/PaletteItems
@onready var run_button: Button = $Panel/BottomBar/RunButton
@onready var hint_button: Button = $Panel/BottomBar/HintButton
@onready var reset_button: Button = $Panel/BottomBar/ResetButton
@onready var hint_panel: Panel = $Panel/HintPanel
@onready var hint_label: RichTextLabel = $Panel/HintPanel/HintLabel
@onready var completion_panel: Panel = $Panel/CompletionPanel
@onready var completion_title: Label = $Panel/CompletionPanel/Title
@onready var completion_message_label: Label = $Panel/CompletionPanel/Message
@onready var completion_stars: Label = $Panel/CompletionPanel/Stars
@onready var completion_score: Label = $Panel/CompletionPanel/Score
@onready var next_button: Button = $Panel/CompletionPanel/NextButton
@onready var close_completion: Button = $Panel/CompletionPanel/CloseButton
@onready var close_lab: Button = $Panel/TopBar/CloseButton
@onready var companion_char: TextureRect = %CompanionChar
@onready var cutscene_player: LabCutscenePlayer = $Panel/CutscenePlayer
@onready var level_def: LevelDefinition

var _current_hint_level := 0

func _ready():
	_resolve_level_def()
	execution_player.execution_finished.connect(_on_execution_finished)
	hint_panel.visible = false
	completion_panel.visible = false
	workspace.puzzle_changed.connect(_on_puzzle_changed)
	workspace.puzzle_completed.connect(_on_workspace_complete)
	workspace.wrong_drop_attempted.connect(_on_wrong_drop)
	run_button.pressed.connect(_on_run_pressed)
	hint_button.pressed.connect(_on_hint_pressed)
	reset_button.pressed.connect(_on_reset_pressed)
	next_button.pressed.connect(_on_next_pressed)
	close_completion.pressed.connect(_close_completion)
	close_lab.pressed.connect(_on_close_lab)

	var puzzles := _load_sequence_from_file()
	if puzzles.is_empty():
		puzzles = _load_all_puzzles()
	if not puzzles.is_empty():
		load_puzzles(puzzles, level_def)

func _get_level_id() -> String:
	if level_def and not level_def.level_id.is_empty():
		return level_def.level_id
	return "programming_lab"

func _resolve_level_def() -> void:
	if level_def != null:
		return
	var path := "res://data/levels/%s.tres" % _get_level_id()
	if ResourceLoader.exists(path):
		level_def = ResourceLoader.load(path) as LevelDefinition

func _load_sequence_from_file() -> Array[FlowchartPuzzleData]:
	var seq_id := _get_level_id()
	var path := "res://data/sequences/" + seq_id + ".tres"
	if not ResourceLoader.exists(path):
		return []
	var seq := ResourceLoader.load(path) as PuzzleSequence
	if seq == null:
		return []
	return seq.puzzle_order.duplicate()

func _load_all_puzzles() -> Array[FlowchartPuzzleData]:
	var result: Array[FlowchartPuzzleData] = []
	var dir := DirAccess.open("res://data/puzzles/")
	if dir == null:
		return result
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while not fname.is_empty():
		if fname.ends_with(".tres") or fname.ends_with(".res"):
			var path := "res://data/puzzles/" + fname
			if ResourceLoader.exists(path):
				var res = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
				if res is FlowchartPuzzleData:
					result.append(res)
		fname = dir.get_next()
	dir.list_dir_end()
	result.sort_custom(func(a, b): return a.puzzle_id < b.puzzle_id)
	return result

func load_puzzles(puzzles: Array[FlowchartPuzzleData], level: LevelDefinition = null):
	puzzle_list = puzzles
	level_def = level
	puzzle_scores = []
	for i in range(puzzle_list.size()):
		puzzle_scores.append(0)
	if puzzle_list.size() > 0:
		load_puzzle(0)

func load_puzzle(index: int):
	if index < 0 or index >= puzzle_list.size():
		return
	current_puzzle_index = index
	var data := puzzle_list[index]
	print("Loading puzzle: ", data.title, " cutscene_type: ", data.cutscene_type, " cutscene_path: ", data.cutscene_path)
	workspace.setup(data)
	_populate_ui(data)
	_populate_palette(data)
	_current_hint_level = 0
	hints_used = 0
	start_time = Time.get_ticks_msec()
	hint_panel.visible = false
	completion_panel.visible = false
	cutscene_player.close()
	run_button.disabled = false
	hint_button.disabled = false

func _populate_ui(data: FlowchartPuzzleData):
	puzzle_title.text = data.title
	difficulty_stars.text = "★".repeat(data.difficulty) + "☆".repeat(3 - data.difficulty)
	puzzle_counter.text = "Puzzle " + str(current_puzzle_index + 1) + " / " + str(puzzle_list.size())
	problem_desc.text = data.problem_description
	ipo_input.text = data.ipo_input
	ipo_process.text = data.ipo_process
	ipo_output.text = data.ipo_output

func _populate_palette(data: FlowchartPuzzleData):
	for child in palette_container.get_children():
		child.queue_free()

	for t in data.palette_types:
		var item := FlowchartNode.new()
		item.node_type = t
		item.label_text = FlowchartNode.TYPE_LABELS.get(t, "")
		item.size = Vector2(232, 34)
		item.custom_minimum_size = Vector2(228, 30)
		item.tooltip_text = "Drag me to an empty slot"
		palette_container.add_child(item)

func _on_puzzle_changed():
	run_button.disabled = not _check_can_run()
	if companion_char and companion_char.has_method("show_success"):
		companion_char.show_success()

func _on_wrong_drop():
	if companion_char and companion_char.has_method("show_mistake"):
		companion_char.show_mistake()

func _check_can_run() -> bool:
	for slot in workspace.puzzle_data.slots:
		var sid: String = slot.get("id", "")
		if not sid in workspace.placed_nodes:
			return false
	return true

func _on_run_pressed():
	if not _check_can_run():
		return
	run_button.disabled = true
	hint_button.disabled = true
	var incorrect := workspace.get_incorrect_slots()
	if not incorrect.is_empty():
		workspace.mark_wrong(incorrect)
		if companion_char and companion_char.has_method("show_mistake"):
			companion_char.show_mistake()
		await get_tree().create_timer(1.0).timeout
		workspace.clear_highlights()
		run_button.disabled = false
		hint_button.disabled = false
		return
	execution_player.start_execution(workspace)

func _on_execution_finished(success: bool):
	if success:
		_on_puzzle_solved()
	else:
		run_button.disabled = false
		hint_button.disabled = false

func _on_puzzle_solved():
	if companion_char and companion_char.has_method("show_success"):
		companion_char.show_success()
	var data := workspace.puzzle_data
	print("Puzzle solved! cutscene_type: ", data.cutscene_type, " cutscene_path: ", data.cutscene_path)
	if data and data.cutscene_type > 0 and not data.cutscene_path.is_empty():
		print("Playing cutscene...")
		cutscene_player.setup(data)
		if cutscene_player.visible:
			await cutscene_player.finished
			cutscene_player.close()
	var elapsed := (Time.get_ticks_msec() - start_time) / 1000.0
	var time_bonus: float = max(0.0, 30.0 - elapsed) / 30.0
	var hint_penalty: float = hints_used * 0.2
	var raw_score: float = max(0.0, 1.0 - hint_penalty) * (0.7 + 0.3 * time_bonus)
	var final_score: int = int(raw_score * 100)
	puzzle_scores[current_puzzle_index] = final_score
	
	var star_count := 1
	if final_score >= 80:
		star_count = 3
	elif final_score >= 50:
		star_count = 2
	
	completion_title.text = "Puzzle Complete!"
	completion_message_label.text = workspace.puzzle_data.completion_message
	if completion_message_label.text.is_empty():
		completion_message_label.text = "Great job! You solved the puzzle."
	completion_stars.text = "⭐".repeat(star_count) + "☆".repeat(3 - star_count)
	completion_score.text = "Score: " + str(final_score) + "%  |  Time: " + str(int(elapsed)) + "s  |  Hints: " + str(hints_used)
	
	var is_last = current_puzzle_index >= puzzle_list.size() - 1
	next_button.visible = not is_last
	completion_panel.visible = true

func _on_hint_pressed():
	var data := workspace.puzzle_data
	if data == null:
		return
	_current_hint_level = mini(_current_hint_level + 1, 3)
	hints_used += 1
	
	var hint_text := ""
	match _current_hint_level:
		1: hint_text = data.hint_level_1
		2: hint_text = data.hint_level_2
		3: hint_text = data.hint_level_3
	
	if hint_text.is_empty():
		hint_text = "Think carefully about what each symbol represents."

	hint_label.text = "Hint " + str(_current_hint_level) + "/3:\n" + hint_text
	hint_panel.visible = true
	
	if _current_hint_level >= 3:
		hint_button.disabled = true

func _on_reset_pressed():
	workspace.reset()
	run_button.disabled = true
	hint_button.disabled = false
	_current_hint_level = 0
	hints_used = 0

func _on_workspace_complete():
	pass

func _on_next_pressed():
	completion_panel.visible = false
	var next := current_puzzle_index + 1
	if next < puzzle_list.size():
		load_puzzle(next)

func _close_completion():
	completion_panel.visible = false

func _on_close_lab():
	_on_lab_exit()

func _on_lab_exit():
	lab_closed.emit()
	if level_def and not level_def.level_id.is_empty():
		LevelProgression.complete_level(level_def)
	var return_scene := LevelProgression.get_resume_scene()
	if return_scene.is_empty():
		return_scene = fallback_scene
	else:
		LevelProgression.save_spawn_position(return_scene, LevelProgression.get_resume_spawn().get("player", Vector3.ZERO), LevelProgression.get_resume_spawn().get("camera_offset", Vector3.ZERO))
		LevelProgression.clear_resume_state()
	get_tree().change_scene_to_file(return_scene)
