class_name ModelingLab
extends CanvasLayer

signal lab_closed

@export_file("*.tscn") var fallback_scene := "res://scenes/main_menu.tscn"

enum LabMode { LESSON, CREATIVE_STUDIO }
enum Tool { MOVE, ROTATE, SCALE }

# Subsystems
var snap_settings: SnapSettings
var spawner: PrimitiveSpawner
var selection_manager: SelectionManager
var transform_manager: TransformManager
var accuracy_manager: AccuracyManager
var scoring_manager: ScoringManager
var assignment_manager: AssignmentManager
var ghost_guide_manager: GhostGuideManager
var material_manager: MaterialManager
var hierarchy_manager: HierarchyManager
var save_manager: SaveManager
var portfolio_manager: PortfolioManager3D
var undo_manager: UndoManager
var creative_studio_manager: CreativeStudioManager

# Mode state
var _mode: int = LabMode.LESSON
var _current_tool: int = Tool.MOVE
var _current_assignment: AssignmentData = null
var _primitive_locked: Array[bool] = []
var _player_objects: Array[Node3D] = []
var _scores: Array[float] = []
var _all_assignments_completed: bool = false
var _dragging: bool = false
var _drag_axis: Vector3 = Vector3.ZERO
var _drag_uniform: bool = true
var _drag_start_mouse: Vector2 = Vector2.ZERO
var _drag_axis_screen: Vector2 = Vector2.RIGHT
var _drag_axis_perp: Vector2 = Vector2.UP

# Workspace references
var workspace: Node3D
var object_container: Node3D
var ghost_container: Node3D
var gizmo: Gizmo3D
var camera_controller: CameraController

# Called by main menu
static func launch():
	SceneTransition.change_scene("res://scenes/modeling_lab/modeling_lab.tscn")


func _ready():
	workspace = $SubViewportContainer/SubViewport/Workspace
	object_container = workspace.get_node("ObjectContainer")
	ghost_container = workspace.get_node("GhostContainer")
	gizmo = workspace.get_node("Gizmo3D")
	camera_controller = workspace.get_node("CameraController")

	snap_settings = SnapSettings.new()
	spawner = PrimitiveSpawner.new()
	selection_manager = SelectionManager.new(object_container)
	transform_manager = TransformManager.new(selection_manager, snap_settings)
	accuracy_manager = AccuracyManager.new()
	scoring_manager = ScoringManager.new()
	assignment_manager = AssignmentManager.new()
	material_manager = MaterialManager.new()
	hierarchy_manager = HierarchyManager.new(object_container)
	save_manager = SaveManager.new()
	portfolio_manager = PortfolioManager3D.new(save_manager)
	undo_manager = UndoManager.new()
	creative_studio_manager = CreativeStudioManager.new()

	ghost_guide_manager = GhostGuideManager.new(ghost_container)

	_connect_ui_signals()
	_find_ui_nodes()
	_setup_tool_group()
	_check_creative_studio_unlock()
	_load_current_lesson()

	if not selection_manager.get_selected():
		gizmo.visible = false
	camera_controller.fit_all.call_deferred(_player_objects)
	_update_zoom_display()

	var view_orbit_gizmo := get_node_or_null("SubViewportContainer/ViewOrbitGizmo") as ViewOrbitGizmo
	if view_orbit_gizmo:
		view_orbit_gizmo.orbit_by.connect(camera_controller.orbit_by)
		view_orbit_gizmo.view_axis_requested.connect(camera_controller.set_view_axis)
		view_orbit_gizmo.view_reset_requested.connect(_on_gizmo_reset_view)


func _find_ui_nodes():
	pass  # %UniqueName lookups happen on demand in signal handlers


func _setup_tool_group():
	var group := ButtonGroup.new()
	%MoveBtn.button_group = group
	%RotateBtn.button_group = group
	%ScaleBtn.button_group = group
	%MoveBtn.set_pressed_no_signal(true)


func _connect_ui_signals():
	# Top bar
	%CloseBtn.pressed.connect(_on_close)
	%HintBtn.pressed.connect(_on_hint)
	%BackBtn.pressed.connect(_on_back)

	# Tool buttons
	%MoveBtn.pressed.connect(_on_tool_selected.bind(Tool.MOVE))
	%RotateBtn.pressed.connect(_on_tool_selected.bind(Tool.ROTATE))
	%ScaleBtn.pressed.connect(_on_tool_selected.bind(Tool.SCALE))

	# Actions
	%DuplicateBtn.pressed.connect(_on_duplicate)
	%DeleteBtn.pressed.connect(_on_delete)
	%ResetBtn.pressed.connect(_on_reset)
	%CenterBtn.pressed.connect(_on_center)
	%FocusBtn.pressed.connect(_focus_selected)

	# Toggles
	%GridToggle.toggled.connect(_on_grid_toggled)
	%SnapToggle.toggled.connect(_on_snap_toggled)
	%SnapSize.value_changed.connect(_on_snap_size_changed)

	# Selection
	selection_manager.selected_changed.connect(_on_selection_changed)

	# SubViewport input
	%SubViewportContainer.mouse_filter = Control.MOUSE_FILTER_STOP
	%SubViewportContainer.gui_input.connect(_on_viewport_gui_input)

	# Material panel
	%ColorSwatch.gui_input.connect(_on_color_swatch_clicked)
	%MetallicSlider.value_changed.connect(_on_metallic_changed)
	%RoughnessSlider.value_changed.connect(_on_roughness_changed)
	for btn in [%PlasticBtn, %MetalBtn, %WoodBtn, %StoneBtn, %GlassBtn]:
		btn.pressed.connect(_on_preset_pressed.bind(btn.text.to_lower()))

	# Hierarchy
	%RenameBtn.pressed.connect(_on_hierarchy_rename)
	%ParentBtn.pressed.connect(_on_hierarchy_parent)
	%UnparentBtn.pressed.connect(_on_hierarchy_unparent)
	%Tree.item_selected.connect(_on_hierarchy_selected)

	# Inspector
	%NodeName.text_submitted.connect(_on_inspector_name_changed)
	%PosX.value_changed.connect(_on_inspector_pos_changed.bind("x"))
	%PosY.value_changed.connect(_on_inspector_pos_changed.bind("y"))
	%PosZ.value_changed.connect(_on_inspector_pos_changed.bind("z"))
	%RotX.value_changed.connect(_on_inspector_rot_changed.bind("x"))
	%RotY.value_changed.connect(_on_inspector_rot_changed.bind("y"))
	%RotZ.value_changed.connect(_on_inspector_rot_changed.bind("z"))
	%ScaleX.value_changed.connect(_on_inspector_scale_changed.bind("x"))
	%ScaleY.value_changed.connect(_on_inspector_scale_changed.bind("y"))
	%ScaleZ.value_changed.connect(_on_inspector_scale_changed.bind("z"))

	# Portfolio
	portfolio_manager.portfolio_changed.connect(_on_portfolio_changed)
	portfolio_manager.model_opened.connect(_on_model_opened)

	# Spawn menu
	%SpawnBtn.get_popup().id_pressed.connect(_on_spawn_selected)

	# Dialogs
	%SaveDialog/VBox/HBox/SaveBtn.pressed.connect(_on_save_confirm)
	%SaveDialog/VBox/HBox/CancelBtn.pressed.connect(_on_save_cancel)
	%LoadDialog/VBox/HBox/OpenBtn.pressed.connect(_on_load_open)
	%LoadDialog/VBox/HBox/DeleteBtn.pressed.connect(_on_load_delete)
	%LoadDialog/VBox/HBox/CancelBtn.pressed.connect(_on_load_cancel)
	%CompletionPanel/VBox/ContBtn.pressed.connect(_on_complete_continue)
	%CreativeStudioUnlockPanel/VBox/OkBtn.pressed.connect(_on_enter_creative_studio)

	# Mode toggle
	%ModeBtn.pressed.connect(_on_mode_toggle)


func _load_current_lesson():
	_current_assignment = assignment_manager.load_index(0)
	if _current_assignment:
		_setup_assignment(_current_assignment)


func _setup_assignment(data: AssignmentData):
	_clear_objects()
	var _discarded_ghosts: Array[MeshInstance3D] = ghost_guide_manager.spawn_for_assignment(data, spawner)
	_spawn_player_primitives(data)
	_primitive_locked = []
	_scores = []
	for i in data.primitives.size():
		_primitive_locked.append(false)
		_scores.append(0.0)
	_update_assignment_ui()
	camera_controller.fit_all(_player_objects)
	_hide_all_dialogs()
	_rebuild_hierarchy_request()

func _clear_objects():
	if selection_manager:
		selection_manager.deselect_all()
	for child in object_container.get_children():

		if child is MeshInstance3D and not child.is_in_group("ghost_guides"):
			child.queue_free()
	_player_objects.clear()


func _spawn_player_primitives(data: AssignmentData):
	for i in data.primitives.size():
		var def := data.primitives[i]
		var mi := spawner.spawn(def.type, object_container)
		mi.position = def.target_position + Vector3(1.5, 0, 1.5)
		mi.rotation_degrees = def.target_rotation
		mi.scale = def.target_scale
		if def.material_color != Color.WHITE:
			material_manager.apply_to(mi, {albedo = def.material_color, metallic = def.material_metallic, roughness = def.material_roughness})
		mi.add_to_group("player_objects")
		_player_objects.append(mi)
	if _player_objects.size() > 0:
		selection_manager.select(_player_objects[0])


func _process(_delta):
	if _mode == LabMode.LESSON and _current_assignment:
		_update_assignment_accuracy()
	if gizmo and gizmo.visible and _dragging:
		_update_gizmo_drag()


func _update_assignment_accuracy():
	if not _current_assignment:
		return
	var any_changed := false
	for i in _current_assignment.primitives.size():
		if _primitive_locked[i]:
			continue
		var player: Node3D = _player_objects[i] if i < _player_objects.size() else null
		var ghost := ghost_guide_manager.get_ghost(i)
		if not player or not ghost:
			continue
		var result := accuracy_manager.compare(player.transform, ghost.transform)
		_scores[i] = result.overall
		ghost_guide_manager.update_feedback(i, result)

		if accuracy_manager.is_perfect(result) or result.overall >= 98.0:
			_primitive_locked[i] = true
			any_changed = true

	if any_changed:
		# Check if all locked
		var all_locked := true
		for locked in _primitive_locked:
			if not locked:
				all_locked = false
				break
		if all_locked:
			_on_assignment_complete()

	_update_accuracy_ui()

func _update_accuracy_ui():
	if _scores.is_empty():
		return
	var _avg := 0.0
	for s in _scores:
		_avg += s
	_avg /= _scores.size()
	if _scores.size() >= 1:
		%PosAcc.value = _scores[0]
	if _scores.size() >= 2:
		%RotAcc.value = _scores[1] if _scores.size() > 1 else _scores[0]
	if _scores.size() >= 3:
		%ScaleAcc.value = _scores[2] if _scores.size() > 2 else _scores[0]


func _update_assignment_ui():
	if not _current_assignment:
		return
	%LessonLabel.text = "Lesson %d: %s" % [_current_assignment.lesson_number, _current_assignment.display_name]
	%Assignment/LessonTitle.text = "Lesson %d: %s" % [_current_assignment.lesson_number, _current_assignment.display_name]
	%Assignment/Instructions.text = _current_assignment.instruction_text


func _on_assignment_complete():
	var final_score := scoring_manager.calculate_final(_scores)
	var grade := scoring_manager.grade_from_percent(final_score)
	var label := scoring_manager.grade_label(final_score)
	var color := scoring_manager.grade_color(final_score)

	assignment_manager.mark_current_completed(final_score)

	%CompletionPanel/VBox/ScoreLabel.text = "Score: %.1f%%" % final_score
	%CompletionPanel/VBox/GradeLabel.text = "Grade: %s — %s" % [grade, label]
	%CompletionPanel/VBox/GradeLabel.modulate = color
	%CompletionPanel.visible = true

	_check_creative_studio_unlock()
	_check_all_completed()


func _check_creative_studio_unlock():
	if assignment_manager.is_creative_studio_unlocked():
		creative_studio_manager.set_unlocked(true)
		if _mode == LabMode.LESSON and not %CreativeStudioUnlockPanel.visible:
			%CreativeStudioUnlockPanel.visible = true


func _check_all_completed():
	if assignment_manager.progress.completed_ids.size() >= 7:
		_all_assignments_completed = true


func _on_complete_continue():
	%CompletionPanel.visible = false
	if assignment_manager.has_next():
		_current_assignment = assignment_manager.advance()
		if _current_assignment:
			_setup_assignment(_current_assignment)
	else:
		_enter_creative_studio()


func _on_enter_creative_studio():
	%CreativeStudioUnlockPanel.visible = false
	_enter_creative_studio()


func _enter_creative_studio():
	_mode = LabMode.CREATIVE_STUDIO
	_clear_objects()
	ghost_guide_manager.clear()
	%SpawnBtn.visible = true
	%LessonLabel.text = "Creative Studio — Free Modeling"
	%Assignment/LessonTitle.text = "Creative Studio"
	%Assignment/Instructions.text = "Spawn primitives, edit materials, and save your creations!"
	_hide_all_dialogs()
	_rebuild_hierarchy_request()

	# Build spawn menu
	var popup: PopupMenu = %SpawnBtn.get_popup()
	popup.clear()
	for i in PrimitiveDef.Type.size():
		popup.add_item(PrimitiveDef.Type.keys()[i], i)


func _on_spawn_selected(id: int):
	if _mode == LabMode.CREATIVE_STUDIO:
		var mi := spawner.spawn(id, object_container)
		mi.position = Vector3(0, 0.5, 0)
		selection_manager.select(mi)
		camera_controller.fit_all([mi])
		_rebuild_hierarchy_request()


func _on_tool_selected(tool: int):
	_current_tool = tool
	var names: Dictionary = {Tool.MOVE: "Move", Tool.ROTATE: "Rotate", Tool.SCALE: "Scale"}
	%ToolLabel.text = "Tool: " + names.get(tool, "Move")
	gizmo.set_mode(tool)
	if selection_manager.get_selected():
		gizmo.visible = true


func _on_selection_changed(node: MeshInstance3D):
	if node:
		gizmo.set_target(node)
		gizmo.visible = (_mode == LabMode.CREATIVE_STUDIO) or (_mode == LabMode.LESSON)
		_update_inspector(node)
	else:
		gizmo.visible = false


# ── Viewport Input ──────────────────────────────────────────────

func _on_viewport_gui_input(event: InputEvent):
	var sv: SubViewport = %SubViewport
	var mouse_pos: Vector2 = sv.get_mouse_position()

	# Camera gets first chance
	if camera_controller.handle_input(event):
		_update_zoom_display()
		get_viewport().set_input_as_handled()
		return

	# Selection on left click
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# Start transform drag if a gizmo handle was grabbed
		if selection_manager.get_selected():
			var pick := gizmo.pick(mouse_pos, camera_controller.camera)
			if pick.get("picked", false):
				_dragging = true
				_drag_axis = pick.get("axis", Vector3.ZERO)
				_drag_uniform = pick.get("uniform", true)
				_drag_start_mouse = mouse_pos
				if _drag_uniform:
					_drag_axis_screen = Vector2.RIGHT
					_drag_axis_perp = Vector2.UP
				else:
					var sel := selection_manager.get_selected()
					var origin := camera_controller.camera.unproject_position(sel.global_position)
					var tip := camera_controller.camera.unproject_position(sel.global_position + _drag_axis)
					_drag_axis_screen = (tip - origin).normalized()
					_drag_axis_perp = Vector2(-_drag_axis_screen.y, _drag_axis_screen.x)
				match _current_tool:
					Tool.MOVE: transform_manager.begin_move(_drag_axis)
					Tool.ROTATE: transform_manager.begin_rotate(_drag_axis)
					Tool.SCALE: transform_manager.begin_scale(_drag_uniform)
				get_viewport().set_input_as_handled()
				return

		# Select the object under the cursor
		var selected := selection_manager.select_from_click(mouse_pos, camera_controller.camera)
		if selected:
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _dragging:
			_dragging = false
			match _current_tool:
				Tool.MOVE: transform_manager.end_move()
				Tool.ROTATE: transform_manager.end_rotate()
				Tool.SCALE: transform_manager.end_scale()

	if event is InputEventMouseMotion and _dragging:
		var moved: Vector2 = mouse_pos - _drag_start_mouse
		var dist: float = moved.dot(_drag_axis_screen)
		match _current_tool:
			Tool.MOVE:
				transform_manager.apply_move(_drag_axis, dist * 0.02)
			Tool.ROTATE:
				var tangential: float = moved.dot(_drag_axis_perp)
				transform_manager.apply_rotate(_drag_axis, tangential * 0.001)
			Tool.SCALE:
				if _drag_uniform:
					transform_manager.apply_scale(_drag_axis, _scale_delta(mouse_pos, _drag_start_mouse, _drag_axis_screen), true)
				else:
					transform_manager.apply_scale(_drag_axis, _scale_delta(mouse_pos, _drag_start_mouse, _drag_axis_screen), false)
		_update_inspector(selection_manager.get_selected())

	# Keyboard shortcuts
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_W: %MoveBtn.button_pressed = true; _on_tool_selected(Tool.MOVE)
			KEY_E: %RotateBtn.button_pressed = true; _on_tool_selected(Tool.ROTATE)
			KEY_R: %ScaleBtn.button_pressed = true; _on_tool_selected(Tool.SCALE)
			KEY_D: _on_duplicate()
			KEY_DELETE: _on_delete()
			KEY_F: _focus_selected()
			KEY_Z:
				if event.ctrl_pressed:
					if event.shift_pressed: _on_redo()
					else: _on_undo()
			KEY_Y: if event.ctrl_pressed: _on_redo()
			KEY_S: if event.ctrl_pressed: _on_save()
			KEY_O: if event.ctrl_pressed: _on_load()


# Signed projection of a screen-space drag onto the scale direction. Positive
# grows, negative shrinks — both uniform (center handle, right = grow) and
# axial handles use this formula.
func _scale_delta(mouse_now: Vector2, grab_start: Vector2, screen_axis: Vector2) -> float:
	return (mouse_now - grab_start).dot(screen_axis)


func _update_gizmo_drag():
	if selection_manager.get_selected():
		gizmo.global_position = selection_manager.get_selected().global_position


func _update_inspector(node: Node3D):
	if not node:
		%NodeName.text = ""
		%PosX.set_value_no_signal(0); %PosY.set_value_no_signal(0); %PosZ.set_value_no_signal(0)
		%RotX.set_value_no_signal(0); %RotY.set_value_no_signal(0); %RotZ.set_value_no_signal(0)
		%ScaleX.set_value_no_signal(1); %ScaleY.set_value_no_signal(1); %ScaleZ.set_value_no_signal(1)
		return
	%NodeName.text = node.name
	%PosX.set_value_no_signal(node.position.x)
	%PosY.set_value_no_signal(node.position.y)
	%PosZ.set_value_no_signal(node.position.z)
	%RotX.set_value_no_signal(node.rotation_degrees.x)
	%RotY.set_value_no_signal(node.rotation_degrees.y)
	%RotZ.set_value_no_signal(node.rotation_degrees.z)
	%ScaleX.set_value_no_signal(node.scale.x)
	%ScaleY.set_value_no_signal(node.scale.y)
	%ScaleZ.set_value_no_signal(node.scale.z)

	var mat := material_manager.read_from(node as MeshInstance3D)
	%ColorSwatch.color = mat.get("albedo", Color.WHITE)
	%MetallicSlider.set_value_no_signal(mat.get("metallic", 0.0))
	%RoughnessSlider.set_value_no_signal(mat.get("roughness", 0.5))

	_update_bottom_bar(node)


func _update_bottom_bar(node: Node3D):
	var t := "X: %.2f  Y: %.2f  Z: %.2f" % [node.position.x, node.position.y, node.position.z]
	%TransformLabel.text = t


func _focus_selected():
	var sel := selection_manager.get_selected()
	if sel:
		camera_controller.focus_on(sel.global_position)


func _on_gizmo_reset_view():
	camera_controller.reset_view()


# ── Actions ─────────────────────────────────────────────────────

func _on_duplicate():
	var copy := transform_manager.duplicate_selected()
	if copy:
		undo_manager.push_duplicate(copy.get_path())
		_rebuild_hierarchy_request()


func _on_delete():
	var sel := selection_manager.get_selected()
	if sel:
		undo_manager.push_delete(sel.get_path(), {name = sel.name})
		transform_manager.delete_selected()
		_rebuild_hierarchy_request()


func _on_reset():
	transform_manager.reset_selected()
	if selection_manager.get_selected():
		_update_inspector(selection_manager.get_selected())


func _on_center():
	transform_manager.center_selected()
	if selection_manager.get_selected():
		_update_inspector(selection_manager.get_selected())


func _on_grid_toggled(val: bool):
	snap_settings.grid_visible = val


func _on_snap_toggled(val: bool):
	snap_settings.snap_enabled = val


func _on_snap_size_changed(val: float):
	snap_settings.position_snap = val


func _on_hint():
	_show_toast("W: Move | E: Rotate | R: Scale | D: Duplicate | Del: Delete | F: Focus")


# ── Material Panel ──────────────────────────────────────────────

func _on_color_swatch_clicked(event: InputEvent):
	if event is InputEventMouseButton and event.pressed:
		var sel := selection_manager.get_selected() as MeshInstance3D
		if sel:
			%ColorSwatch.color = Color(randf(), randf(), randf(), 1)
			material_manager.apply_to(sel, {albedo = %ColorSwatch.color})


func _on_metallic_changed(val: float):
	var sel := selection_manager.get_selected() as MeshInstance3D
	if sel:
		material_manager.apply_to(sel, {metallic = val, roughness = %RoughnessSlider.value, albedo = %ColorSwatch.color})


func _on_roughness_changed(val: float):
	var sel := selection_manager.get_selected() as MeshInstance3D
	if sel:
		material_manager.apply_to(sel, {metallic = %MetallicSlider.value, roughness = val, albedo = %ColorSwatch.color})


func _on_preset_pressed(preset_name: String):
	var sel := selection_manager.get_selected() as MeshInstance3D
	if sel:
		material_manager.apply_preset(preset_name, sel)
		var props := material_manager.get_preset_props(preset_name)
		%ColorSwatch.color = props.get("albedo", Color.WHITE)
		%MetallicSlider.value = props.get("metallic", 0.0)
		%RoughnessSlider.value = props.get("roughness", 0.5)


# ── Hierarchy ──────────────────────────────────────────────────

var _hierarchy_refresh_queued := false

# Rebuilds are deferred so they (a) run after queue_free() deletions from this
# frame actually remove their nodes, and (b) never execute synchronously inside
# a Tree mouse-selection handler (Godot blocks clear()/create_item() there).
func _rebuild_hierarchy_request():
	if _hierarchy_refresh_queued:
		return
	_hierarchy_refresh_queued = true
	call_deferred("_flush_hierarchy_rebuild")


func _flush_hierarchy_rebuild():
	await get_tree().process_frame
	_hierarchy_refresh_queued = false
	if is_inside_tree():
		_rebuild_hierarchy()


func _rebuild_hierarchy():
	var tree: Tree = %Tree
	tree.clear()
	var root: TreeItem = tree.create_item()
	for entry in hierarchy_manager.get_tree_data():
		var item: TreeItem = tree.create_item(root)
		item.set_text(0, entry.name)
		item.set_metadata(0, entry.node)
		item.set_custom_color(0, Color(0.9, 0.9, 0.95))


func _on_hierarchy_selected():
	var item: TreeItem = %Tree.get_selected()
	if not item:
		return
	var meta: Variant = item.get_metadata(0)
	if not is_instance_valid(meta):
		_rebuild_hierarchy_request()
		return
	var node := meta as Node3D
	if node is MeshInstance3D:
		selection_manager.select_node(node)


func _on_hierarchy_rename():
	var item: TreeItem = %Tree.get_selected()
	if not item:
		return
	var meta: Variant = item.get_metadata(0)
	if not is_instance_valid(meta):
		_rebuild_hierarchy_request()
		return
	var node := meta as Node3D
	if hierarchy_manager.rename(node, node.name + "_renamed"):
		_rebuild_hierarchy_request()


func _on_hierarchy_parent():
	var item: TreeItem = %Tree.get_selected()
	if not item:
		return
	var meta: Variant = item.get_metadata(0)
	if not is_instance_valid(meta):
		_rebuild_hierarchy_request()
		return
	var child := meta as Node3D
	if child.get_parent() != object_container:
		hierarchy_manager.reparent(child, object_container)
		_rebuild_hierarchy_request()


func _on_hierarchy_unparent():
	var item: TreeItem = %Tree.get_selected()
	if not item:
		return
	var meta: Variant = item.get_metadata(0)
	if not is_instance_valid(meta):
		_rebuild_hierarchy_request()
		return
	var node := meta as Node3D
	if hierarchy_manager.reparent(node, object_container):
		_rebuild_hierarchy_request()


func _on_hierarchy_selected_in_tree(node_path: NodePath):
	var node := object_container.get_node(node_path) as Node3D
	if node:
		selection_manager.select_node(node)


# ── Inspector ──────────────────────────────────────────────────

func _on_inspector_name_changed(new_name: String):
	var sel := selection_manager.get_selected()
	if sel:
		hierarchy_manager.rename(sel, new_name)
		_rebuild_hierarchy_request()


func _on_inspector_pos_changed(val: float, axis: String):
	var sel := selection_manager.get_selected()
	if not sel: return
	var p := sel.position
	match axis:
		"x": p.x = val
		"y": p.y = val
		"z": p.z = val
	sel.position = p
	_update_bottom_bar(sel)


func _on_inspector_rot_changed(val: float, axis: String):
	var sel := selection_manager.get_selected()
	if not sel: return
	var r := sel.rotation_degrees
	match axis:
		"x": r.x = val
		"y": r.y = val
		"z": r.z = val
	sel.rotation_degrees = r


func _on_inspector_scale_changed(val: float, axis: String):
	var sel := selection_manager.get_selected()
	if not sel: return
	var s := sel.scale
	match axis:
		"x": s.x = val
		"y": s.y = val
		"z": s.z = val
	sel.scale = s


# ── Save / Load ────────────────────────────────────────────────

func _on_save():
	if _mode == LabMode.CREATIVE_STUDIO:
		%SaveDialog/VBox/NameEdit.text = ""
		%SaveDialog/VBox/ErrorLabel.visible = false
		%SaveDialog.visible = true
	else:
		_show_toast("Saving is only available in Creative Studio")


func _on_save_confirm():
	var name_val: String = %SaveDialog/VBox/NameEdit.text.strip_edges()
	if name_val.is_empty():
		name_val = "My_Model"
	var data := save_manager.capture_model(object_container, name_val)
	var path := save_manager.save_model(data, name_val)
	if not path.is_empty():
		%SaveDialog.visible = false
		portfolio_manager.refresh()
		_show_toast("Saved: " + name_val)
	else:
		%SaveDialog/VBox/ErrorLabel.visible = true


func _on_save_cancel():
	%SaveDialog.visible = false


func _on_load():
	portfolio_manager.refresh()
	_rebuild_portfolio_browser()
	%LoadDialog.visible = true


func _on_load_open():
	var sel: PackedInt32Array = %LoadDialog/VBox/ItemList.get_selected_items()
	if sel.size() > 0:
		var ok := portfolio_manager.open_artifact(sel[0])
		if ok:
			%LoadDialog.visible = false
		else:
			_show_toast("Failed to load model")
	else:
		_show_toast("Select a model first")


func _on_load_delete():
	var sel: PackedInt32Array = %LoadDialog/VBox/ItemList.get_selected_items()
	if sel.size() > 0:
		portfolio_manager.delete_artwork(sel[0])
		portfolio_manager.refresh()


func _on_load_cancel():
	%LoadDialog.visible = false


func _on_portfolio_changed():
	_rebuild_portfolio_browser()


func _on_model_opened(data: ModelData, _path: String):
	if _mode == LabMode.CREATIVE_STUDIO:
		_clear_objects()
		save_manager.restore_model(object_container, data, spawner)
		_rebuild_hierarchy_request()
		var objects: Array[Node3D] = []
		for child in object_container.get_children():
			if child is MeshInstance3D:
				objects.append(child)
		camera_controller.fit_all(objects)


func _rebuild_portfolio_browser():
	var list: ItemList = %LoadDialog/VBox/ItemList
	list.clear()
	for entry in portfolio_manager.get_entries():
		list.add_item(entry.name)


# ── Mode ────────────────────────────────────────────────────────

func _on_mode_toggle():
	%ModeBtn.text = "Local" if %ModeBtn.text == "World" else "World"


func _update_zoom_display():
	var zoom := camera_controller.get_distance()
	%ZoomLabel.text = "Zoom: %.0f%%" % ((8.0 / max(zoom, 0.1)) * 100.0)


# ── Undo / Redo ────────────────────────────────────────────────

func _on_undo():
	var action := undo_manager.undo()
	if action.is_empty():
		return
	match action.type:
		"transform":
			var node := object_container.get_node_or_null(action.node)
			if node:
				node.transform = action.before


func _on_redo():
	var action := undo_manager.redo()
	if action.is_empty():
		return
	match action.type:
		"transform":
			var node := object_container.get_node_or_null(action.node)
			if node:
				node.transform = action.after


# ── Dialogs ─────────────────────────────────────────────────────

func _on_back():
	_on_close()

func _on_close():
	lab_closed.emit()
	if _all_assignments_completed:
		var level_def := ResourceLoader.load("res://data/levels/3d_design_lab.tres") as LevelDefinition
		if level_def:
			LevelProgression.complete_level(level_def)
	var return_scene := LevelProgression.get_resume_scene()
	if return_scene.is_empty():
		return_scene = fallback_scene
	else:
		var spawn_data = LevelProgression.get_resume_spawn()
		LevelProgression.save_spawn_position(return_scene, spawn_data.get("player", Vector3.ZERO), spawn_data.get("camera_offset", Vector3.ZERO))
		LevelProgression.clear_resume_state()
	get_tree().change_scene_to_file(return_scene)


func _show_toast(msg: String):
	%Toast/Label.text = msg
	%Toast.visible = true
	await get_tree().create_timer(2.0).timeout
	%Toast.visible = false


func _hide_all_dialogs():
	%SaveDialog.visible = false
	%LoadDialog.visible = false
	%CompletionPanel.visible = false
	%Toast.visible = false
