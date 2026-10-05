class_name FlowchartPuzzleData
extends Resource

enum NodeType { START, END, PROCESS, DECISION, INPUT_OUTPUT }

@export_category("Identity")
@export var puzzle_id := ""
@export var title := ""
@export var difficulty := 1

@export_category("Description")
@export_multiline var problem_description := ""
@export var ipo_input := ""
@export var ipo_process := ""
@export var ipo_output := ""

@export_category("Workspace")
@export var slots: Array[Dictionary] = []
@export var palette_types: Array[int] = []
@export var connections: Array[Dictionary] = []

@export_category("Hints")
@export_multiline var hint_level_1 := ""
@export_multiline var hint_level_2 := ""
@export_multiline var hint_level_3 := ""

@export_category("Reward")
@export var reward_stars := 3
@export var completion_message := ""

@export_category("Cutscene")
@export var cutscene_type := 0  # 0=none 1=png_sequence 2=video
@export var cutscene_path := ""
@export var cutscene_fps := 12.0

func validate_slot(slot_id: String, placed_type: int) -> bool:
	for slot in slots:
		if slot.get("id") == slot_id:
			var expected = slot.get("correct_type", -1)
			return expected == -1 or expected == placed_type
	return false

func get_slot(slot_id: String) -> Dictionary:
	for slot in slots:
		if slot.get("id") == slot_id:
			return slot
	return {}

func get_slot_connections(slot_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for c in connections:
		if c.get("from") == slot_id:
			result.append(c)
	return result
