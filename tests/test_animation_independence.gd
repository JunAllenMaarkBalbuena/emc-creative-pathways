extends Node

## Gate: the 2.5D Animation Production Lab boots standalone with built-in
## starter assets (character sprite, backdrop, primitive prop, key light)
## and no dependency on any other lab scene. Fails when the scene is
## missing, the world scaffold is wrong, or a starter node is empty.

var _fail := 0

func _ready() -> void:
	var tree := get_tree()
	_fail = await _run()
	tree.quit(_fail)


func _run() -> int:
	var packed := load("res://scenes/animation_production_lab/animation_production_lab.tscn") as PackedScene
	if packed == null:
		print("FAIL: animation_production_lab.tscn failed to load")
		return 1
	var lab := packed.instantiate()
	add_child(lab)
	await get_tree().process_frame

	if not lab is CanvasLayer or (lab.script as Script).resource_path != "res://scripts/animation_production_lab/animation_production_lab.gd":
		print("FAIL: lab root is not the AnimationProductionLab script on CanvasLayer")
		return 1
	if lab.get_node_or_null("UI/SceneViewport") == null:
		print("FAIL: UI/SceneViewport missing")
		return 1
	var world := lab.get_node_or_null("UI/SceneViewport/World")
	if world == null or not world is Node3D:
		print("FAIL: UI/SceneViewport/World missing or not Node3D")
		return 1
	if world.find_children("*", "Camera3D", true, false).is_empty():
		print("FAIL: World has no Camera3D")
		return 1
	var char_root := world.get_node_or_null("CharacterRoot")
	if char_root == null or not _has_textured_sprite(char_root):
		print("FAIL: CharacterRoot has no Sprite3D with a texture")
		return 1
	var prop_root := world.get_node_or_null("PropRoot")
	if prop_root == null or prop_root.find_children("*", "MeshInstance3D", true, false).is_empty():
		print("FAIL: PropRoot has no MeshInstance3D")
		return 1
	var light_root := world.get_node_or_null("LightingRoot")
	if light_root == null or (light_root.find_children("*", "DirectionalLight3D", true, false).is_empty() \
		and light_root.find_children("*", "OmniLight3D", true, false).is_empty()):
		print("FAIL: LightingRoot has no light")
		return 1
	print("PASS: animation lab boots independently with starter world")
	return 0


func _has_textured_sprite(root: Node) -> bool:
	for child in root.get_children():
		if child is Sprite3D and child.texture != null:
			return true
	return false