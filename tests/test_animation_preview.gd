extends SceneTree

## PreviewController test: apply_frame() swaps character sprite textures from
## the frame channel at fps boundaries; apply_keyframes() routes evaluated
## tracks to world/camera/lighting (RF4: an unknown target like "ghost" is
## skipped silently, never an error); step() drives the clock and applies at
## frame-boundary changes; evaluate_review() fills the 10-item checklist from
## measurable controller state only.

const TEX_IDLE := "res://assets/char_animation/idle/1c66b4d4-7798-4026-9ddd-b75a5d3ce19d-8.png"
const TEX_RUN := "res://assets/char_animation/run/7b805aea-b3c0-43fa-a4d2-84ef858de3d6-8.png"
const TEX_BG := "res://assets/Scene_BG/Menu_Bg_image.png"

func _init() -> void:
	var failures := _run()
	if failures.is_empty():
		print("PASS: preview applies frames & keyframes and evaluates the review checklist")
		quit(0)
	else:
		for f in failures:
			print("FAIL: ", f)
		quit(1)


func _run() -> Array[String]:
	var failures: Array[String] = []
	var tex_a := load(TEX_IDLE) as Texture2D
	var tex_b := load(TEX_RUN) as Texture2D

	# Frame channel: 3 frames, one duplicated vs distinct -> 2 poses.
	var frames := FrameController.new()
	frames.add_frame(tex_a, 0.1)
	frames.add_frame(tex_b, 0.1)
	frames.add_frame(tex_a, 0.1)

	var timeline := TimelineController.new()
	timeline.frame_controller_ref = frames
	if not timeline.set_fps(12) or not timeline.set_duration(5.0):
		failures.append("timeline setup failed")

	# Scratch stage: world (one character + one background, both visible),
	# lighting with a resolvable lights root.
	var stage := Node3D.new()
	var world := WorldController.new()
	stage.add_child(world)
	world.add_child(_named_node("Characters"))
	world.add_child(_named_node("Backgrounds"))
	world.add_child(_named_node("Props"))
	world.character_root = NodePath("Characters")
	world.background_root = NodePath("Backgrounds")
	world.prop_root = NodePath("Props")
	var lighting := LightingController.new()
	stage.add_child(lighting)
	var lights := _named_node("Lights")
	stage.add_child(lights)
	lighting.lighting_root = NodePath("../Lights")

	var hero_asset := _asset(WorldController.CATEGORY_CHARACTER, "hero_idle", TEX_IDLE)
	var hero := world.add_asset(hero_asset, Vector3(0, 1, 0))
	var bg_id := world.add_asset(_asset(WorldController.CATEGORY_BACKGROUND, "backdrop", TEX_BG), Vector3(0, 0, -2))
	if hero == "" or bg_id == "":
		failures.append("could not add the scratch world objects")

	var keyframes := KeyframeController.new()
	keyframes.add_keyframe(0.0, hero, KeyframeController.TARGET_OBJECT, "position", Vector3(0, 0, 0))
	keyframes.add_keyframe(1.0, hero, KeyframeController.TARGET_OBJECT, "position", Vector3(2, 0, 0))
	keyframes.add_keyframe(0.5, "ghost", KeyframeController.TARGET_OBJECT, "position", Vector3(9, 9, 9))

	var light_id := lighting.add_light(LightingController.LIGHT_DIRECTIONAL, Vector3(0, 5, 2))
	if light_id == "":
		failures.append("could not add the key light")

	var preview := PreviewController.new()
	preview.timeline = timeline
	preview.frames = frames
	preview.keyframes = keyframes
	preview.world = world
	preview.camera = AnimationCameraController.new()  # camera_path unset -> camera() null
	preview.lighting = lighting

	# apply_frame at the first frame boundary -> frame index 1.
	timeline.current_time = 1.0 / 12.0
	preview.apply_frame()
	var hero_node := world.get_object_node(hero) as Sprite3D
	if hero_node == null or hero_node.texture != frames.frames[1].texture:
		failures.append("apply_frame did not swap to frame 1's texture")

	# apply_keyframes moves the object along the linear track at mid-time.
	timeline.current_time = 0.5
	preview.apply_keyframes()
	var obj_data := world.get_object(hero)
	var pos: Variant = obj_data.get("position", Vector3.ZERO)
	if pos != Vector3(1, 0, 0):
		failures.append("apply_keyframes did not lerp the position to (1,0,0), got %s" % str(pos))

	# step drives clock + keyframes + frame at the boundary change.
	timeline.stop()
	timeline.play()
	preview.step(0.4)
	hero_node = world.get_object_node(hero) as Sprite3D
	if hero_node == null or hero_node.texture != frames.frames[2].texture:
		failures.append("step did not apply the latest frame at the frame boundary")

	# The ghost keyframe must be skipped silently (RF4) — no script error here.
	preview.apply_keyframes()

	# evaluate_review: the 10 measurable items.
	preview.evaluate_review()
	if preview.review_checklist.get("character visible", false) != true:
		failures.append("review: character visible should be true")
	if preview.review_checklist.get("background visible", false) != true:
		failures.append("review: background visible should be true")
	if preview.review_checklist.get("beginning/middle/end present", false) != true:
		failures.append("review: 3 frames should satisfy beginning/middle/end")
	if preview.review_checklist.get("final pose visible", false) != true:
		failures.append("review: final pose should be visible (last frame has a texture)")
	if preview.review_checklist.get("pose change", false) != true:
		failures.append("review: pose change should be true with 2 distinct textures")
	if preview.review_checklist.get("plays without errors", false) != true:
		failures.append("review: plays without errors should be true when wired")

	# Lighting false when the key light is dimmed to 0.
	lighting.set_intensity(light_id, 0.0)
	preview.evaluate_review()
	if preview.review_checklist.get("lighting sufficient", true) != false:
		failures.append("review: lighting sufficient should be false when key energy is 0")

	# Timing false when fps is off by more than the tolerance (12 +- 2).
	timeline.set_fps(30)
	preview.evaluate_review()
	if preview.review_checklist.get("timing correct", true) != false:
		failures.append("review: timing correct should be false at fps 30")
	timeline.set_fps(12)

	return failures


func _named_node(name: String) -> Node3D:
	var node := Node3D.new()
	node.name = name
	return node


func _asset(category: String, id: String, path: String) -> EMCAssetData:
	var asset := EMCAssetData.new()
	asset.asset_id = id
	asset.category = category
	asset.asset_type = "sprite"
	asset.path = path
	return asset