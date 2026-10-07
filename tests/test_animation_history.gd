extends SceneTree

## EditorHistory (plan Task 4): a two-stack undo/redo over WorldController
## mutations. Ops that mutate composition or transforms must push closures
## that restore exact prior state, and a clear() after a world rebuild (the
## load path) must leave no stale undo entries behind (Review-Focus #3).
##
## Structural SceneTree harness like test_animation_composition.gd: no lab
## scene, just a WorldController with three roots. Node identity is asserted
## through the registry + live nodes: undo of a remove resurrects the SAME id
## at its original layer index with its registry entry intact (including prop
## metadata color, which the resurrecting rebuild must not lose).

const IDLE_DIR := "res://assets/char_animation/idle"
const BG_PATH := "res://assets/Scene_BG/Menu_Bg_image.png"

var _changed := 0


func _init() -> void:
	var failures := _run()
	if failures.is_empty():
		print("PASS: EditorHistory undo/redo over composition + transforms")
		quit(0)
	else:
		for f in failures:
			print("FAIL: ", f)
		quit(1)


func _run() -> Array[String]:
	var failures: Array[String] = []
	var wc := _make_world()
	wc.history.history_changed.connect(_on_changed)

	# --- empty history ------------------------------------------------------
	if wc.undo() or wc.redo():
		failures.append("undo/redo must return false on an empty history")
	if wc.history.can_undo() or wc.history.can_redo():
		failures.append("can_undo/can_redo must be false on an empty history")

	# --- add -> undo -> redo ------------------------------------------------
	var char_id := wc.add_asset(_asset("hero", "character", "sprite", "starter",
		IDLE_DIR + "/" + _first_idle_png()), Vector3(0, 0.5, 0))
	if char_id.is_empty():
		failures.append("add_asset failed")
	if not wc.history.can_undo():
		failures.append("add should push an undo entry")
	if wc.layer_order() != [char_id]:
		failures.append("layer stack should hold the added object, got " + str(wc.layer_order()))

	if not wc.undo():
		failures.append("undo after add should succeed")
	elif not wc.layer_order().is_empty() or not wc.get_object(char_id).is_empty():
		failures.append("undo of add should remove the object everywhere")

	if not wc.redo():
		failures.append("redo after undo-add should succeed")
	elif wc.layer_order() != [char_id]:
		failures.append("redo of add should resurrect at its original layer, got " + str(wc.layer_order()))
	elif not _pos(wc, char_id).is_equal_approx(Vector3(0, 0.5, 0)):
		failures.append("redo of add should restore the node position")

	# --- transform (position) ----------------------------------------------
	wc.set_object_position(char_id, Vector3(1, 2, 3))
	if not _pos(wc, char_id).is_equal_approx(Vector3(1, 2, 3)):
		failures.append("position set should apply")
	if not wc.undo() or not _pos(wc, char_id).is_equal_approx(Vector3(0, 0.5, 0)):
		failures.append("undo should restore the old position")
	if not wc.redo() or not _pos(wc, char_id).is_equal_approx(Vector3(1, 2, 3)):
		failures.append("redo should re-apply the position")

	# --- transform (scale / rotation / depth / visible) ----------------------
	wc.set_object_scale(char_id, Vector3(2, 2, 2))
	wc.undo()
	if not (wc.get_object(char_id).get("scale") as Vector3).is_equal_approx(Vector3.ONE):
		failures.append("undo of scale should restore ONE")
	wc.redo()

	wc.set_object_rotation(char_id, Vector3(0, 90, 0))
	wc.undo()
	if not (wc.get_object(char_id).get("rotation_degrees") as Vector3).is_equal_approx(Vector3.ZERO):
		failures.append("undo of rotation should restore ZERO")
	wc.redo()

	wc.set_object_depth(char_id, 1.5)
	if not is_equal_approx(_pos(wc, char_id).z, 3.0 + 1.5):
		failures.append("depth should shift the node z (got %s)" % _pos(wc, char_id))
	wc.undo()
	if not is_equal_approx(_pos(wc, char_id).z, 3.0):
		failures.append("undo of depth should restore the base z")
	wc.redo()

	var node := wc.get_object_node(char_id)
	if not wc.undo() or node.visible != true:
		failures.append("undo of visibility set should restore visible")
	wc.set_object_visible(char_id, false)
	wc.undo()
	if node.visible != true:
		failures.append("visibility undo chain broken")
	# reset the visible flag for later sections
	wc.set_object_visible(char_id, false)  # push
	wc.set_object_visible(char_id, true)   # push

	# --- rename --------------------------------------------------------------
	wc.rename_layer(char_id, "Hero")
	wc.undo()
	if wc.get_object(char_id).get("display_name", "") != "hero":
		failures.append("undo of rename should restore the old name")
	wc.redo()
	if wc.get_object(char_id).get("display_name", "") != "Hero":
		failures.append("redo of rename should re-apply the name")

	# --- lock ----------------------------------------------------------------
	wc.set_layer_locked(char_id, true)
	wc.undo()
	if wc.get_object(char_id).get("locked", true) != false:
		failures.append("undo of lock should unlock")
	wc.redo()
	if wc.get_object(char_id).get("locked", false) != true:
		failures.append("redo of lock should lock")

	# --- remove -> undo resurrects (registry fidelity incl. prop color) ------
	var prop_id := wc.add_asset(_asset("box", "prop", "primitive", "starter", "",
		{"shape": "box", "color": Color(1, 0, 0, 1)}), Vector3(1.2, 0.45, 0))
	var prop_index := wc.layer_index(prop_id)
	wc.remove_object(prop_id)
	if wc.layer_order().has(prop_id):
		failures.append("remove should drop the object")
	if not wc.undo():
		failures.append("undo of remove should succeed")
	else:
		if not wc.layer_order().has(prop_id) or wc.layer_index(prop_id) != prop_index:
			failures.append("undo of remove should resurrect at its original layer index")
		var pnode := wc.get_object_node(prop_id)
		if pnode == null:
			failures.append("undo of remove should rebuild the node")
		else:
			var pmat := pnode.material_override as StandardMaterial3D
			if pmat == null or not pmat.albedo_color.is_equal_approx(Color(1, 0, 0, 1)):
				failures.append("undo of remove must keep the prop metadata color (rebuild loses it)")
			if not _pos(wc, prop_id).is_equal_approx(Vector3(1.2, 0.45, 0)):
				failures.append("undo of remove should restore the node position")
		if wc.get_object(prop_id).get("element_type", "") != "3d":
			failures.append("undo of remove should restore element_type")
	if not wc.redo():
		failures.append("redo of remove should succeed")
	elif wc.layer_order().has(prop_id):
		failures.append("redo of remove should delete again")

	# --- reorder --------------------------------------------------------------
	var bg_id := wc.add_asset(_asset("bg", "background", "sprite", "starter", BG_PATH),
		Vector3(0, 1, -6))
	# the lock section ended with the redo re-applying locked=true — unlock so
	# the reorder test below can move the layer (locks only guard the public
	# ops; history replay bypasses them on purpose).
	wc.set_layer_locked(char_id, false)
	# current order: [char, bg, prop?] -> prop was re-deleted; stack is [char, bg]
	if wc.layer_order() != [char_id, bg_id]:
		failures.append("reorder precondition wrong: " + str(wc.layer_order()))
	if not wc.move_layer_up(char_id):
		failures.append("move_layer_up should succeed")
	if wc.layer_order() != [bg_id, char_id]:
		failures.append("move_layer_up should go toward the front: " + str(wc.layer_order()))
	if not wc.undo() or wc.layer_order() != [char_id, bg_id]:
		failures.append("undo of reorder should restore [char, bg]: " + str(wc.layer_order()))
	if not wc.redo() or wc.layer_order() != [bg_id, char_id]:
		failures.append("redo of reorder should re-apply [bg, char]: " + str(wc.layer_order()))

	# --- duplicate ------------------------------------------------------------
	var dup_id := wc.duplicate_object(char_id)
	if dup_id.is_empty() or not wc.layer_order().has(dup_id):
		failures.append("duplicate should register a new layer")
	if not wc.undo() or wc.layer_order().has(dup_id):
		failures.append("undo of duplicate should remove the copy")
	if not wc.redo() or wc.layer_order() != [bg_id, char_id, dup_id]:
		failures.append("redo of duplicate should resurrect the copy at the end: " + str(wc.layer_order()))
	if not _pos(wc, dup_id).is_equal_approx(_pos(wc, char_id) + Vector3(0.4, 0, 0)):
		failures.append("duplicate offset should survive undo/redo")

	# --- replace asset --------------------------------------------------------
	if not wc.replace_object_asset(dup_id, _asset("box2", "prop", "primitive", "starter", "",
		{"shape": "box", "color": Color(0, 1, 0, 1)})):
		failures.append("replace_object_asset should succeed")
	elif (wc.get_object(dup_id).get("category", "") as String) != "prop":
		failures.append("replace should switch the category")
	if not wc.undo() or (wc.get_object(dup_id).get("category", "") as String) != "character":
		failures.append("undo of replace should restore the character asset")
	if not wc.redo() or (wc.get_object(dup_id).get("category", "") as String) != "prop":
		failures.append("redo of replace should re-apply the prop asset")

	# --- reset ----------------------------------------------------------------
	wc.set_object_position(char_id, Vector3(5, 5, 5))
	wc.reset_object(char_id)
	if not _pos(wc, char_id).is_equal_approx(Vector3(0, 0.5, 0)):
		failures.append("reset should return to spawn")
	if not wc.undo() or not (wc.get_object(char_id).get("position") as Vector3).is_equal_approx(Vector3(5, 5, 5)):
		failures.append("undo of reset should restore the pre-reset position")
	if not wc.redo() or not _pos(wc, char_id).is_equal_approx(Vector3(0, 0.5, 0)):
		failures.append("redo of reset should return to spawn again")

	# --- a new op after undo discards redo ------------------------------------
	wc.undo()  # back to pre-lock state... any undo; then mutate
	if not wc.history.can_redo():
		failures.append("after one undo redo should be available")
	wc.rename_layer(char_id, "Renamed")
	if wc.history.can_redo():
		failures.append("a fresh op must clear the redo stack")
	if wc.redo():
		failures.append("redo after a fresh op must fail")

	# --- history_changed fired ------------------------------------------------
	if _changed < 1:
		failures.append("history_changed should have fired")

	# --- Review-Focus #3: world rebuild + clear leaves no stale undo ----------
	var doomed := wc.all_objects()
	if doomed.is_empty():
		failures.append("expected surviving objects before the rebuild sim")
	for object_id in doomed:
		wc.remove_object(object_id)
	wc.history.clear()
	if wc.undo() or not wc.layer_order().is_empty():
		failures.append("after rebuild + clear(), stale undo must not resurrect anything")
	if wc.history.can_undo():
		failures.append("clear() should empty the undo stack")

	return failures


func _make_world() -> WorldController:
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
	return wc


func _pos(wc: WorldController, object_id: String) -> Vector3:
	var node := wc.get_object_node(object_id)
	return node.position if node != null else Vector3(-999, -999, -999)


func _on_changed() -> void:
	_changed += 1


func _asset(id: String, category: String, type: String, source: String, path: String,
		extra: Dictionary = {}) -> EMCAssetData:
	var a := EMCAssetData.new()
	a.asset_id = id
	a.display_name = id
	a.category = category
	a.asset_type = type
	a.source_lab = source
	a.path = path
	a.metadata = extra
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