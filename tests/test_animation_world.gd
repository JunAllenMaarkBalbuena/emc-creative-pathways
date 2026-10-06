extends SceneTree

## WorldController test: place, select, transform (position/rotation/scale/
## visible), depth offset, layer ordering, reset-to-spawn, duplicate, replace
## asset, and remove, with the registry kept in sync (the source of truth the
## save layer reads from later). Fails when any invariant breaks.

const IDLE_DIR := "res://assets/char_animation/idle"
const BG_PATH := "res://assets/Scene_BG/Menu_Bg_image.png"

func _init() -> void:
	var failures := _run()
	if failures.is_empty():
		print("PASS: world controller place/select/transform/depth/layers")
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

	if wc.add_asset(null) != "":
		failures.append("add_asset(null) should return ''")

	var idle_file := _first_idle_png()
	var char_asset := _asset("char_starter", "character", "sprite", "starter", IDLE_DIR + "/" + idle_file)
	var bg_asset := _asset("bg_starter", "background", "sprite", "starter", BG_PATH)
	var box_asset := _asset("prop_box", "prop", "primitive", "starter", "", {"shape": "box"})
	var cyc_asset := _asset("prop_cyc", "prop", "primitive", "starter", "", {"shape": "cylinder"})
	var prop2_asset := _asset("prop_box2", "prop", "primitive", "starter", "", {"shape": "box"})

	var char_id := wc.add_asset(char_asset, Vector3(0, 0.5, 0))
	var bg_id := wc.add_asset(bg_asset, Vector3(0, 1, -6))
	var prop_id := wc.add_asset(box_asset, Vector3(1.2, 0.45, 0))
	var prop2_id := wc.add_asset(prop2_asset, Vector3(-1.0, 0.45, 0))

	if wc.all_objects().size() != 4:
		failures.append("expected 4 registered objects")
	if not (wc.get_object_node(prop_id).mesh is BoxMesh):
		failures.append("prop should spawn a BoxMesh")

	if wc.set_object_position(char_id, Vector3(1, 2, 3)) == false or wc.get_object_node(char_id).position != Vector3(1, 2, 3):
		failures.append("set_object_position did not move node")
	if wc.get_object(char_id)["position"] != Vector3(1, 2, 3):
		failures.append("position not mirrored in registry")

	wc.set_object_rotation(char_id, Vector3(0, 45, 0))
	if wc.get_object_node(char_id).rotation_degrees != Vector3(0, 45, 0):
		failures.append("rotation did not round-trip")
	wc.set_object_scale(char_id, Vector3(1.5, 1.5, 1.5))
	if wc.get_object_node(char_id).scale != Vector3(1.5, 1.5, 1.5):
		failures.append("scale did not round-trip")
	wc.set_object_visible(char_id, false)
	if wc.get_object_node(char_id).visible != false:
		failures.append("visible did not round-trip")

	wc.set_object_depth(prop_id, 2.0)
	if wc.get_object_node(prop_id).position.z != 0.0 + 2.0:
		failures.append("depth did not offset only z")
	wc.set_object_depth(prop_id, 0.0)
	if wc.get_object_node(prop_id).position.z != 0.0:
		failures.append("depth reset did not restore z")

	var prop_parent: Node3D = wc.get_object_node(prop_id).get_parent()
	wc.set_object_layer(prop_id, 1)
	if prop_parent.get_child(1) != wc.get_object_node(prop_id):
		failures.append("layer reorder did not apply within root")

	wc.set_object_position(char_id, Vector3(9, 9, 9))
	wc.set_object_rotation(char_id, Vector3(1, 2, 3))
	wc.set_object_scale(char_id, Vector3(2, 2, 2))
	wc.set_object_visible(char_id, false)
	wc.set_object_depth(char_id, 5.0)
	wc.reset_object(char_id)
	var cdata := wc.get_object(char_id)
	if cdata["position"] != Vector3(0, 0.5, 0) or cdata["rotation_degrees"] != Vector3.ZERO \
		or cdata["scale"] != Vector3.ONE or cdata["visible"] != true or cdata["depth"] != 0.0:
		failures.append("reset_object did not restore spawn defaults")

	var dup_id := wc.duplicate_object(prop_id)
	if dup_id == "" or dup_id == prop_id:
		failures.append("duplicate did not return a distinct id")
	elif not (wc.get_object_node(dup_id).mesh is BoxMesh) or wc.all_objects().size() != 5:
		failures.append("duplicate did not copy the mesh family")

	if wc.replace_object_asset(prop_id, cyc_asset) == false:
		failures.append("replace_object_asset returned false")
	elif not (wc.get_object_node(prop_id).mesh is CylinderMesh):
		failures.append("replace did not swap to CylinderMesh")
	if wc.get_object_node(prop_id).position != Vector3(1.2, 0.45, 0):
		failures.append("replace did not keep the transform")

	if wc.remove_object(char_id) == false or wc.get_object_node(char_id) != null:
		failures.append("remove did not detach node and registry")
	if wc.all_objects().size() != 4:
		failures.append("remove did not shrink the registry")

	wc.select(prop_id)
	if wc.selected() != prop_id:
		failures.append("select did not set selection")
	wc.clear_selection()
	if wc.selected() != "":
		failures.append("clear_selection did not clear")

	if wc.add_asset(_asset("bad", "prop", "primitive", "starter", "", {"shape": "torus"}), Vector3.ZERO) == "":
		failures.append("add_asset with metadata shape 'torus' should still return an id (defaults to box)")
	if wc.get_object_node(wc.all_objects()[wc.all_objects().size() - 1]) == null:
		failures.append("failed to resolve last added object")

	world_root.free()
	return failures


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