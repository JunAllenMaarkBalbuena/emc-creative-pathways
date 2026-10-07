extends Node

## Starter layer ordering (plan Task 3): the authored starter nodes
## (StarterBackdrop/StarterCharacter/StarterWorkstation) are NOT registered in
## the composition stack — they must never out-rank a player layer. The
## guarantee under test, per approved B2:
##   - every starter renders in the TRANSPARENT pass with effective priority
##     <= RenderOrder.STARTER_PRIORITY (so they always sit behind layers),
##   - every registered renderable's priority >= 1 (strictly above starters),
##   - starter nodes never appear in world.layer_order().
##
## Scene-harness test on purpose: the starter nodes only exist once the lab
## scene is inside a running tree (mirrors test_animation_ui_stages.gd).

const LAB := "res://scenes/animation_production_lab/animation_production_lab.tscn"
const IDLE_DIR := "res://assets/char_animation/idle"
const BG_PATH := "res://assets/Scene_BG/Menu_Bg_image.png"


func _ready() -> void:
	var tree := get_tree()
	var failures := await _run()
	if failures.is_empty():
		print("PASS: starter layers stay behind player layers")
		tree.quit(0)
	else:
		for f in failures:
			print("FAIL: ", f)
		tree.quit(1)


func _run() -> Array[String]:
	var failures: Array[String] = []
	var lab := load(LAB).instantiate() as AnimationProductionLab
	lab.autosave_enabled = false
	lab.enable_creative_studio = false
	add_child(lab)
	await get_tree().process_frame

	var backdrop: Sprite3D = lab.get_node_or_null(
		"UI/SceneViewportContainer/SceneViewport/World/BackgroundRoot/StarterBackdrop")
	var starter_char: Sprite3D = lab.get_node_or_null(
		"UI/SceneViewportContainer/SceneViewport/World/CharacterRoot/StarterCharacter")
	var workstation: MeshInstance3D = lab.get_node_or_null(
		"UI/SceneViewportContainer/SceneViewport/World/PropRoot/StarterWorkstation")

	if backdrop == null or starter_char == null or workstation == null:
		failures.append("one of the three starter nodes is missing from the scene")
		lab.queue_free()
		return failures

	# Sprites carry the instance render_priority; the workstation's effective
	# priority + transparent-pass membership live on its active material.
	if backdrop.render_priority > RenderOrder.STARTER_PRIORITY:
		failures.append("StarterBackdrop must render at or below STARTER_PRIORITY")
	if starter_char.render_priority > RenderOrder.STARTER_PRIORITY:
		failures.append("StarterCharacter must render at or below STARTER_PRIORITY")
	var wmat := workstation.get_active_material(0) as StandardMaterial3D
	if wmat == null:
		failures.append("StarterWorkstation has no active material to measure")
	else:
		if wmat.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA:
			failures.append("StarterWorkstation must render in the transparent pass (opaque meshes sort by depth, breaking B2)")
		if wmat.render_priority > RenderOrder.STARTER_PRIORITY:
			failures.append("StarterWorkstation priority must stay at or below STARTER_PRIORITY")

	# Registered layers: exactly two objects in the stack, both strictly above
	# the starters.
	var idle_file := _first_idle_png()
	var bg_asset := _asset("bg_starter", "background", "sprite", "starter", BG_PATH)
	var char_asset := _asset("char_starter", "character", "sprite", "starter", IDLE_DIR + "/" + idle_file)
	var bg_id := lab.world.add_asset(bg_asset, Vector3(0, 1, -6))
	var char_id := lab.world.add_asset(char_asset, Vector3(0, 0.5, 0))
	if bg_id.is_empty() or char_id.is_empty():
		failures.append("world.add_asset failed inside the lab")
	else:
		var stack := lab.world.layer_order()
		if stack.size() != 2:
			failures.append("layer stack should hold exactly the two added objects, got %s" % stack)
		for starter_name in ["StarterBackdrop", "StarterCharacter", "StarterWorkstation"]:
			if stack.has(starter_name):
				failures.append("%s must not be registered in the layer stack" % starter_name)
		for n in [lab.world.get_object_node(bg_id), lab.world.get_object_node(char_id)]:
			var eff := _effective_priority(n)
			if eff <= RenderOrder.STARTER_PRIORITY:
				failures.append("registered layer priority %d must exceed STARTER_PRIORITY" % eff)

	lab.queue_free()
	return failures


func _effective_priority(node: Node3D) -> int:
	if node is SpriteBase3D:
		return (node as SpriteBase3D).render_priority
	if node is MeshInstance3D:
		var m := node as MeshInstance3D
		var mat := m.material_override as StandardMaterial3D
		return mat.render_priority if mat != null else -1
	return -1


func _asset(id: String, category: String, type: String, source: String, path: String) -> EMCAssetData:
	var a := EMCAssetData.new()
	a.asset_id = id
	a.display_name = id
	a.category = category
	a.asset_type = type
	a.source_lab = source
	a.path = path
	return a


func _first_idle_png() -> String:
	var dir := DirAccess.open(IDLE_DIR)
	if dir == null:
		return ""
	var names: Array[String] = []
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.ends_with(".png"):
			names.append(name)
		name = dir.get_next()
	dir.list_dir_end()
	names.sort()
	return names[0] if names.size() > 0 else ""