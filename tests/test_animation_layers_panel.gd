extends Node

## LayersPanel docker test (plan Task 5): the guided STAGING..LIGHTING layout
## shows the Layers docker beside the inspector, it renders
## world.layer_summaries() as ordered rows ("name — 2D/3D"), and every row /
## button signal round-trips into the WorldController composition ops — which
## is what makes the panel a *driver* of the stack, not a passive mirror.
##
## Scene-harness test on purpose (same reason as test_animation_ui_stages.gd):
## panels resolve via the CanvasLayer's own Control tree only once the scene
## is running. Autosave + studio are disabled so the boot stays offline.

const LAB := "res://scenes/animation_production_lab/animation_production_lab.tscn"
const IDLE_DIR := "res://assets/char_animation/idle"
const BG_PATH := "res://assets/Scene_BG/Menu_Bg_image.png"

func _ready() -> void:
	var tree := get_tree()
	var failures := await _run()
	if failures.is_empty():
		print("PASS: layers docker reflects and drives the composition stack")
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

	# Pre-implementation guard: without the scene instance the root has no
	# layers_panel at all. get_node_or_null (not lab.layers_panel — a typed
	# access to an undeclared member throws and would hang the harness).
	if lab.get_node_or_null("UI/LayersPanel") == null:
		failures.append("LayersPanel is missing from the lab scene")
		return failures

	lab.assignment_manager.go_to(AnimationAssignmentManager.Stage.STAGING)
	if not lab.layers_panel.visible:
		failures.append("LayersPanel should be visible at STAGING")

	var world := lab.world
	var char_id := world.add_asset(_asset("hero", "character", "sprite", "starter",
		IDLE_DIR + "/" + _first_idle_png()), Vector3(0, 0.5, 0))
	var bg_id := world.add_asset(_asset("bg", "background", "sprite", "starter", BG_PATH),
		Vector3(0, 1, -6))
	var prop_id := world.add_asset(_asset("box", "prop", "primitive", "starter", "",
		{"shape": "box", "color": Color(1, 0, 0, 1)}), Vector3(1.2, 0.45, 0))
	if char_id.is_empty() or bg_id.is_empty() or prop_id.is_empty():
		failures.append("world.add_asset failed")
		return failures

	# --- rows mirror world.layer_summaries() --------------------------------
	var rows := _rows(lab)
	if rows.size() != 3:
		failures.append("objects_changed should refresh the docker rows, got %d" % rows.size())
	else:
		var t0: String = (rows[0] as Button).text
		var t1: String = (rows[1] as Button).text
		var t2: String = (rows[2] as Button).text
		if not t0.contains("hero") or not t0.ends_with("— 2D"):
			failures.append("row 0 should carry 'name — 2D': %s" % t0)
		if not t1.contains("bg") or not t1.ends_with("— 2D"):
			failures.append("row 1 should carry 'name — 2D': %s" % t1)
		if not t2.contains("box") or not t2.ends_with("— 3D"):
			failures.append("row 2 should carry 'name — 3D': %s" % t2)
	if world.layer_order() != [char_id, bg_id, prop_id]:
		failures.append("insertion should append to the stack: " + str(world.layer_order()))

	# --- selecting a row selects on the world -------------------------------
	_rows(lab)[0].emit_signal("pressed")
	if world.selected() != char_id:
		failures.append("row click should select on the world, got %s" % world.selected())
	if not (_rows(lab)[0] as Button).button_pressed:
		failures.append("selected row should be highlighted")

	# --- world.select() highlights the row ----------------------------------
	world.select(bg_id)
	if not (_rows(lab)[1] as Button).button_pressed:
		failures.append("world.select should highlight row 1")
	if (_rows(lab)[0] as Button).button_pressed:
		failures.append("world.select should un-highlight row 0")

	# --- rename field pre-fills the current name on selection ----------------
	# Select bg (the current selection): the field should offer the name to
	# edit, not force typing into an empty box.
	if (lab.layers_panel.get_node("%RenameField") as LineEdit).text != "bg":
		failures.append("selection should pre-fill the rename field with the current name")
	_rows(lab)[0].emit_signal("pressed")  # select char (display_name "hero")
	if (lab.layers_panel.get_node("%RenameField") as LineEdit).text != "hero":
		failures.append("changing selection should refresh the rename field")

	# --- reorder row drives the stack ---------------------------------------
	_rows(lab)[0].emit_signal("pressed")  # select char (back of stack)
	_press(lab, "MoveUpButton")
	if world.layer_order() != [bg_id, char_id, prop_id]:
		failures.append("move_up should step the layer forward: " + str(world.layer_order()))
	_press(lab, "MoveDownButton")
	if world.layer_order() != [char_id, bg_id, prop_id]:
		failures.append("move_down should step the layer backward: " + str(world.layer_order()))
	_press(lab, "ToFrontButton")
	if world.layer_order() != [bg_id, prop_id, char_id]:
		failures.append("to_front should jump to the front: " + str(world.layer_order()))
	_press(lab, "ToBackButton")
	if world.layer_order() != [char_id, bg_id, prop_id]:
		failures.append("to_back should jump to the back: " + str(world.layer_order()))
	_press(lab, "ForwardButton")
	if world.layer_order() != [bg_id, char_id, prop_id]:
		failures.append("forward should step toward the front: " + str(world.layer_order()))
	_press(lab, "BackwardButton")
	if world.layer_order() != [char_id, bg_id, prop_id]:
		failures.append("backward should step toward the back: " + str(world.layer_order()))

	# --- delete -------------------------------------------------------------
	_rows(lab)[0].emit_signal("pressed")  # select char
	_press(lab, "DeleteButton")
	if world.layer_order() != [bg_id, prop_id]:
		failures.append("delete should remove the selected layer: " + str(world.layer_order()))

	# --- duplicate ----------------------------------------------------------
	_rows(lab)[0].emit_signal("pressed")  # select bg
	_press(lab, "DuplicateButton")
	if world.layer_order() != [bg_id, prop_id] \
			and (world.layer_order().size() != 3 \
			or world.layer_order()[-1] == bg_id or world.layer_order()[-1] == prop_id):
		failures.append("duplicate should append a copy at the end: " + str(world.layer_order()))
	var dup_id := world.layer_order()[-1]
	if dup_id == bg_id or dup_id == prop_id:
		failures.append("duplicate should return a fresh id")

	# --- rename -------------------------------------------------------------
	_rows(lab)[2].emit_signal("pressed")  # select the copy (last row)
	(lab.layers_panel.get_node("%RenameField") as LineEdit).text = "Copy"
	_press(lab, "RenameButton")
	if str(world.get_object(dup_id).get("display_name", "")) != "Copy":
		failures.append("rename should update the display name")

	# --- visibility + lock toggles ------------------------------------------
	var dup_node := world.get_object_node(dup_id)
	if dup_node == null:
		failures.append("duplicate node should exist")
	else:
		_rows(lab)[2].emit_signal("pressed")
		(lab.layers_panel.get_node("%VisibleToggle") as CheckButton).emit_signal("toggled", false)
		if dup_node.visible:
			failures.append("visibility toggle should hide the selected layer")
		(lab.layers_panel.get_node("%LockToggle") as CheckButton).emit_signal("toggled", true)
		if not bool(world.get_object(dup_id).get("locked", false)):
			failures.append("lock toggle should lock the selected layer")

	# --- add feeds through the library's selected asset ---------------------
	var before := world.layer_order().size()
	lab.asset_library_panel.set_assets(lab.library.list())
	var lib_rows := lab.asset_library_panel.get_node("%AssetList") as VBoxContainer
	if lib_rows == null or lib_rows.get_child_count() == 0:
		failures.append("asset library should list committed assets")
	else:
		(lib_rows.get_child(0) as Button).emit_signal("pressed")
		_press(lab, "AddButton")
		if world.layer_order().size() != before + 1:
			failures.append("add should grow the stack through the library asset")

	# --- locked layers refuse public reorder (panel respects the lock) ------
	var locked_id := dup_id
	if world.move_layer_up(locked_id):
		failures.append("a locked layer must refuse reorder")

	lab.queue_free()
	return failures


func _rows(lab: AnimationProductionLab) -> Array:
	var list := lab.layers_panel.get_node("%LayerList") as VBoxContainer
	var out: Array = []
	for child in list.get_children():
		out.append(child)
	return out


func _press(lab: AnimationProductionLab, node_name: String) -> void:
	(lab.layers_panel.get_node("%" + node_name) as Button).emit_signal("pressed")


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