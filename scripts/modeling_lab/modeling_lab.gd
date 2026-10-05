class_name ModelingLab
extends CanvasLayer

signal lab_closed

@export_file("*.tscn") var fallback_scene := "res://scenes/main_menu.tscn"

enum LabMode { LESSON, CREATIVE_STUDIO }
enum Tool { MOVE, ROTATE, SCALE }

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
	var tip := cam.unproject_position(gizmo.global_position + _drag_axis)
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
func _compute_rotate_tangent(grab_pos: Vector2, origin: Vector2,
		hit_3d: Vector3) -> Vector2:
	var cam := camera_controller.camera
	var n := _drag_axis.normalized()
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
				_drag_axis = pick.get("axis", Vector3.ZERO)
				_drag_uniform = pick.get("uniform", true)
				_drag_start_mouse = mouse_pos
				if _drag_uniform:
					_drag_axis_screen = Vector2.RIGHT
					_drag_axis_perp = Vector2.UP
				else:
					_compute_drag_screen_basis(mouse_pos,
							pick.get("position", Vector3.INF))
				match _current_tool:
					Tool.MOVE: transform_manager.begin_move(_drag_axis)
					Tool.ROTATE: transform_manager.begin_rotate(_drag_axis)
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
					transform_manager.apply_move(_drag_axis, dist * 0.02)
				Tool.ROTATE:
					var tangential: float = moved.dot(_drag_axis_perp)
					# 0.001 rad/px needed ~5,600px of drag for a full turn, so a
					# rotation felt almost frozen even once the snap was fixed.
					# 0.004 puts a 90deg turn at ~390px, which tracks a mouse or
					# trackpad naturally. TransformManager accumulates this per
					# frame and snaps the TOTAL, so raising it does not fight the
					# snap - it only makes the detents arrive sooner.
					transform_manager.apply_rotate(_drag_axis, tangential * 0.004)
				Tool.SCALE:
					if _drag_uniform:
						transform_manager.apply_scale(_drag_axis, _scale_delta(mouse_pos, _drag_start_mouse, _drag_axis_screen), true)
					else:
						transform_manager.apply_scale(_drag_axis, _scale_delta(mouse_pos, _drag_start_mouse, _drag_axis_screen), false)
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


func _update_inspector(node: Node3D):
	if not node:
		%NodeName.text = ""
		%PosX.set_value_no_signal(0); %PosY.set_value_no_signal(0); %PosZ.set_value_no_signal(0)
		%RotX.set_value_no_signal(0); %RotY.set_value_no_signal(0); %RotZ.set_value_no_signal(0)
		%ScaleX.set_value_no_signal(1); %ScaleY.set_value_no_signal(1); %ScaleZ.set_value_no_signal(1)
		%ColorSwatch.color = Color.WHITE
		if _base_color_wheel:
			_base_color_wheel.set_color(Color.WHITE)
		%MetallicSlider.set_value_no_signal(0.0)
		%RoughnessSlider.set_value_no_signal(0.5)
		return
	%NodeName.text = HierarchyManager.display_of(node)
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


func _on_inspector_pos_changed(val: float, axis: String):
	var sel := selection_manager.get_selected()
	if not sel: return
	var before := sel.transform
	var after := sel.transform
	var p: Vector3 = sel.position
	match axis:
		"x": p.x = val
		"y": p.y = val
		"z": p.z = val
	after.origin = p
	var action := CommandFactory.transform([object_container.get_path_to(sel)], [before], [after], object_container, spawner, material_manager, hierarchy_manager)
	undo_redo.execute_command(action)
	selection_manager.reselect_from_ids(action.get_last_created_ids())
	_update_bottom_bar(selection_manager.get_selected())


func _on_inspector_rot_changed(val: float, axis: String):
	var sel := selection_manager.get_selected()
	if not sel: return
	var before := sel.transform
	var after := sel.transform
	var r: Vector3 = sel.rotation_degrees
	match axis:
		"x": r.x = val
		"y": r.y = val
		"z": r.z = val
	# Scale is baked into a Transform3D's basis, so rebuilding the basis from
	# euler angles alone silently discards it: rotating a scaled object in the
	# inspector reset it to unit size. Rebuild the rotation, then re-apply the
	# object's scale on top.
	#
	# The multiply order matters. `Basis.scaled(s)` PRE-multiplies, so
	# `Basis.from_euler(r).scaled(s)` is S*R. That only reads back correctly
	# while the incoming basis is a bare rotation; when it already carries
	# scale, S*R mixes the row lengths and a (2,3,4) scale under yaw came back
	# as (3.16,3.0,3.16). `R*S` is the true TRS order and decomposes cleanly.
	#
	# Read the scale from `sel.scale` (Node3D decomposes it properly), not
	# `sel.basis.get_scale()` - the latter is row lengths, valid only while
	# unrotated.
	var s: Vector3 = sel.scale
	after.basis = Basis.from_euler(Vector3(deg_to_rad(r.x), deg_to_rad(r.y), deg_to_rad(r.z))) * Basis.from_scale(s)
	var action := CommandFactory.transform([object_container.get_path_to(sel)], [before], [after], object_container, spawner, material_manager, hierarchy_manager)
	undo_redo.execute_command(action)
	selection_manager.reselect_from_ids(action.get_last_created_ids())


func _on_inspector_scale_changed(val: float, axis: String):
	var sel := selection_manager.get_selected()
	if not sel: return
	var before := sel.transform
	var after := sel.transform
	var s: Vector3 = sel.scale
	match axis:
		"x": s.x = val
		"y": s.y = val
		"z": s.z = val
	# Rebuild as orthonormal * scale rather than scaling the live basis.
	# `Basis.scaled(s)` is `S * basis` (it pre-multiplies), so against a basis
	# that already carries scale the row lengths MULTIPLY instead of being
	# replaced: dragging X from 2 to 5 on a (2,3,4) cube produced (10,9,16),
	# corrupting the untouched axes too, and each repeat squared them. Strip
	# the scale off, then rebuild R * S in true TRS order.
	var rot_only: Basis = after.basis.orthonormalized()
	after.basis = rot_only * Basis.from_scale(s)
	var action := CommandFactory.transform([object_container.get_path_to(sel)], [before], [after], object_container, spawner, material_manager, hierarchy_manager)
	undo_redo.execute_command(action)
	selection_manager.reselect_from_ids(action.get_last_created_ids())


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

func _on_mode_toggle():
	%ModeBtn.text = "Local" if %ModeBtn.text == "World" else "World"


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
