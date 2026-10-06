class_name MainMenu
extends Control

@export_file("*.tscn") var game_scene_path := "res://scenes/world_demo.tscn"
@export_file("*.tscn") var programming_lab_path := "res://scenes/programming_lab.tscn"
@export_file("*.tscn") var flowchart_editor_path := "res://scenes/flowchart_editor.tscn"
@export_file("*.tscn") var digital_art_lab_path := "res://scenes/digital_art_lab/digital_art_lab.tscn"
@export_file("*.tscn") var modeling_lab_path := "res://scenes/modeling_lab/modeling_lab.tscn"
@export_file("*.tscn") var animation_production_lab_path := "res://scenes/animation_production_lab/animation_production_lab.tscn"
@export var intro_cutscene: CutsceneDefinition

@onready var play_button: Button = $PlayButton
@onready var continue_button: Button = $ContinueButton
@onready var lab_button: Button = $LabButton
@onready var editor_button: Button = $EditorButton
@onready var art_button: Button = $ArtButton
@onready var model_button: Button = $ModelButton
@onready var anim_button: Button = $AnimButton
@onready var settings_button: Button = $SettingsButton
@onready var quit_button: Button = $ExitButton
@onready var title_label: Label = $TitleLabel
@onready var version_label: Label = $VersionLabel
@onready var settings_ui: SettingsUI = $SettingsUI

var _cutscene_player

func _ready() -> void:
	play_button.pressed.connect(_on_play_pressed)
	continue_button.pressed.connect(_on_continue_pressed)
	if lab_button:
		lab_button.pressed.connect(_on_lab_pressed)
	if editor_button:
		# The flowchart editor is an authoring tool, not player content. It
		# browses and saves .tres puzzles through FileDialog with
		# ACCESS_RESOURCES against res://data/puzzles/, and on web res:// is a
		# read-only virtual filesystem inside the .pck. The dialog cannot list
		# a real directory tree there, and save-as has nowhere writable to go.
		#
		# So it is hidden rather than half-working. Puzzles authored on desktop
		# still ship in the exported build, because they are baked into the .pck
		# at export time - a web player can play them, just not create them.
		#
		# Left visible on desktop, where it is the normal way to author puzzles.
		if Platform.is_mobile_or_web():
			editor_button.hide()
		else:
			editor_button.pressed.connect(_on_editor_pressed)
	if art_button:
		art_button.pressed.connect(_on_art_pressed)
	if model_button:
		model_button.pressed.connect(_on_model_pressed)
	if anim_button:
		anim_button.pressed.connect(_on_anim_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	settings_ui.settings_closed.connect(_on_settings_closed)
	continue_button.visible = LevelProgression.has_resume_state() or LevelProgression.has_lab_resume_state()
	if intro_cutscene != null:
		_cutscene_player = _find_or_create_cutscene_player()
		_cutscene_player.cutscene_finished.connect(_on_cutscene_finished)

func _on_play_pressed() -> void:
	LevelProgression.clear_all_memory()
	LevelProgression.reset_skin_index()
	SceneTransition.change_scene(game_scene_path)

func _on_lab_pressed() -> void:
	SceneTransition.change_scene(programming_lab_path)

func _on_editor_pressed() -> void:
	SceneTransition.change_scene(flowchart_editor_path)

func _on_art_pressed() -> void:
	SceneTransition.change_scene(digital_art_lab_path)

func _on_model_pressed() -> void:
	SceneTransition.change_scene(modeling_lab_path)

func _on_anim_pressed() -> void:
	SceneTransition.change_scene(animation_production_lab_path)

func _on_continue_pressed() -> void:
	if LevelProgression.has_lab_resume_state():
		var lab_scene = LevelProgression.get_lab_resume_scene()
		var lab_spawn = LevelProgression.get_lab_resume_spawn()
		LevelProgression.clear_lab_resume_state()
		if lab_spawn.has("player") and lab_spawn.has("camera_offset"):
			LevelProgression.save_spawn_position(lab_scene, lab_spawn["player"], lab_spawn["camera_offset"])
		SceneTransition.change_scene(lab_scene)
	else:
		var scene = LevelProgression.get_resume_scene()
		var spawn = LevelProgression.get_resume_spawn()
		LevelProgression.clear_resume_state()
		if spawn.has("player") and spawn.has("camera_offset"):
			LevelProgression.save_spawn_position(scene, spawn["player"], spawn["camera_offset"])
		SceneTransition.change_scene(scene)

func _on_cutscene_finished() -> void:
	SceneTransition.change_scene(game_scene_path)

func _on_settings_pressed() -> void:
	settings_ui.open()

func _on_settings_closed() -> void:
	pass

func _on_quit_pressed() -> void:
	get_tree().quit()

func _find_or_create_cutscene_player() -> CutscenePlayer:
	var existing := find_children("*", "CutscenePlayer", true, false)
	if existing.size() > 0:
		return existing[0]
	var cs_scene := preload("res://scenes/cutscene/cutscene_player.tscn")
	var cs_player := cs_scene.instantiate() as CutscenePlayer
	add_child(cs_player)
	return cs_player
