class_name ModelingLab
extends CanvasLayer

signal lab_closed

@export_file("*.tscn") var fallback_scene := "res://scenes/main_menu.tscn"

enum LabMode { LESSON, CREATIVE_STUDIO }
enum Tool { MOVE, ROTATE, SCALE }

## Which frame the gizmo handles are drawn in, and which frame SCALE acts in.
##
## Global is the default and is the honest one: move and rotate were already
## world-space, and every handle used to be drawn world-aligned. Scale alone wrote
## `node.scale`, which acts along the object's OWN axes — so on a rotated object
## the red X handle pointed along world X while the stretch it produced ran along
## local X. Global makes the drawing tell the truth. Local is offered because a
## local frame is genuinely the more useful one for non-uniform scaling of a
## rotated prop.
enum Orientation { GLOBAL, LOCAL }

const ColorPickerControlScript := preload("res://scripts/digital_art_lab/color_picker_control.gd")

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
var undo_redo: CommandManager
var creative_studio_manager: CreativeStudioManager

# Mode state
var _mode: int = LabMode.LESSON
var _current_tool: int = Tool.MOVE
## See the Orientation enum. LOCAL is the default.
##
## Global scales along world axes, which is Blender's own default and is
## mathematically exact - the world axis you drag grows by exactly the factor,
## no other world axis moves, and anything off-axis skews. That skew is shear,
## and shear is not wanted here: the object should stay a clean box and only its
## dimensions should change. Local does that - it scales the object's own axes,
## so no face ever becomes a parallelogram.
##
## The cost of Local, stated plainly because it is not nothing: on a cube yawed
## 45 degrees, dragging the X handle by 1.5 takes the world-X extent from 1.414
## to 1.768, NOT to 2.121. The stretch lands on the object's own axis, which
## runs diagonally through world space, so no world axis is scaled by the factor
## you typed. Global reaches 2.121 but shears to get there. Neither does both.
##
## This single flag plus one branch is the whole toggle, so Global stays one
## click away in the toolbar and putting it back as the default is a one-line
## change.
var _orientation: int = Orientation.LOCAL
var _current_assignment: AssignmentData = null
var _primitive_locked: Array[bool] = []
var _player_objects: Array[Node3D] = []
var _scores: Array[float] = []
var _all_assignments_completed: bool = false
var _dragging: bool = false
## Which handle was grabbed, in the GIZMO's own frame. Stays local on purpose:
## it identifies *which* of X/Y/Z was grabbed, and that answer is needed in both
## orientations. Under Local the handle is rotated, so this is NOT a world
## direction — see `_drag_axis_world`.
var _drag_axis: Vector3 = Vector3.ZERO
## The same handle expressed in world space, FROZEN when the drag is armed.
## Used only by the motion handler, and frozen deliberately: under Local the
## gizmo's frame follows the object, so recomputing a rotate axis each frame would
## have it chase the object being rotated. Press-time screen maths reads the live
## frame instead — see `_world_drag_axis()`.
var _drag_axis_world: Vector3 = Vector3.ZERO
var _drag_uniform: bool = true
var _drag_start_mouse: Vector2 = Vector2.ZERO
var _drag_axis_screen: Vector2 = Vector2.RIGHT
var _drag_axis_perp: Vector2 = Vector2.UP

# Box-select / body-drag state
var _box_dragging: bool = false
var _box_drag_start: Vector2 = Vector2.ZERO
var _body_dragging: bool = false
var _body_plane_point: Vector3 = Vector3.ZERO
var _body_drag_start: Vector3 = Vector3.ZERO
# Body-drag is ARMED on press over a selected member and only BEGINS once the
# cursor moves past BODY_DRAG_START_PX. A plain click (no movement) stays
# armed through release and does nothing — so the very next click within the
# double-click window still matches _last_click_node (no rebuild happened) and
# drills down from a selected group to a single member.
var _body_drag_armed: bool = false
var _body_drag_origin: Vector2 = Vector2.ZERO
const BODY_DRAG_START_PX := 4.0

# Double-click detection
var _last_click_time: float = 0.0
var _last_click_node: MeshInstance3D = null
const DOUBLE_CLICK_THRESHOLD := 0.3

# Workspace references
var workspace: Node3D
var object_container: Node3D
var ghost_container: Node3D
var gizmo: Gizmo3D
var camera_controller: CameraController
var grid_plane: MeshInstance3D
var _selection_overlay: Control

# Called by main menu
static func launch():
	SceneTransition.change_scene("res://scenes/modeling_lab/modeling_lab.tscn")


func _ready():
	workspace = $SubViewportContainer/SubViewport/Workspace
	object_container = workspace.get_node("ObjectContainer")
	ghost_container = workspace.get_node("GhostContainer")
	gizmo = workspace.get_node("Gizmo3D")
	camera_controller = workspace.get_node("CameraController")
	grid_plane = workspace.get_node("GridPlane")
	_selection_overlay = $SubViewportContainer/SubViewport/SelectionOverlay

	snap_settings = SnapSettings.new()
	grid_plane.visible = snap_settings.grid_visible
	spawner = PrimitiveSpawner.new()
	selection_manager = SelectionManager.new(object_container)
	hierarchy_manager = HierarchyManager.new(object_container)
	undo_redo = CommandManager.new()
	undo_redo.selection_manager = selection_manager
	material_manager = MaterialManager.new()
	transform_manager = TransformManager.new(selection_manager, snap_settings, hierarchy_manager, undo_redo, spawner, material_manager)
	accuracy_manager = AccuracyManager.new()
	scoring_manager = ScoringManager.new()
	assignment_manager = AssignmentManager.new()
	save_manager = SaveManager.new()
	portfolio_manager = PortfolioManager3D.new(save_manager)
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
		view_orbit_gizmo.set_camera(camera_controller.camera)
		# Wire the transform gizmo's camera too — Gizmo3D keeps handles
		# constant-on-screen by scaling with camera distance (NATIVE_DISTANCE
		# etc. in gizmo_3d.gd). Without set_camera the gizmo stays fixed
		# world-size and its 0.04-radius shafts go sub-pixel as you zoom out to
		# fit the scene ("slowly disappears while the grid stays crisp and
		# reads as overlapping it").
		gizmo.set_camera(camera_controller.camera)



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
	%UndoBtn.pressed.connect(_on_undo)
	%RedoBtn.pressed.connect(_on_redo)

	# Toggles
	%GridToggle.toggled.connect(_on_grid_toggled)
	%SnapToggle.toggled.connect(_on_snap_toggled)
	%SnapSize.value_changed.connect(_on_snap_size_changed)
	%LocalToggle.toggled.connect(_on_local_toggled)
	# The toggle is the second way in (KEY_X is the first), so start it agreeing
	# with `_orientation` rather than trusting the scene's default to match.
	_sync_orientation_toggle()

	# Selection
	selection_manager.selected_changed.connect(_on_selection_changed)

	# SubViewport input
	%SubViewportContainer.mouse_filter = Control.MOUSE_FILTER_STOP
	%SubViewportContainer.gui_input.connect(_on_viewport_gui_input)

	# Material panel
	%ColorSwatch.gui_input.connect(_on_color_swatch_clicked)
	%MetallicSlider.value_changed.connect(_on_metallic_changed)
	%RoughnessSlider.value_changed.connect(_on_roughness_changed)
	%MetallicSlider.drag_started.connect(_on_material_drag_started)
	%MetallicSlider.drag_ended.connect(func(_vc: bool): _on_material_drag_ended(Color()))
	%RoughnessSlider.drag_started.connect(_on_material_drag_started)
	%RoughnessSlider.drag_ended.connect(func(_vc: bool): _on_material_drag_ended(Color()))
	for btn in [%PlasticBtn, %MetalBtn, %WoodBtn, %StoneBtn, %GlassBtn]:
		btn.pressed.connect(_on_preset_pressed.bind(btn.text.to_lower()))
	_build_base_color_wheel()
	_base_color_wheel.drag_started.connect(_on_material_drag_started)
	_base_color_wheel.drag_ended.connect(_on_material_drag_ended)

	# Hierarchy
	%RenameBtn.pressed.connect(_on_hierarchy_rename)
	%ParentBtn.pressed.connect(_on_hierarchy_parent)
	%UnparentBtn.pressed.connect(_on_hierarchy_unparent)
	%Tree.item_selected.connect(_on_hierarchy_selected)
	# SELECT_MULTI emits multi_selected (3 args) instead of item_selected on
	# click. A bound method with fewer args than the signal is NOT called by
	# Godot ("Method expected 0 argument(s), but called with 3"), so wrap the
	# handler in an arg-matching lambda.
	%Tree.multi_selected.connect(func(_it, _col, _sel): _on_hierarchy_selected())
	%Tree.item_edited.connect(_on_tree_item_edited)

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
	# The World set. Wired to the same handlers pattern as the Local set, but each
	# handler operates in world space; see _commit_inspector_change for why they
	# share one undo path.
	%WPosX.value_changed.connect(_on_inspector_world_pos_changed.bind("x"))
	%WPosY.value_changed.connect(_on_inspector_world_pos_changed.bind("y"))
	%WPosZ.value_changed.connect(_on_inspector_world_pos_changed.bind("z"))
	%WRotX.value_changed.connect(_on_inspector_world_rot_changed.bind("x"))
	%WRotY.value_changed.connect(_on_inspector_world_rot_changed.bind("y"))
	%WRotZ.value_changed.connect(_on_inspector_world_rot_changed.bind("z"))
	%WScaleX.value_changed.connect(_on_inspector_world_scale_changed.bind("x"))
	%WScaleY.value_changed.connect(_on_inspector_world_scale_changed.bind("y"))
	%WScaleZ.value_changed.connect(_on_inspector_world_scale_changed.bind("z"))

	# Portfolio
	portfolio_manager.portfolio_changed.connect(_on_portfolio_changed)
	portfolio_manager.model_opened.connect(_on_model_opened)

	# Spawn menu
	%SpawnBtn.get_popup().id_pressed.connect(_on_spawn_selected)

	# Save / Load toolbar buttons (Creative Studio only)
	%SaveBtn.pressed.connect(_on_save)
	%LoadBtn.pressed.connect(_on_load)

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
	# Free EVERY non-ghost child below the container: groups (Node3D) AND
	# their members. Ghost guides live in the separate GhostContainer, so this
	# blanket wipe never touches lesson guides.
	for child in object_container.get_children():
		if not child.is_in_group("ghost_guides"):
			child.free()
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
	# Hard invariant: the gizmo may ONLY be visible while something is
	# actually selected. The snapshot undo system rebuilds node instances on
	# every apply, which can silently invalidate the cached selection (and thus
	# leave a pivot-mode gizmo floating over an empty scene). Re-check every
	# frame and tear down if the selection really is gone. selected_nodes()
	# stale-clears first, so this is the single source of truth for "is any
	# selectable mesh alive and picked".
	if gizmo and selection_manager:
		if gizmo.visible and selection_manager.selected_nodes().is_empty() \
				and not selection_manager.get_selected():
			gizmo.set_target(null)
			gizmo.visible = false


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
	%SaveBtn.visible = true
	%LoadBtn.visible = true
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
		var base := PrimitiveSpawner.base_name_for_type(id)
		var unique_name := HierarchyManager.allocate_name(object_container, base)
		var data := {
			name = unique_name,
			display_name = unique_name,
			type = id,
			position = Vector3(0, 0.5, 0),
			rotation_degrees = Vector3.ZERO,
			scale = Vector3.ONE,
			material_albedo = Color.WHITE,
			material_metallic = 0.0,
			material_roughness = 1.0,
		}
		var mi := undo_redo.execute_command(
			CommandFactory.spawn(data, object_container, spawner, material_manager, hierarchy_manager)
		)
		if mi:
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


func gizmo_orientation() -> int:
	return _orientation


func set_gizmo_orientation(orientation: int) -> void:
	_orientation = clampi(orientation, Orientation.GLOBAL, Orientation.LOCAL)
	_apply_gizmo_orientation()
	# Synced from here rather than by each caller, so the toolbar checkbox and the
	# bottom-bar button cannot drift from each other or from the real frame.
	_sync_orientation_toggle()


func toggle_gizmo_orientation() -> void:
	set_gizmo_orientation(
			Orientation.LOCAL if _orientation == Orientation.GLOBAL
			else Orientation.GLOBAL)


## The frame the handles should be drawn in.
##
## Global is identity. Local is the rotation of the first-selected node —
## `SelectionManager.select_multi` already ends with `_selected = fresh[0]`, so
## "first-selected" is the existing selection order and needs no extra state.
##
## `global_basis` rather than `basis` because the result feeds
## `Gizmo3D.axis_to_world`, which returns a WORLD direction; taking the rotation
## in the object's parent frame would be wrong the moment a parent ever carries a
## transform.
func _orientation_basis() -> Basis:
	if _orientation == Orientation.LOCAL:
		var node := selection_manager.get_selected()
		if node and is_instance_valid(node):
			return node.global_basis.orthonormalized()
	return Basis.IDENTITY


## Pushes the current orientation onto the gizmo. Called on selection change and
## while dragging, because under Local the handles must follow the object as it
## rotates — otherwise the ring you grabbed would slide off the axis you are
## turning.
func _apply_gizmo_orientation() -> void:
	if gizmo:
		gizmo.set_orientation(_orientation_basis())


## Reflects `_orientation` in the toolbar toggle.
##
## `KEY_X` changes the mode without going through the button, so without this the
## button would show the opposite state from what the gizmo is actually doing.
## `set_value_no_signal` because the button's own signal is what calls back into
## `set_gizmo_orientation` — setting the value normally would recurse.
## The one place the orientation controls are written.
##
## There are two of them and they are the SAME setting, not two: a Local checkbox
## in the toolbar and a World/Object button in the bottom bar. Both are written
## from `_orientation` here, and `set_gizmo_orientation` calls this, so whichever
## one the user pressed, the state and both labels follow from a single value.
##
## `set_pressed_no_signal` because the checkbox's own signal is what calls back
## into `set_gizmo_orientation` — writing the value normally would recurse.
func _sync_orientation_toggle() -> void:
	var local := _orientation == Orientation.LOCAL
	var button := get_node_or_null("%LocalToggle") as BaseButton
	if button:
		button.set_pressed_no_signal(local)
	# Named "Object"/"World" rather than "Local"/"Global": the bottom bar sits
	# beside the transform readout, where the question is "whose axes am I
	# dragging?" rather than Blender's vocabulary. The toolbar checkbox keeps
	# "Local" because that is the term its tooltip explains.
	var mode := get_node_or_null("%ModeBtn") as Button
	if mode:
		mode.text = "Object" if local else "World"


## The toolbar's Local toggle. Unchecked is Global (handles along world axes);
## checked is Local, where the handles follow the object's own axes.
func _on_local_toggled(pressed: bool) -> void:
	set_gizmo_orientation(
			Orientation.LOCAL if pressed else Orientation.GLOBAL)


func _on_selection_changed(node: MeshInstance3D):
	if node:
		if selection_manager.selected_count() > 1:
			# Multi-select: the gizmo pivots to the group centroid (it stops
			# tracking any single member) so Move/Rotate/Scale act on the set.
			gizmo.set_pivot(selection_manager.get_centroid())
		else:
			gizmo.set_target(node)
		gizmo.visible = (_mode == LabMode.CREATIVE_STUDIO) or (_mode == LabMode.LESSON)
	else:
		# REGRESSION: deselect MUST also clear the gizmo's target, not just hide
		# it. gizmo_3d.gd:_process runs `visible = _target != null` every frame,
		# so a stale `_target` here makes the gizmo resurrect itself the next
		# frame — it "remains" floating over the empty scene when nothing is
		# selected (only visible, not <null>, is what actually keeps it hidden).
		gizmo.set_target(null)
		gizmo.visible = false
	# Local orientation is derived from the selected node, so it has to be
	# recomputed whenever the selection changes — otherwise switching to Local
	# while a rotated object is selected would draw world-aligned handles.
	_apply_gizmo_orientation()
	# The material panel must reflect the newly selected object immediately
	# (its base color, metallic, roughness) — not only after the first
	# transform drag. Deselect resets the panel to defaults.
	_update_inspector(node)
	_sync_tree_selection()


# ── Viewport Input ──────────────────────────────────────────────

## Minimum screen-space length, in pixels, before an axis' projected direction
## counts as well-defined. Below this the axis is treated as parallel to the
## view ray. 4px matches the thinnest ring: at the default view a 1-unit axis
## measures 45-90px, so 4px is roughly 15deg off-axis.
const AXIS_SCREEN_EPS := 4.0

## Builds `_drag_axis_screen` / `_drag_axis_perp` for the handle that was just
## grabbed. Move and scale read the first; rotate reads the second.
##
## `hit_3d` is the 3D point the gizmo raycast struck, used by rotate only (see
## `_compute_rotate_tangent`). Callers that have no pick result may omit it.
##
## MOVE / SCALE. The screen direction of a world axis is the pixel delta between
## the gizmo centre and the centre displaced along that axis. That delta
## collapses to (0, 0) when the axis points at, or away from, the camera, because
## `unproject_position` returns the SAME pixel for both points. `.normalized()`
## leaves the zero vector as zero, so every `moved.dot(...)` is exactly 0 and the
## handle is grabbed, dragged, and does nothing at all.
##
## This is reachable from ordinary play, which is why it looked arbitrary:
## ViewOrbitGizmo's axis buttons call `CameraController.set_view_axis()`, which
## aligns the camera to the axis EXACTLY, and hand-orbiting lands in the same
## place. Measured at every `set_view_axis` angle: screen length 0.0000px,
## rotate delta 0.000, move delta 0.000. From the default tilted view the same
## three axes measure 45-90px and respond normally - the difference between
## "sometimes dead" and "always fine".
##
## ROTATE is NOT derived from the projected axis. Doing that was a second,
## independent bug: it reverses whenever the ring's axis points at the camera,
## and misbehaves again when the ring is edge-on. See `_compute_rotate_tangent`.
func _compute_drag_screen_basis(grab_pos: Vector2,
		hit_3d: Vector3 = Vector3.INF) -> void:
	var cam := camera_controller.camera
	# Projected from the gizmo position (the group centroid when multi-selected),
	# not the primary node.
	var origin := cam.unproject_position(gizmo.global_position)
	# Read from the gizmo rather than reusing `_drag_axis`: this projects a real
	# world point, so it needs a world direction. Under Local the handle has
	# genuinely rotated, so adding the local axis to a world position would
	# project the wrong tip and the drag would follow a direction the handle is
	# not pointing along.
	var tip := cam.unproject_position(gizmo.global_position + _world_drag_axis())
	var delta := tip - origin

	if delta.length() > AXIS_SCREEN_EPS:
		_drag_axis_screen = delta.normalized()
	elif (grab_pos - origin).length() > AXIS_SCREEN_EPS:
		# Degenerate: the axis is parallel to the view ray, so there is no
		# projected axis to follow. Drag radially - the only motion left that
		# maps to motion along the axis.
		_drag_axis_screen = (grab_pos - origin).normalized()
	else:
		# Grabbed within a few pixels of the gizmo centre, so there is no usable
		# radius either. Screen-up keeps the handle responsive rather than
		# silently doing nothing, which is the failure being fixed.
		_drag_axis_screen = Vector2.UP

	_drag_axis_perp = _compute_rotate_tangent(grab_pos, origin, hit_3d)

## The screen-space direction the rotate ring travels under the cursor, at the
## point the cursor grabbed.
##
## Correctness criterion, and the one the regression test asserts: the ring point
## under the cursor must FOLLOW the cursor. Rotating the wrong way makes it move
## against the drag instead. Deriving the tangent from the projected axis broke
## that criterion — measured, 36 of 48 cases reversed whenever the ring's axis
## pointed at the camera, and 16 of 48 when it was edge-on. That is the report
## "in positive x y z the rotation is reverse in negative it rotates fine":
## ViewOrbitGizmo's `+X`/`+Y`/`+Z` buttons each put the camera on the positive
## side of that axis, so the ring faced the user and reversed, while the negative
## buttons put the camera on the far side and happened to come out right.
##
## A ring point at angle t sits at `centre + u*cos(t) + v*sin(t)` (v = n x u), so
## in screen space it traces `C + U*cos(t) + V*sin(t)` and the tangent is
## `-U*sin(t) + V*cos(t)`. Locating t is the only hard part.
##
## `hit_3d` is the point the gizmo's own raycast actually struck, and it answers
## t exactly, with no degeneracy to guard: `t` is just the angle of a real 3D
## vector in the same (u, v) frame that U and V were projected from. Measured at
## every view angle, 1728 cases: zero reversals.
##
## Two screen-space estimates were tried and both measured worse, which is why
## this uses the raycast instead of anything derivable from pixels alone:
##   - the 2x2 screen solve, which degenerates at edge-on because `U x V` is the
##     area of the projected ellipse and vanishes there;
##   - the arcball angle in a ring-aligned basis, which is well conditioned at
##     edge-on but lives in a CAMERA-dependent frame, while `u`/`v` here are an
##     arbitrary fixed choice — so the offset between the two frames flips sign
##     as the camera moves. Measured: whole view/handle pairs reversed 48 of 72.
##     Intersecting the ray with the ring's plane fails too, because at edge-on
##     the camera lies IN that plane and `ray . n` is 0 for every ray.
## World direction of the grabbed handle, read from the gizmo at CALL time.
##
## Deliberately distinct from `_drag_axis_world`, which is frozen at press. Under
## Local the gizmo's frame follows the object as it rotates, so a rotate drag that
## recomputed its axis each frame would have the axis chase the very object it is
## turning. The screen basis and the ring tangent are press-time quantities about
## what the user is looking at, so they read the live frame; applying the
## transform reads the frozen one.
func _world_drag_axis() -> Vector3:
	return gizmo.axis_to_world(_drag_axis)

func _compute_rotate_tangent(grab_pos: Vector2, origin: Vector2,
		hit_3d: Vector3) -> Vector2:
	var cam := camera_controller.camera
	# World axis, for the same reason as `_compute_drag_screen_basis`: the ring
	# this derives a tangent for is a real world-space ring, and under Local it
	# sits on the object's own axes rather than the world ones.
	var n := _world_drag_axis().normalized()
	if n.length() < 0.5:
		return Vector2.UP

	# An in-plane basis. `u` must not be parallel to `n`, or `v` collapses to zero
	# and the whole derivation is garbage.
	var seed := Vector3.UP if absf(n.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var u := seed.cross(n).normalized()
	var v := n.cross(u).normalized()

	var U := cam.unproject_position(gizmo.global_position + u) - origin
	var V := cam.unproject_position(gizmo.global_position + v) - origin

	var t: float
	if hit_3d.is_finite():
		var rel := hit_3d - gizmo.global_position
		t = atan2(rel.dot(v), rel.dot(u))
	else:
		# No raycast hit to work from (only reachable off the ring, or from a
		# caller that did not pass one). Fall back to the screen estimate.
		t = _theta_from_screen(grab_pos, origin, U, V)

	var tangent := -U * sin(t) + V * cos(t)
	if tangent.length() < 0.0001:
		# The cursor is at the one place on a foreshortened ring where the screen
		# tangent is genuinely zero. Fall back to the screen radius, which is at
		# least guaranteed non-degenerate for any off-centre grab.
		var radial := grab_pos - origin
		if radial.length() > AXIS_SCREEN_EPS:
			return Vector2(-radial.y, radial.x)
		return Vector2.UP
	return tangent.normalized()

## Locate the grabbed ring angle from the cursor's screen position, using the
## projected in-plane basis. `U x V` is the signed area of the projected ellipse,
## so it goes to zero exactly when the ring is edge-on — which is why this is only
## a fallback for when no 3D hit is available.
func _theta_from_screen(grab_pos: Vector2, origin: Vector2, U: Vector2, V: Vector2) -> float:
	var w := grab_pos - origin
	var det := U.x * V.y - U.y * V.x
	if absf(det) < 0.0001:
		return 0.0
	var cos_t := (w.x * V.y - w.y * V.x) / det
	var sin_t := (U.x * w.y - U.y * w.x) / det
	# The cursor may not sit exactly on the ellipse (it need not — the ring is a
	# tube), so the raw solution can exceed unit length. Renormalise rather than
	# trusting it, which keeps t on the unit circle.
	var l := Vector2(cos_t, sin_t).length()
	if l < 0.0001:
		return 0.0
	return atan2(sin_t / l, cos_t / l)

func _on_viewport_gui_input(event: InputEvent):
	var sv: SubViewport = %SubViewport
	var mouse_pos: Vector2 = sv.get_mouse_position()

	# Camera gets first chance
	if camera_controller.handle_input(event):
		# Camera consumed the interaction (orbit/zoom). A previously armed
		# body-drag press (if any) is now stale — no release will clear it.
		body_drag_armed_discard()
		_update_zoom_display()
		get_viewport().set_input_as_handled()
		return

	# Selection on left click
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# Double-click detection: must run BEFORE gizmo/body-drag checks
		# so the second click isn't consumed by transform handles.
		var now := Time.get_ticks_msec() / 1000.0
		var hit_node := selection_manager.pick_object(mouse_pos, camera_controller.camera)
		var is_double_click := (hit_node != null \
			and is_instance_valid(hit_node) \
			and _last_click_node == hit_node \
			and (now - _last_click_time) < DOUBLE_CLICK_THRESHOLD)
		_last_click_time = now
		_last_click_node = hit_node
		if is_double_click:
			# Double-click: select only the hit node. When the full group is
			# selected this drills down from group -> member (the single-click
			# rule re-expands to the whole group again on the next click).
			selection_manager.select(hit_node)
			get_viewport().set_input_as_handled()
			return

		# Start transform drag if a gizmo handle was grabbed
		if selection_manager.get_selected():
			var pick := gizmo.pick(mouse_pos, camera_controller.camera)
			if pick.get("picked", false):
				_dragging = true
				# Two axes, deliberately. `_drag_axis` stays in the gizmo's own
				# frame because it answers "which handle was grabbed" — a world
				# axis cannot answer that under Local, where a 45deg-yawed local
				# X handle has a world direction with two non-zero components and
				# would scale two axes at once. `_drag_axis_world` is the same
				# handle in world space, for everything that projects a point or
				# moves the object along it.
				_drag_axis = pick.get("axis", Vector3.ZERO)
				_drag_axis_world = gizmo.axis_to_world(_drag_axis)
				_drag_uniform = pick.get("uniform", true)
				_drag_start_mouse = mouse_pos
				if _drag_uniform:
					_drag_axis_screen = Vector2.RIGHT
					_drag_axis_perp = Vector2.UP
				else:
					_compute_drag_screen_basis(mouse_pos,
							pick.get("position", Vector3.INF))
				match _current_tool:
					Tool.MOVE: transform_manager.begin_move(_drag_axis_world)
					Tool.ROTATE: transform_manager.begin_rotate(_drag_axis_world)
					Tool.SCALE: transform_manager.begin_scale(_drag_uniform)
				get_viewport().set_input_as_handled()
				return

		# Body-drag: clicking an already-selected member with >1 selected and
		# the Move tool active drags the whole group along the camera plane
		# WITHOUT collapsing the selection set. Arm it on press; it only BEGINS
		# once the cursor actually moves (see motion branch), so a plain click —
		# including the first click of a double-click that should drill INTO the
		# selected group — never triggers a transform/rebuild.
		var hit := selection_manager.pick_object(mouse_pos, camera_controller.camera)
		if hit \
				and selection_manager.selected_count() > 1 \
				and selection_manager.is_selected(hit) \
				and _current_tool == Tool.MOVE:
			_body_drag_armed = true
			_body_drag_origin = mouse_pos
			get_viewport().set_input_as_handled()
			return

		# Single selection / collapse
		var selected := selection_manager.select_from_click(mouse_pos, camera_controller.camera)
		if selected:
			get_viewport().set_input_as_handled()
			return

		# Nothing under the cursor → start a rubber-band box selection.
		_box_drag_start = mouse_pos
		_box_dragging = true
		if _selection_overlay:
			_selection_overlay.show_box(mouse_pos, mouse_pos)
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _dragging:
			_dragging = false
			match _current_tool:
				Tool.MOVE: transform_manager.end_move()
				Tool.ROTATE: transform_manager.end_rotate()
				Tool.SCALE: transform_manager.end_scale()
		if _body_dragging:
			_body_dragging = false
			transform_manager.end_move()
		elif _body_drag_armed:
			# A plain click on a selected member: no drag ever started, so do
			# NOT call end_move() (that would execute a transform + rebuild the
			# nodes, breaking the following double-click's node-identity match).
			body_drag_armed_discard()
		if _box_dragging:
			_box_dragging = false
			_apply_selection_box(_box_drag_start, mouse_pos)
			if _selection_overlay:
				_selection_overlay.hide_box()

	if event is InputEventMouseMotion:
		if _dragging:
			var moved: Vector2 = mouse_pos - _drag_start_mouse
			var dist: float = moved.dot(_drag_axis_screen)
			match _current_tool:
				Tool.MOVE:
					transform_manager.apply_move(_drag_axis_world, dist * 0.02)
				Tool.ROTATE:
					var tangential: float = moved.dot(_drag_axis_perp)
					# 0.001 rad/px needed ~5,600px of drag for a full turn, so a
					# rotation felt almost frozen even once the snap was fixed.
					# 0.004 puts a 90deg turn at ~390px, which tracks a mouse or
					# trackpad naturally. TransformManager accumulates this per
					# frame and snaps the TOTAL, so raising it does not fight the
					# snap - it only makes the detents arrive sooner.
					transform_manager.apply_rotate(_drag_axis_world, tangential * 0.004)
				Tool.SCALE:
					# `_drag_axis` (local) picks the component; `world_frame` picks
					# the frame. Passing the world axis instead would scale two
					# axes at once for any object yawed off 0/90deg.
					var _world := _orientation == Orientation.GLOBAL
					var _d := _scale_delta(mouse_pos, _drag_start_mouse,
							_drag_axis_screen)
					transform_manager.apply_scale(_drag_axis, _d, _drag_uniform,
							_world)
			_update_inspector(selection_manager.get_selected())
		elif _body_drag_armed:
			# The press armed a potential body-drag. Promote it to a real drag
			# only once the cursor actually moves; otherwise the release below
			# simply clears the arm (a click, not a drag).
			if mouse_pos.distance_to(_body_drag_origin) >= BODY_DRAG_START_PX:
				_begin_body_drag(mouse_pos)
		elif _body_dragging:
			_apply_body_drag(mouse_pos)
		elif _box_dragging:
			if _selection_overlay:
				_selection_overlay.show_box(_box_drag_start, mouse_pos)

	# Keyboard shortcuts
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_W: %MoveBtn.button_pressed = true; _on_tool_selected(Tool.MOVE)
			KEY_E: %RotateBtn.button_pressed = true; _on_tool_selected(Tool.ROTATE)
			KEY_R: %ScaleBtn.button_pressed = true; _on_tool_selected(Tool.SCALE)
			KEY_D: _on_duplicate()
			KEY_DELETE: _on_delete()
			# Global/Local gizmo frame. X is unclaimed: the only KEY_G in the tree
			# is the digital-art lab's fill tool, and no InputMap action takes X.
			# No explicit sync: `toggle_gizmo_orientation` reaches
			# `set_gizmo_orientation`, which writes both controls.
			KEY_X:
				toggle_gizmo_orientation()
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


func _apply_selection_box(from: Vector2, to: Vector2):
	# Rubber-band selection in viewport coordinates. An object is inside the
	# box when its projected center lands in the rect. Walks the FULL hierarchy
	# (including grouped members) so a group can be box-selected just like a
	# standalone mesh — matching the physics click path.
	var rect := Rect2(from, to - from).abs()
	var hits: Array[MeshInstance3D] = []
	for child in selection_manager.collect_selectable_meshes():
		var p: Vector2 = camera_controller.camera.unproject_position(child.global_position)
		if rect.has_point(p):
			hits.append(child)
	if hits.is_empty():
		selection_manager.deselect_all()
	else:
		selection_manager.select_multi(hits)


func _begin_body_drag(mouse_pos: Vector2):
	# Drag the whole group on a plane through the centroid facing the camera.
	body_drag_armed_discard()
	_body_dragging = true
	_body_plane_point = selection_manager.get_centroid()
	_body_drag_start = _ray_plane_hit(mouse_pos, _body_plane_point)
	transform_manager.begin_move(Vector3.ZERO)


## Drops a pending body-drag arm (press that never became a drag). Called from
## the release path (a plain click — zero-move — must not fire end_move and
## rebuild the meshes, which would break a following double-click drill-down),
## from camera-input consumption, and when a drag proper begins.
func body_drag_armed_discard() -> void:
	_body_drag_armed = false


func _ray_plane_hit(screen_pos: Vector2, plane_point: Vector3) -> Vector3:
	var cam: Camera3D = camera_controller.camera
	var from: Vector3 = cam.project_ray_origin(screen_pos)
	var dir: Vector3 = cam.project_ray_normal(screen_pos)
	var n := -cam.global_transform.basis.z
	var denom := dir.dot(n)
	if absf(denom) < 1e-6:
		return plane_point
	var t := (plane_point - from).dot(n) / denom
	return from + dir * t


func _apply_body_drag(mouse_pos: Vector2):
	if not _body_dragging:
		return
	var plane_hit := _ray_plane_hit(mouse_pos, _body_plane_point)
	var delta := plane_hit - _body_drag_start
	transform_manager.apply_move_delta(delta)
	if selection_manager.selected_count() > 1:
		gizmo.set_pivot(selection_manager.get_centroid())


func _update_gizmo_drag():
	if selection_manager.selected_count() > 1:
		gizmo.set_pivot(selection_manager.get_centroid())
	elif selection_manager.get_selected():
		gizmo.global_position = selection_manager.get_selected().global_position
	# Under Local the handles ride the object's rotation, so a rotate drag has to
	# keep feeding the gizmo its new frame or the ring slides off the axis being
	# turned. Cheap: one orthonormalise per frame on an already-loaded node.
	_apply_gizmo_orientation()


## How long each of the object's axes actually is, in world units.
##
## The columns of a basis ARE its axes, so their lengths are the object's real
## scale — and this is exactly what `node.scale` already reports. Measured, not
## assumed: for `Basis.from_scale(1.5,1,1) * Basis.from_euler(0,45,0)` (a sheared
## basis), `get_scale()` and the column lengths agree to the last digit on all
## three axes. So the inspector's readout was never wrong and switching it to
## this helper changes no displayed value.
##
## It is here because the WRITE side needs the quantity, and read and write have
## to agree. `node.scale` is fine to READ and useless to WRITE BACK: three lengths
## cannot reconstruct a sheared basis, so routing the write through it is what
## flattened the shear. One helper, both halves, no chance of them drifting apart.
func _effective_axis_lengths(basis: Basis) -> Vector3:
	return Vector3(basis[0].length(), basis[1].length(), basis[2].length())


## How much each axis of the FRAME this basis lives in is scaled: the lengths of
## the basis's ROWS.
##
## A basis's COLUMNS are the object's own axes, which is why their lengths are
## `get_scale()` and what the Local Scale row shows. Row lengths answer the
## different question "how much is this frame's X scaled by". Measured on a cube
## rotated 37 degrees with scale (2,3,4): columns (2.000, 3.000, 4.000), rows
## (2.889, 3.000, 3.414) - the two genuinely disagree, which is the whole reason
## the panel carries two scale rows.
##
## Rows are also the right choice because they make the read/write pair exactly
## invertible: scaling row i by f multiplies that row's length by f and touches no
## other row. See _on_inspector_world_scale_changed.
func _row_lengths(basis: Basis) -> Vector3:
	return Vector3(
			Vector3(basis[0][0], basis[1][0], basis[2][0]).length(),
			Vector3(basis[0][1], basis[1][1], basis[2][1]).length(),
			Vector3(basis[0][2], basis[1][2], basis[2][2]).length())


## The basis's rotation, in degrees.
##
## Deliberately NOT `Basis.get_euler()`. That is only defined on an ORTHONORMAL
## basis, and this panel hands it bases carrying non-uniform scale all the time.
## Measured: a rotation of (20, 37, -11) with scale (2, 3, 4) came back as
## **(90.00, 35.52, 0.00)** - a different orientation, not a rounding difference.
## `ShearWarning` disclosed shear but nothing disclosed this, so the panel was
## reporting a rotation the user never set, and worse, writing one back carried
## the other two axes' drift into the result.
##
## `orthonormalized()` strips scale and leaves R exactly for a clean R*S basis.
## For a SHEARED basis it yields the nearest orthonormal frame, which is an
## approximation - the same disclosure ShearWarning already makes.
func _read_rotation_degrees(basis: Basis) -> Vector3:
	# Componentwise rather than `rad_to_deg(v)`: Godot 4.7's rad_to_deg takes a
	# float, not a Vector3.
	var e := basis.orthonormalized().get_euler()
	return Vector3(rad_to_deg(e.x), rad_to_deg(e.y), rad_to_deg(e.z))


## R*S in the true TRS order, so it decomposes cleanly - and this is also what
## makes it the shear-removal write. Rebuilding from an euler plus a vector of
## axis lengths cannot preserve skew, so the first rotation after an object is
## sheared flattens it, and its volume lands on the product of those lengths
## (the Hadamard gap: that product exceeds |det| whenever there is shear, which
## is why the object grows on that first edit and holds afterwards).
##
## Restored by user decision - see docs/audit-2026-10-05.md section 5q. 5p's
## `_rotation_delta` was the fix this deliberately reverts.
##
## Order matters: `Basis.from_scale(s)` PRE-multiplies, so the scale must go on
## the right.
func _basis_from_rotation_and_scale(rot_deg: Vector3, axis_lengths: Vector3) -> Basis:
	return Basis.from_euler(Vector3(
			deg_to_rad(rot_deg.x), deg_to_rad(rot_deg.y), deg_to_rad(rot_deg.z))) \
			* Basis.from_scale(axis_lengths)


## Writes a Vector3 into the three SpinBoxes named <prefix>X / Y / Z.
##
## `set_value_no_signal` because these boxes' `value_changed` signal is what calls
## the handlers that refresh the panel - writing the value normally would recurse.
func _set_axis_triplet(prefix: String, v: Vector3) -> void:
	for axis in ["x", "y", "z"]:
		var box := get_node_or_null("%" + prefix + axis.to_upper()) as SpinBox
		if box:
			box.set_value_no_signal(v[axis])


## True when the basis cannot be written as rotation * scale, i.e. it carries
## shear. "The three columns are not mutually orthogonal" is the direct test and
## needs no quaternion round-trip to compare matrices.
##
## The columns are normalised first so the epsilon means the same thing at any
## object size: an absolute dot product scales with the square of the axis
## lengths, so on a 1000-unit object a raw 1e-6 cutoff would classify clean
## R*S geometry as sheared. 1e-5 is ~100x the float32 residue a basis picks up
## round-tripping through `PrimitiveSaveData.basis_rows`.
func _is_sheared(basis: Basis) -> bool:
	const EPS := 1e-5
	var x := basis[0].normalized()
	var y := basis[1].normalized()
	var z := basis[2].normalized()
	return absf(x.dot(y)) > EPS or absf(x.dot(z)) > EPS or absf(y.dot(z)) > EPS


func _update_inspector(node: Node3D):
	if not node:
		%NodeName.text = ""
		_set_axis_triplet("Pos", Vector3.ZERO)
		_set_axis_triplet("Rot", Vector3.ZERO)
		_set_axis_triplet("Scale", Vector3.ONE)
		_set_axis_triplet("WPos", Vector3.ZERO)
		_set_axis_triplet("WRot", Vector3.ZERO)
		_set_axis_triplet("WScale", Vector3.ONE)
		%ColorSwatch.color = Color.WHITE
		if _base_color_wheel:
			_base_color_wheel.set_color(Color.WHITE)
		%MetallicSlider.set_value_no_signal(0.0)
		%RoughnessSlider.set_value_no_signal(0.5)
		%ShearWarning.visible = false
		return
	%NodeName.text = HierarchyManager.display_of(node)
	var gt := node.global_transform
	# ── Local set: the object's own frame ──
	_set_axis_triplet("Pos", node.position)
	_set_axis_triplet("Rot", _read_rotation_degrees(node.basis))
	# Same numbers `node.scale` would give (measured — see the helper), but read
	# through the same helper the write path uses, so the panel cannot report one
	# quantity and apply another.
	_set_axis_triplet("Scale", _effective_axis_lengths(node.basis))
	# ── World set: the same three quantities in world space ──
	# Position and rotation come off the global transform. Scale is the ROW
	# lengths, not the columns the Local row shows: columns are the object's own
	# axes, rows are this frame's axes. See _row_lengths.
	_set_axis_triplet("WPos", gt.origin)
	_set_axis_triplet("WRot", _read_rotation_degrees(gt.basis))
	_set_axis_triplet("WScale", _row_lengths(gt.basis))
	# Both rotation rows run _read_rotation_degrees, which is exact for a clean
	# R*S basis and approximate for a sheared one - the same class of
	# approximation the warning below discloses. Writing a rotation back still
	# flattens the shear to R*S (see _on_inspector_rot_changed); the fields stay
	# editable on purpose.
	%ShearWarning.visible = _is_sheared(node.basis)

	var mat := material_manager.read_from(node as MeshInstance3D)
	%ColorSwatch.color = mat.get("albedo", Color.WHITE)
	if _base_color_wheel:
		_base_color_wheel.set_color(%ColorSwatch.color)
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
	var sel := selection_manager.get_selected()
	if not sel:
		return
	var action: ModelingAction
	# Full-group selection duplicates the WHOLE group (new group node + member
	# copies) instead of just the primary mesh; anything else keeps the
	# classic single-node duplicate.
	if selection_manager.is_full_group_selected(sel):
		var group := selection_manager.get_group_parent(sel)
		if group:
			action = CommandFactory.duplicate_group(
				group, object_container, spawner, material_manager, hierarchy_manager)
		else:
			action = CommandFactory.duplicate_node(
				sel, object_container, spawner, material_manager, hierarchy_manager)
	else:
		action = CommandFactory.duplicate_node(
			sel, object_container, spawner, material_manager, hierarchy_manager)
	var copy := undo_redo.execute_command(action)
	# For a plain mesh duplicate, re-point onto the copy. For a group duplicate
	# the primary created node is the group Node3D; duplicate_group's member
	# snapshots flow through _repoint_selection, which selects the member copies.
	if copy and copy is MeshInstance3D:
		selection_manager.select(copy)
	_rebuild_hierarchy_request()


func _on_delete():
	var sel_nodes := selection_manager.selected_nodes()
	if sel_nodes.is_empty():
		return
	var nodes: Array[Node3D] = []
	for n in sel_nodes:
		nodes.append(n)
	# Deselect BEFORE freeing: selected_changed(null) must fire while the node is
	# still valid so the gizmo tears down. Deselecting after execute() loses the
	# signal (the freed _selected is silently nulled) and the gizmo targets a
	# freed node forever.
	selection_manager.deselect_all()
	undo_redo.execute_command(
		CommandFactory.delete(nodes, object_container, spawner, material_manager, hierarchy_manager)
	)
	_rebuild_hierarchy_request()


func _on_reset():
	transform_manager.reset_selected()
	_rebuild_hierarchy_request()
	if selection_manager.get_selected():
		_update_inspector(selection_manager.get_selected())


func _on_center():
	transform_manager.center_selected()
	_rebuild_hierarchy_request()
	if selection_manager.get_selected():
		_update_inspector(selection_manager.get_selected())
	if selection_manager.get_selected():
		_update_inspector(selection_manager.get_selected())


func _on_grid_toggled(val: bool):
	snap_settings.grid_visible = val
	grid_plane.visible = val


func _on_snap_toggled(val: bool):
	snap_settings.snap_enabled = val


func _on_snap_size_changed(val: float):
	snap_settings.position_snap = val


func _on_hint():
	_show_toast("W: Move | E: Rotate | R: Scale | D: Duplicate | Del: Delete | F: Focus")


# ── Material Panel ──────────────────────────────────────────────

var _base_color_wheel: ColorPickerControlScript = null
var _base_color_wheel_expanded := false
var _material_before: Dictionary[String, Variant] = {}
var _material_before_node_id: int = 0


func _build_base_color_wheel():
	_base_color_wheel = ColorPickerControlScript.new()
	_base_color_wheel.name = "BaseColorWheel"
	_base_color_wheel.visible = false
	%ColorSwatch.get_parent().add_child(_base_color_wheel)
	_base_color_wheel.color_changed.connect(_on_base_color_wheel_changed)


func _on_color_swatch_clicked(event: InputEvent):
	if event is InputEventMouseButton and event.pressed:
		_base_color_wheel_expanded = not _base_color_wheel_expanded
		if _base_color_wheel_expanded:
			_base_color_wheel.set_color(%ColorSwatch.color)
		_base_color_wheel.visible = _base_color_wheel_expanded


func _on_base_color_wheel_changed(color: Color):
	%ColorSwatch.color = color
	var sel := selection_manager.get_selected() as MeshInstance3D
	if sel and is_instance_valid(sel):
		material_manager.apply_to(sel, {
			albedo = color,
			metallic = %MetallicSlider.value,
			roughness = %RoughnessSlider.value,
		})


func _on_metallic_changed(val: float):
	var sel := selection_manager.get_selected() as MeshInstance3D
	if sel and is_instance_valid(sel):
		material_manager.apply_to(sel, {
			albedo = %ColorSwatch.color,
			metallic = val,
			roughness = %RoughnessSlider.value,
		})


func _on_roughness_changed(val: float):
	var sel := selection_manager.get_selected() as MeshInstance3D
	if sel and is_instance_valid(sel):
		material_manager.apply_to(sel, {
			albedo = %ColorSwatch.color,
			metallic = %MetallicSlider.value,
			roughness = val,
		})


func _on_preset_pressed(preset_name: String):
	var sel := selection_manager.get_selected() as MeshInstance3D
	if sel and is_instance_valid(sel):
		var props := material_manager.get_preset_props(preset_name)
		var before := material_manager.read_from(sel)
		undo_redo.execute_command(
			CommandFactory.material(sel, before, props,
				object_container, spawner, material_manager, hierarchy_manager)
		)
		%ColorSwatch.color = props.get("albedo", Color.WHITE)
		if _base_color_wheel:
			_base_color_wheel.set_color(%ColorSwatch.color)
		%MetallicSlider.value = props.get("metallic", 0.0)
		%RoughnessSlider.value = props.get("roughness", 0.5)


func _on_material_drag_started():
	var sel := selection_manager.get_selected() as MeshInstance3D
	if sel and is_instance_valid(sel):
		_material_before_node_id = sel.get_instance_id()
		_material_before = material_manager.read_from(sel)


func _on_material_drag_ended(_final_color: Color):
	if _material_before.is_empty():
		return
	var node := instance_from_id(_material_before_node_id) as Node3D
	if node and is_instance_valid(node):
		var after := material_manager.read_from(node)
		if _material_before.albedo != after.albedo \
				or abs(_material_before.metallic - after.metallic) > 0.001 \
				or abs(_material_before.roughness - after.roughness) > 0.001:
			undo_redo.execute_command(
				CommandFactory.material(node, _material_before, after,
					object_container, spawner, material_manager, hierarchy_manager)
			)
	_material_before = {}


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
	var depth_items: Array[TreeItem] = []
	for entry in hierarchy_manager.get_tree_data():
		var parent: TreeItem = root
		if entry.depth > 0 and depth_items.size() >= entry.depth:
			var pi: TreeItem = depth_items[entry.depth - 1]
			if pi != null:
				parent = pi
		var item: TreeItem = tree.create_item(parent)
		item.set_text(0, entry.name)
		item.set_metadata(0, entry.node)
		item.set_custom_color(0, Color(0.9, 0.9, 0.95))
		item.set_editable(0, true)
		depth_items.resize(entry.depth + 1)
		depth_items[entry.depth] = item
	_sync_tree_selection()


func _sync_tree_selection():
	var tree: Tree = %Tree
	var sel_nodes := selection_manager.selected_nodes()
	var single := selection_manager.get_selected()
	if single and sel_nodes.is_empty():
		sel_nodes = [single]
	# Deselect all TreeItems first.
	var cursor: TreeItem = tree.get_next_selected(null)
	while cursor:
		cursor.deselect(0)
		cursor = tree.get_next_selected(cursor)
	# Select TreeItems whose metadata matches the selected nodes.
	var root := tree.get_root()
	if not root:
		return
	var item: TreeItem = root.get_first_child()
	while item:
		var meta: Variant = item.get_metadata(0)
		if is_instance_valid(meta) and meta is MeshInstance3D and meta in sel_nodes:
			item.select(0)
		item = item.get_next()


func _on_hierarchy_selected():
	var item: TreeItem = %Tree.get_selected()
	if not item:
		return
	var nodes: Array[MeshInstance3D] = []
	var cur: TreeItem = %Tree.get_next_selected(null)
	while cur:
		var meta: Variant = cur.get_metadata(0)
		if is_instance_valid(meta):
			if meta is MeshInstance3D:
				nodes.append(meta)
			elif meta is Node3D:
				# Group row: clicking selects every member (multi-select).
				_collect_group_members(meta, nodes)
		cur = %Tree.get_next_selected(cur)
	if nodes.is_empty():
		_rebuild_hierarchy_request()
		return
	if nodes.size() > 1:
		selection_manager.select_multi(nodes)
	else:
		selection_manager.select_node(nodes[0])


func _collect_group_members(node: Node, output: Array[MeshInstance3D]):
	for c in node.get_children():
		if c is MeshInstance3D and not c.is_in_group("ghost_guides"):
			output.append(c)
		elif c.get_child_count() > 0:
			_collect_group_members(c, output)


func _on_hierarchy_rename():
	var item: TreeItem = %Tree.get_selected()
	if not item:
		return
	var meta: Variant = item.get_metadata(0)
	if not is_instance_valid(meta):
		_rebuild_hierarchy_request()
		return
	if %Tree.edit_selected():
		return


func _on_tree_item_edited():
	var item: TreeItem = %Tree.get_edited()
	if item == null:
		item = %Tree.get_selected()
	if not item:
		return
	var meta: Variant = item.get_metadata(0)
	if not is_instance_valid(meta):
		_rebuild_hierarchy_request()
		return
	var node := meta as Node3D
	var new_name := item.get_text(0).strip_edges()
	if new_name.is_empty():
		_rebuild_hierarchy_request()
		return
	var old_name := HierarchyManager.display_of(node)
	if new_name != old_name:
		undo_redo.execute_command(
			CommandFactory.rename(node, old_name, new_name, object_container, spawner, material_manager, hierarchy_manager)
		)
		_rebuild_hierarchy_request()


func _on_hierarchy_parent():
	var members: Array[Node3D] = []
	for n in selection_manager.selected_nodes():
		if is_instance_valid(n):
			members.append(n)
	if members.size() < 2:
		return
	# If all selected members already share the same group parent, skip.
	var shared_parent: Node = members[0].get_parent()
	if shared_parent and shared_parent != object_container and shared_parent is Node3D:
		var all_same := true
		for m in members:
			if m.get_parent() != shared_parent:
				all_same = false
				break
		if all_same:
			return
	# Generate a unique group name. Allocating matters as soon as a second group
	# exists: without it the name "group" is already taken and the new node's
	# display name collides with the existing group's.
	var group_name := HierarchyManager.allocate_name(object_container, "group")
	undo_redo.execute_command(
		CommandFactory.group(group_name, members, object_container, spawner, material_manager, hierarchy_manager)
	)
	_rebuild_hierarchy_request()


func _on_hierarchy_unparent():
	# Blender's "Clear Parent": only the selected objects leave their group, and
	# the group itself stays behind - even once it is empty.
	#
	# This used to call CommandFactory.ungroup() on each former parent, which
	# promotes EVERY member and frees the group. Detaching one object therefore
	# destroyed the whole group and scattered its remaining members to the top
	# level. ungroup() remains the right tool for dissolving a group outright,
	# but nothing here can select a group node - groups are plain Node3D while the
	# selection is Array[MeshInstance3D] - so that path is not reachable from a
	# button and a separate "dissolve" affordance would have to be added.
	var members: Array[Node3D] = []
	for n in selection_manager.selected_nodes():
		if not is_instance_valid(n):
			continue
		var parent := n.get_parent()
		if parent != object_container and parent is Node3D:
			members.append(n as Node3D)

	if members.is_empty():
		return
	undo_redo.execute_command(
		CommandFactory.reparent(members, object_container, object_container,
			spawner, material_manager, hierarchy_manager)
	)
	_rebuild_hierarchy_request()


func _on_hierarchy_selected_in_tree(node_path: NodePath):
	var node := object_container.get_node(node_path) as Node3D
	if node:
		selection_manager.select_node(node)


# ── Inspector ──────────────────────────────────────────────────

func _on_inspector_name_changed(new_name: String):
	var sel := selection_manager.get_selected()
	if sel:
		var old_name := HierarchyManager.display_of(sel)
		if new_name != old_name:
			undo_redo.execute_command(
				CommandFactory.rename(sel, old_name, new_name, object_container, spawner, material_manager, hierarchy_manager)
			)
			_rebuild_hierarchy_request()


## The one place an inspector edit becomes an undoable command.
##
## All twelve rows - six Local, six World - funnel through here, so undo and redo
## behave identically whichever set was edited and whichever frame the edit was
## expressed in. The command stores the whole Transform3D verbatim (the 5h fix),
## so undo restores the exact basis rather than an R*S approximation of it.
##
## `after` is a LOCAL-space transform. `before` is read here rather than passed
## in because the caller's copy is already mutated while the node itself is not:
## `Transform3D` is a value type, so writing to the caller's `after` has not
## touched the scene yet.
func _commit_inspector_change(node: Node3D, after: Transform3D) -> void:
	var before := node.transform
	var action := CommandFactory.transform(
			[object_container.get_path_to(node)], [before], [after],
			object_container, spawner, material_manager, hierarchy_manager)
	undo_redo.execute_command(action)
	selection_manager.reselect_from_ids(action.get_last_created_ids())
	# Repopulate BOTH sets. The world rows are derived from the very transform that
	# just changed, so leaving them alone would show pre-edit numbers next to
	# post-edit ones - the specific way a two-set panel goes wrong.
	var node_after := selection_manager.get_selected() as Node3D
	if node_after:
		_update_inspector(node_after)
		_update_bottom_bar(node_after)


## Maps a world-space point into `node`'s parent space, i.e. the inverse of the
## parent's global transform. Identity when there is no 3D parent, which is the
## only case in which that is the correct answer.
func _parent_global_inverse(node: Node3D) -> Transform3D:
	var parent := node.get_parent_node_3d()
	if parent == null:
		return Transform3D.IDENTITY
	return parent.global_transform.affine_inverse()


func _on_inspector_pos_changed(val: float, axis: String):
	var sel := selection_manager.get_selected()
	if not sel: return
	var after := sel.transform
	var p: Vector3 = sel.position
	match axis:
		"x": p.x = val
		"y": p.y = val
		"z": p.z = val
	after.origin = p
	_commit_inspector_change(sel, after)


## World position. Undo still records the LOCAL transform, which is correct: the
## parent is static, so the before/after locals fully determine the world change.
func _on_inspector_world_pos_changed(val: float, axis: String):
	var sel := selection_manager.get_selected()
	if not sel: return
	var after := sel.transform
	var p: Vector3 = sel.global_position
	match axis:
		"x": p.x = val
		"y": p.y = val
		"z": p.z = val
	after.origin = _parent_global_inverse(sel) * p
	_commit_inspector_change(sel, after)


## Local rotation. REBUILDS the basis as `R * S`, which is the shear-removal
## feature by design: rebuilding from an euler plus a vector of axis lengths
## cannot preserve skew, so the first rotation after an object is sheared
## flattens it. The object grows on that edit - the volume lands on the product
## of its column lengths, an excess that exists exactly when there is shear -
## and holds from then on. See `_basis_from_rotation_and_scale`.
##
## The base rotation comes from `_read_rotation_degrees`, NOT
## `sel.rotation_degrees`. Using the latter would carry the read-side get_euler()
## error into the write: editing X would bake the drift measured on Y and Z into
## the result. `_effective_axis_lengths` is read the same way the Scale row shows
## it, so the panel reports and applies one quantity, and the Scale row does not
## move when you rotate.
func _on_inspector_rot_changed(val: float, axis: String):
	var sel := selection_manager.get_selected()
	if not sel: return
	var after := sel.transform
	var r := _read_rotation_degrees(sel.basis)
	match axis:
		"x": r.x = val
		"y": r.y = val
		"z": r.z = val
	after.basis = _basis_from_rotation_and_scale(r, _effective_axis_lengths(sel.basis))
	_commit_inspector_change(sel, after)


## World rotation. Composed in world space and then brought back into local space,
## so the row means what it says even if an ancestor is ever rotated. With the
## shipped hierarchy that mapping is the identity, but a parent with a rotation
## would otherwise make this row silently wrong.
##
## Rebuilds with COLUMN lengths - `_effective_axis_lengths` - not row lengths.
## Column lengths are idempotent under the rebuild (the column lengths of
## `R * diag(cols)` are `cols` again), so the Local Scale row does not move, the
## skew is removed like the Local row removes it, and the growth happens exactly
## once. The pre-5p row used ROW lengths, which is what made its Local Scale row
## snap to (2, 1, 1) on the first edit and ratchet the volume to 135.7% over
## three - neither is being brought back.
##
## The mapping stays the direct `parent_inv * world`. The old code conjugated
## the rebuilt basis - `parent_inv.basis * M * parent_inv.basis.inverse()` -
## which for an identity parent reduces to M, but for a ROTATED parent multiplies
## by `parent_inv` twice and lands somewhere else entirely. The direct form is
## correct for every parent.
func _on_inspector_world_rot_changed(val: float, axis: String):
	var sel := selection_manager.get_selected()
	if not sel: return
	var world := sel.global_transform
	var r := _read_rotation_degrees(world.basis)
	match axis:
		"x": r.x = val
		"y": r.y = val
		"z": r.z = val
	var parent_inv := _parent_global_inverse(sel)
	world.basis = _basis_from_rotation_and_scale(r, _effective_axis_lengths(world.basis))
	_commit_inspector_change(sel, parent_inv * world)


## Local scale - acts along the object's OWN axes.
##
## Independent of the gizmo's Global/Local toggle: the RotX/Y/Z fields beside
## these are local angles, so ScaleX/Y/Z being local axis lengths is what makes
## each SET coherent. The World set carries its own scale row for world axes.
##
## Rebuild from the live basis by a RATIO rather than from `sel.scale`.
## `Basis.scaled(s)` is `S * basis` (it pre-multiplies), so against a basis that
## already carries scale the row lengths MULTIPLY instead of being replaced:
## dragging X from 2 to 5 on a (2,3,4) cube produced (10,9,16), corrupting the
## untouched axes too, and each repeat squared them.
##
## The old fix orthonormalised first, which flattened a sheared basis back to
## R*S — so a Global-scaled object lost its shear the moment the panel was
## touched. Right-multiplying by the ratio scales one local axis and leaves
## everything else, shear included, untouched.
func _on_inspector_scale_changed(val: float, axis: String):
	var sel := selection_manager.get_selected()
	if not sel: return
	var after := sel.transform
	var basis := after.basis
	var current := _effective_axis_lengths(basis)
	var target := current
	match axis:
		"x": target.x = val
		"y": target.y = val
		"z": target.z = val
	after.basis = basis * Basis.from_scale(_ratio_to_reach(target, current))
	_commit_inspector_change(sel, after)


## World scale - acts along the axes of the frame the object is in.
##
## PRE-multiplies where the Local row right-multiplies, and that is the whole point
## rather than a copy-paste difference: scaling row i by f_i scales THIS frame's
## axis i, which is exactly what `_row_lengths` displays and exactly what the
## Global gizmo scale handle does. Because row i's length scales by f_i and no
## other row moves, the read/write pair is exactly invertible.
##
## Pre-multiplying an orthogonal basis by a diagonal keeps its columns orthogonal,
## so this does not invent shear. Against a SHEARED basis it changes the skew
## rather than removing it, which is the intended world-axis behaviour and is why
## a world-axis scale is a legitimate way to shear an object in the first place.
func _on_inspector_world_scale_changed(val: float, axis: String):
	var sel := selection_manager.get_selected()
	if not sel: return
	var after := sel.transform
	var basis := after.basis
	var current := _row_lengths(basis)
	var target := current
	match axis:
		"x": target.x = val
		"y": target.y = val
		"z": target.z = val
	after.basis = Basis.from_scale(_ratio_to_reach(target, current)) * basis
	_commit_inspector_change(sel, after)


## Per-axis factor taking each component of `current` to `target`, with a floor so
## a degenerate zero-length axis cannot divide by zero. Both scale paths use it, so
## the Local and World rows cannot drift apart in how they handle that edge.
func _ratio_to_reach(target: Vector3, current: Vector3) -> Vector3:
	return Vector3(
			target.x / maxf(current.x, 0.0001),
			target.y / maxf(current.y, 0.0001),
			target.z / maxf(current.z, 0.0001))


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
		# collect_selectable_meshes() recurses into groups, so loaded scenes
		# with grouped members frame correctly instead of only top-level meshes.
		# Map to Array[Node3D] since fit_all() is typed against the base class.
		var objects: Array[Node3D] = []
		for mesh in selection_manager.collect_selectable_meshes():
			objects.append(mesh)
		camera_controller.fit_all(objects)


func _rebuild_portfolio_browser():
	var list: ItemList = %LoadDialog/VBox/ItemList
	list.clear()
	for entry in portfolio_manager.get_entries():
		list.add_item(entry.name)


# ── Mode ────────────────────────────────────────────────────────

## The bottom bar's World/Object button — the SAME setting as the toolbar's Local
## checkbox, not a second one.
##
## It used to do nothing but rewrite its own label, which is worse than having no
## button at all: it sits directly beside the transform readout, reads as the
## frame control, and pressing it changed nothing except the text. A control that
## looks live and is not teaches the user that this app is broken.
func _on_mode_toggle():
	toggle_gizmo_orientation()


func _update_zoom_display():
	var zoom := camera_controller.get_distance()
	%ZoomLabel.text = "Zoom: %.0f%%" % ((8.0 / max(zoom, 0.1)) * 100.0)


# ── Undo / Redo ────────────────────────────────────────────────

func _on_undo():
	var cmd := undo_redo.undo()
	if not cmd:
		return
	_after_history_repoint(cmd)
	_rebuild_hierarchy_request()
	_update_inspector(selection_manager.get_selected())


func _on_redo():
	var cmd := undo_redo.redo()
	if not cmd:
		return
	_after_history_repoint(cmd)
	_rebuild_hierarchy_request()
	_update_inspector(selection_manager.get_selected())


## Undo/redo rebuild node instances (snapshot system frees + materializes).
## Re-point the selection onto the freshly created nodes so the gizmo keeps
## tracking live instances instead of silently going stale and lingering.
func _after_history_repoint(cmd: ModelingAction) -> void:
	selection_manager.reselect_from_ids(cmd.get_last_created_ids())


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
