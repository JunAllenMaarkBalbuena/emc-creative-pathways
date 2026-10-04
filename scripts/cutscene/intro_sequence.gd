extends Node

@export var intro_cutscene: CutsceneDefinition
@export var next_scene: String = "res://scenes/main_menu.tscn"

var _cutscene_player

func _ready() -> void:
	var cs_scene := preload("res://scenes/cutscene/cutscene_player.tscn")
	_cutscene_player = cs_scene.instantiate() as CutscenePlayer
	add_child(_cutscene_player)
	_cutscene_player.cutscene_finished.connect(_on_cutscene_finished)
	if intro_cutscene != null:
		_cutscene_player.play(intro_cutscene)

func _on_cutscene_finished() -> void:
	SceneTransition.change_scene(next_scene)
