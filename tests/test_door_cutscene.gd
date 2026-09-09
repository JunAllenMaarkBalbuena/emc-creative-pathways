extends Node

## Regression test: world_demo.tscn assigns cutscene_definition to its lab doors,
## but DoorInteractable had no such property, so the entry cutscene was dropped
## (and the assignment errored at scene load).

var _fail := 0

func _ready() -> void:
	var tree := get_tree()

	# 1. Scene assignments must bind to real DoorInteractable properties.
	var world := (load("res://scenes/world_demo.tscn") as PackedScene).instantiate()
	add_child(world)
	await tree.process_frame
	for door_name in ["CodingDoor", "AnimationDoor", "ThreeDDesignDoor", "GameDevDoor"]:
		var door := world.get_node_or_null(door_name)
		if door == null:
			_fail = 1
			print("FAIL: %s missing in world_demo" % door_name)
			continue
		if door.get("cutscene_definition") == null:
			_fail = 1
			print("FAIL: %s.cutscene_definition is null (property missing?)" % door_name)
	world.queue_free()
	await tree.process_frame

	# 2. Interacting with a door that has a cutscene must play it and defer
	#    the on-open action until the cutscene finishes.
	await _test_deferred_action(tree)

	tree.quit(_fail)

func _test_deferred_action(tree: SceneTree) -> void:
	var door := Area3D.new()
	door.set_script(load("res://scripts/door_interactable.gd"))
	add_child(door)
	await tree.process_frame

	var def := CutsceneDefinition.new()
	def.cutscene_id = "entry_test"
	var frame := CutsceneFrame.new()
	frame.image = _make_texture(Color.YELLOW)
	frame.duration = 0.1
	def.frames = [frame]

	door.set("cutscene_definition", def)
	door.set("enable_on_open_action", true)
	door.set("on_open_action_type", DoorInteractable.OnOpenAction.SET_CONDITION)
	door.set("on_open_condition_id", "door_test_flag")
	door.set("on_open_condition_value", true)
	GameConditions.set_flag("door_test_flag", false)

	door.interact(null)
	if not door.is_open:
		_fail = 1
		print("FAIL: door did not open on interact")
	var cs_nodes := tree.root.find_children("*", "CutscenePlayer", true, false)
	if cs_nodes.size() == 0 or not cs_nodes[0]._is_playing:
		_fail = 1
		print("FAIL: no CutscenePlayer started playing on door interact")
	if GameConditions.get_flag("door_test_flag"):
		_fail = 1
		print("FAIL: on-open action ran before cutscene finished")

	await tree.create_timer(0.6).timeout
	if not GameConditions.get_flag("door_test_flag"):
		_fail = 1
		print("FAIL: on-open action did not run after cutscene finished")
	if _fail == 0:
		print("PASS: doors play entry cutscene and defer on-open action until finished")

func _make_texture(color: Color) -> Texture2D:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)