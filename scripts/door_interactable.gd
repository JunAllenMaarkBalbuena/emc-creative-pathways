class_name DoorInteractable
extends Interactable

@export var door_mesh_path: NodePath = NodePath("DoorMesh")
@export var open_angle := -90.0
@export var open_duration := 0.6
@export var dialogue_id := "library_door_locked"

var is_open := false

@export_group("Open Condition")
@export var enable_condition := false
@export var condition_id := ""
@export var condition_must_be_true := true
@export_multiline var locked_prompt_content := "This door requires completing a task first."

enum OnOpenAction { NONE, SET_CONDITION, LOAD_SCENE, TELEPORT_PLAYER }

@export_group("On Open Action")
@export var enable_on_open_action := false
@export var on_open_action_type: OnOpenAction = OnOpenAction.NONE
@export var on_open_condition_id := ""
@export var on_open_condition_value := true
@export_file("*.tscn") var on_open_scene_path := ""
@export var on_open_teleport_target: NodePath

@export_group("Entry Cutscene")
@export var cutscene_definition: CutsceneDefinition

var _pending_player: PlayerController

func interact(player: PlayerController) -> String:
	if is_open:
		return "The laboratory door is already open."
	if enable_condition and not _is_condition_met():
		return DialogueDatabase.get_text(dialogue_id, "The door is locked. You need to complete a task first.")
	is_open = true
	var door_mesh := get_node_or_null(door_mesh_path) as Node3D
	if door_mesh != null:
		create_tween().tween_property(door_mesh, "rotation:y", deg_to_rad(open_angle), open_duration)
	if cutscene_definition != null:
		_play_cutscene_then_run(player)
	else:
		_perform_on_open_action(player)
	return DialogueDatabase.get_text(dialogue_id, "The door opens.")

func _play_cutscene_then_run(player: PlayerController) -> void:
	var cs := _find_or_create_cutscene_player()
	if cs == null:
		_perform_on_open_action(player)
		return
	_pending_player = player
	cs.cutscene_finished.connect(_on_entry_cutscene_finished, CONNECT_ONE_SHOT)
	cs.play(cutscene_definition)

func _on_entry_cutscene_finished() -> void:
	var player := _pending_player
	_pending_player = null
	_perform_on_open_action(player)

func _find_or_create_cutscene_player() -> CutscenePlayer:
	var existing := get_tree().root.find_children("*", "CutscenePlayer", true, false)
	if existing.size() > 0:
		return existing[0]
	var cs_scene := preload("res://scenes/cutscene/cutscene_player.tscn")
	var cs_player := cs_scene.instantiate() as CutscenePlayer
	get_tree().root.add_child(cs_player)
	return cs_player

func _is_condition_met() -> bool:
	if condition_id.is_empty():
		return true
	return GameConditions.get_flag(condition_id) == condition_must_be_true

func _perform_on_open_action(player: PlayerController) -> void:
	if not enable_on_open_action:
		return
	match on_open_action_type:
		OnOpenAction.SET_CONDITION:
			if not on_open_condition_id.is_empty():
				GameConditions.set_flag(on_open_condition_id, on_open_condition_value)
		OnOpenAction.LOAD_SCENE:
			if not on_open_scene_path.is_empty():
				var scene_path := get_tree().current_scene.scene_file_path
				var cam = get_tree().current_scene.get_node_or_null("PlayerFollowCamera")
				var cam_offset = cam.global_position - player.global_position if cam else Vector3.ZERO
				if LevelProgression.has_resume_state() and LevelProgression.get_resume_scene() == on_open_scene_path:
					var spawn_data: Dictionary = LevelProgression.get_resume_spawn()
					LevelProgression.save_spawn_position(on_open_scene_path, spawn_data.get("player", Vector3.ZERO), spawn_data.get("camera_offset", Vector3.ZERO))
					LevelProgression.clear_resume_state()
					push_warning("DOOR: returning to %s, saved spawn pos=%s" % [on_open_scene_path, spawn_data.get("player", Vector3.ZERO)])
				else:
					LevelProgression.save_resume_state(scene_path, player.global_position, cam_offset)
					push_warning("DOOR: saved resume state scene=%s pos=%s" % [scene_path, player.global_position])
				get_tree().change_scene_to_file(on_open_scene_path)
		OnOpenAction.TELEPORT_PLAYER:
			var target_node = get_node_or_null(on_open_teleport_target) as Node3D
			if target_node != null:
				player.global_position = target_node.global_position

func get_prompt_title() -> String:
	return DialogueDatabase.get_prompt_title(dialogue_id, prompt_title)

func get_prompt_content() -> String:
	if enable_condition and not _is_condition_met():
		return locked_prompt_content
	return DialogueDatabase.get_prompt_content(dialogue_id, prompt_content)
