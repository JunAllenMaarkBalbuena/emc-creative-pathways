extends SceneTree

## WorldController composition layer stack (plan Task 2): a registry-backed
## ordered stack of ids (_layer_order) with reorder/rename/lock ops, per-layer
## metadata (display_name/element_type/locked), layer_summaries() for the
## Layers docker, and render-priority re-application after every order change
## (B2: higher layer index -> higher transparent-pass priority -> in front).
##
## Mirrors test_animation_world.gd's bootstrap: three starter roots plus
## add_asset for char/bg/prop/prop2. layer_order index 0 = the BACK of the
## stack (drawn behind); the last index = the front (drawn on top).

const IDLE_DIR := "res://assets/char_animation/idle"
const BG_PATH := "res://assets/Scene_BG/Menu_Bg_image.png"


func _init() -> void:
	var failures := _run()
	if failures.is_empty():
		print("PASS: composition layer stack order/rename/lock/summaries")
		quit(0)
	else:
		for f in failures:
			print("FAIL: ", f)
		quit(1)


func _run() -> Array[String]:
	var failures: Array[String] = []
	var world_root := Node3D.new()
	var char_root := Node3D.new()
	char_root.name = "CharacterRoot"
	var bg_root := Node3D.new()
	bg_root.name = "BackgroundRoot"
	var prop_root := Node3D.new()
	prop_root.name = "PropRoot"
	world_root.add_child(char_root)
	world_root.add_child(bg_root)
	world_root.add_child(prop_root)
	var wc := WorldController.new()
	world_root.add_child(wc)
	wc.character_root = NodePath("../CharacterRoot")
	wc.background_root = NodePath("../BackgroundRoot")
	wc.prop_root = NodePath("../PropRoot")

	var idle_file := _first_idle_png()
	var char_asset := _asset("char_starter", "character", "sprite", "starter", IDLE_DIR + "/" + idle_file)
	var bg_asset := _asset("bg_starter", "background", "sprite", "starter", BG_PATH)
	var box_asset := _asset("prop_box", "prop", "primitive", "starter", "", {"shape": "box"})
	var prop2_asset := _asset("prop_box2", "prop", "primitive", "starter", "", {"shape": "box"})

	var char_id := wc.add_asset(char_asset, Vector3(0, 0.5, 0))
	var bg_id := wc.add_asset(bg_asset, Vector3(0, 1, -6))
	var prop_id := wc.add_asset(box_asset, Vector3(1.2, 0.45, 0))
	var prop2_id := wc.add_asset(prop2_asset, Vector3(-1.0, 0.45, 0))

	# --- insertion order + index mapping -----------------------------------
	_expect_order(failures, wc, "insertion", [char_id, bg_id, prop_id, prop2_id])
	if wc.layer_index(char_id) != 0 or wc.layer_index(prop2_id) != 3 or wc.layer_index("nope") != -1:
		failures.append("layer_index mismatch")

	# --- per-layer metadata from add_asset ----------------------------------
	var cdata := wc.get_object(char_id)
	if cdata.get("display_name", "") != "char_starter":
		failures.append("display_name default should be the asset display name")
	if cdata.get("element_type", "") != "2d":
		failures.append("character element_type should be '2d'")
	if wc.get_object(bg_id).get("element_type", "") != "2d":
		failures.append("background element_type should be '2d'")
	if wc.get_object(prop_id).get("element_type", "") != "3d":
		failures.append("prop element_type should be '3d'")
	if wc.get_object(prop2_id).get("element_type", "") != "3d":
		failures.append("prop element_type should be '3d'")
	if wc.get_object(char_id).get("locked", true) != false:
		failures.append("locked should default false")

	# --- render priorities follow layer order (B2 contract) -----------------
	var bg_sprite := wc.get_object_node(bg_id) as Sprite3D
	if bg_sprite == null or bg_sprite.render_priority != RenderOrder.layer_priority(1):
		failures.append("background priority should be layer_priority(1) (got %s)" % [
			bg_sprite.render_priority if bg_sprite else "no-node"])
	var prop_mesh := wc.get_object_node(prop_id) as MeshInstance3D
	var prop_mat: StandardMaterial3D = prop_mesh.material_override as StandardMaterial3D if prop_mesh else null
	if prop_mat == null or prop_mat.render_priority != RenderOrder.layer_priority(2):
		failures.append("prop material priority should be layer_priority(2)")

	# --- reorder ops ---------------------------------------------------------
	if wc.move_layer_up(prop_id) == false:
		failures.append("move_layer_up(prop) should succeed")
	_expect_order(failures, wc, "up", [char_id, bg_id, prop2_id, prop_id])
	if wc.move_layer_down(prop2_id) == false:
		failures.append("move_layer_down(prop2) should succeed")
	_expect_order(failures, wc, "down", [char_id, prop2_id, bg_id, prop_id])
	if wc.layer_to_front(bg_id) == false:
		failures.append("layer_to_front(bg) should succeed")
	_expect_order(failures, wc, "to_front", [char_id, prop2_id, prop_id, bg_id])
	if wc.layer_to_back(prop_id) == false:
		failures.append("layer_to_back(prop) should succeed")
	_expect_order(failures, wc, "to_back", [prop_id, char_id, prop2_id, bg_id])
	if wc.layer_forward(prop2_id) == false:
		failures.append("layer_forward(prop2) should succeed")
	_expect_order(failures, wc, "forward", [prop_id, char_id, bg_id, prop2_id])
	if wc.layer_backward(bg_id) == false:
		failures.append("layer_backward(bg) should succeed")
	_expect_order(failures, wc, "backward", [prop_id, bg_id, char_id, prop2_id])

	# --- no-op edges ----------------------------------------------------------
	var locked_order_before := wc.layer_order()
	if wc.move_layer_up(prop2_id) == false and wc.layer_order() == locked_order_before:
		pass  # last layer, no-op: correct
	else:
		failures.append("move_layer_up on the front-most layer should be a false no-op")
	if wc.layer_backward(prop_id) == false and wc.layer_order() == locked_order_before:
		pass  # back-most layer, no-op: correct
	else:
		failures.append("layer_backward on the back-most layer should be a false no-op")

	# --- reorder_layer (direct index) -----------------------------------------
	if wc.reorder_layer(bg_id, 3) == false:
		failures.append("reorder_layer(bg, 3) should succeed")
	_expect_order(failures, wc, "reorder", [prop_id, char_id, prop2_id, bg_id])
	if wc.reorder_layer(bg_id, 3) != false or wc.reorder_layer("ghost", 0) != false:
		failures.append("reorder_layer no-op / unknown should return false")
	if wc.reorder_layer(char_id, 99) == false:
		failures.append("reorder_layer(char, 99) should clamp and succeed")
	_expect_order(failures, wc, "clamped", [prop_id, prop2_id, bg_id, char_id])

	# --- rename -----------------------------------------------------------------
	if wc.rename_layer(prop2_id, "Star Prop") == false:
		failures.append("rename_layer should succeed")
	if wc.get_object(prop2_id).get("display_name", "") != "Star Prop":
		failures.append("rename_layer did not update display_name")
	if wc.rename_layer("ghost", "X") != false:
		failures.append("rename_layer unknown should return false")

	# --- lock gates every order op ----------------------------------------------
	if wc.set_layer_locked(bg_id, true) == false:
		failures.append("set_layer_locked should succeed")
	var before_lock := wc.layer_order()
	var locked_blocked := wc.move_layer_up(bg_id) == false
	locked_blocked = locked_blocked and wc.move_layer_down(bg_id) == false
	locked_blocked = locked_blocked and wc.layer_to_front(bg_id) == false
	locked_blocked = locked_blocked and wc.layer_to_back(bg_id) == false
	locked_blocked = locked_blocked and wc.layer_forward(bg_id) == false
	locked_blocked = locked_blocked and wc.layer_backward(bg_id) == false
	locked_blocked = locked_blocked and wc.reorder_layer(bg_id, 0) == false
	if not locked_blocked:
		failures.append("a locked layer must refuse every reorder op")
	if wc.layer_order() != before_lock:
		failures.append("reorder ops on a locked layer must not change the order")
	if wc.set_layer_locked(bg_id, false) == false:
		failures.append("unlock should succeed")
	if wc.move_layer_up(bg_id) == false:
		failures.append("unlocked layer should be movable again")

	# --- summary ----------------------------------------------------------------
	var summaries := wc.layer_summaries()
	if summaries.size() != 4:
		failures.append("layer_summaries should list all 4 layers")
	for s in summaries:
		var d := s as Dictionary
		if not d.has_all(["id", "display_name", "element_type", "visible", "locked", "selected"]):
			failures.append("summary missing a key: %s" % d)
	wc.select(prop2_id)
	summaries = wc.layer_summaries()
	var selected_any := false
	var prop2_unlocked := true
	for s in summaries:
		if str(s["id"]) == prop2_id and s["selected"]:
			selected_any = true
		if str(s["id"]) == prop2_id and s["locked"]:
			prop2_unlocked = false
	if not selected_any:
		failures.append("summary should flag the selected layer")
	if not prop2_unlocked:
		failures.append("summary must report prop2 as unlocked")

	# --- remove drops the id and re-applies remaining priorities ------------------
	if wc.remove_object(char_id) == false:
		failures.append("remove should succeed")
	var order_after_remove := wc.layer_order()
	if order_after_remove.has(char_id) or order_after_remove.size() != 3:
		failures.append("remove must drop the id from layer_order")
	var bg_reprio := wc.get_object_node(bg_id) as Sprite3D
	if bg_reprio.render_priority != RenderOrder.layer_priority(2):
		failures.append("after remove, surviving layers must get fresh priorities (bg -> 2)")

	# --- duplicate appends to the top and gets the top priority -------------------
	var dup_id := wc.duplicate_object(prop_id)
	if dup_id == "":
		failures.append("duplicate should succeed")
	else:
		var order := wc.layer_order()
		if order[order.size() - 1] != dup_id:
			failures.append("duplicate should append to the top of the stack")
		if wc.get_object(dup_id).get("locked", true) != false:
			failures.append("duplicate keeps locked=false")
		var dup_mat := (wc.get_object_node(dup_id) as MeshInstance3D).material_override as StandardMaterial3D
		if dup_mat == null or dup_mat.render_priority != RenderOrder.layer_priority(order.size() - 1):
			failures.append("duplicate should carry the fresh top priority")

	world_root.free()
	return failures


func _expect_order(failures: Array[String], wc: WorldController, label: String, expected: Array) -> void:
	var actual := wc.layer_order()
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [label, expected, actual])


func _asset(id: String, category: String, type: String, source: String, path: String, metadata: Dictionary = {}) -> EMCAssetData:
	var a := EMCAssetData.new()
	a.asset_id = id
	a.display_name = id
	a.category = category
	a.asset_type = type
	a.source_lab = source
	a.path = path
	a.metadata = metadata
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