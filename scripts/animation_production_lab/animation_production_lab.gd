class_name AnimationProductionLab
extends CanvasLayer

## Root of the 2.5D Animation Production Lab (4th EMC Simulator tool lab).
## Holds the World (Node3D under UI/SceneViewportContainer/SceneViewport) and
## the Systems/UI
## controllers wired up by later tasks. The lab is fully self-contained:
## it boots from committed starter assets and never loads another lab's
## scenes, scripts, or UI. Saves live under user://animation_lab/.
##
## Independence contract (AGENTS.md): this file must import cleanly with an
## empty user://exports/ and user://drawings/, and must keep working when
## those directories are missing entirely.

signal lab_closed

## Emitted once the guided run is submitted and the level is completed.
## Named guided_flow_completed (not guided_completed) because GDScript cannot
## share a name between a signal and a bool var, and the flag keeps the
## plan's name for boot-time resilience reads (Task 15).
signal guided_flow_completed

const DEFAULT_ASSIGNMENT := "res://data/assignments/animation/day_in_emc_lab.tres"
const LEVEL_PATH := "res://data/levels/animation_production_lab.tres"
const MUSIC_PATH := "res://assets/sound/Level_4_Background_sound.mp3"

# Best-effort SFX candidates (Task 17): played only when the file exists.
# The jam ships no SFX under assets/sound, so these stay silent — never an
# error path.
const SFX_BUTTON: Array[String] = [
	"res://assets/sound/button_click.mp3",
	"res://assets/sound/click.mp3",
]
const SFX_SUCCESS: Array[String] = [
	"res://assets/sound/success.mp3",
	"res://assets/sound/complete.mp3",
]
const SFX_ERROR: Array[String] = [
	"res://assets/sound/error.mp3",
	"res://assets/sound/denied.mp3",
]

const STAGE_NAMES := [
	"BRIEF", "PLAN", "ASSETS", "STAGING", "CAMERA",
	"LIGHTING", "FRAMES", "KEYFRAME", "TIMING", "PREVIEW", "SUBMIT",
]

# Stage ids (must match AnimationAssignmentManager.Stage — do not renumber).
const STAGE_BRIEF := AnimationAssignmentManager.Stage.BRIEF
const STAGE_PLAN := AnimationAssignmentManager.Stage.PLAN
const STAGE_ASSETS := AnimationAssignmentManager.Stage.ASSETS
const STAGE_STAGING := AnimationAssignmentManager.Stage.STAGING
const STAGE_CAMERA := AnimationAssignmentManager.Stage.CAMERA
const STAGE_LIGHTING := AnimationAssignmentManager.Stage.LIGHTING
const STAGE_FRAMES := AnimationAssignmentManager.Stage.FRAMES
const STAGE_KEYFRAME := AnimationAssignmentManager.Stage.KEYFRAME
const STAGE_TIMING := AnimationAssignmentManager.Stage.TIMING
const STAGE_PREVIEW := AnimationAssignmentManager.Stage.PREVIEW
const STAGE_SUBMIT := AnimationAssignmentManager.Stage.SUBMIT

# Panel scripts are class_name-less on purpose (no global class registry
# noise); the root types its handles through these preloaded consts.
const TopBarPanel := preload("res://scripts/animation_production_lab/ui/top_bar.gd")
const AssignmentPanelScript := preload("res://scripts/animation_production_lab/ui/assignment_panel.gd")
const StoryboardPanelScript := preload("res://scripts/animation_production_lab/ui/storyboard_panel.gd")
const AssetLibraryPanelScript := preload("res://scripts/animation_production_lab/ui/asset_library_panel.gd")
const InspectorPanelScript := preload("res://scripts/animation_production_lab/ui/inspector_panel.gd")
const LayersPanelScript := preload("res://scripts/animation_production_lab/ui/layers_panel.gd")
const TimelinePanelScript := preload("res://scripts/animation_production_lab/ui/timeline_panel.gd")
const AnimationControlsScript := preload("res://scripts/animation_production_lab/ui/animation_controls.gd")
const HintPanelScript := preload("res://scripts/animation_production_lab/ui/hint_panel.gd")
const TutorialOverlayScript := preload("res://scripts/animation_production_lab/ui/tutorial_overlay.gd")
const SubmissionPanelScript := preload("res://scripts/animation_production_lab/ui/submission_panel.gd")
const ScorePanelScript := preload("res://scripts/animation_production_lab/ui/score_panel.gd")
const StudioPanelScript := preload("res://scripts/animation_production_lab/ui/studio_panel.gd")

@export_file("*.tscn") var fallback_scene := "res://scenes/main_menu.tscn"

# Tuning surface (spec §8). Controllers read these on _ready.
@export var default_fps := 12
@export var default_duration := 5.0
@export var max_duration := 30.0
@export var fps_min := 1
@export var fps_max := 60
@export var allow_custom_assets := true
@export var enable_hints := true
@export var enable_scoring := true
@export var enable_creative_studio := true
@export var autosave_enabled := true

# Controllers (scene nodes under Systems).
@onready var world: WorldController = $Systems/WorldHub
@onready var camera: AnimationCameraController = $Systems/CameraHub
@onready var lighting: LightingController = $Systems/LightingHub
@onready var frames: FrameController = $Systems/FrameHub
@onready var keyframes: KeyframeController = $Systems/KeyframeHub
@onready var timeline: TimelineController = $Systems/TimelineHub
@onready var assignment_manager: AnimationAssignmentManager = $Systems/AssignmentHub
@onready var preview: PreviewController = $Systems/PreviewHub

# Scoring is RefCounted, so it is created in _ready rather than a scene node.
var scoring: ScoringController

# Created in _ready when autosave_enabled; writes guided.tres on stage changes.
var save_controller: SaveController

# Creative Studio project manager (Task 16). Always created so the studio has
# a save layer; the autosave hook above only exists when autosave_enabled.
var studio: CreativeStudioController

# Read-only EMC asset adapter (RefCounted; booted with committed assets).
var library := EMCAssetLibrary.new()

# Guided-mode panels (instanced under UI).
@onready var top_bar: TopBarPanel = $UI/TopBar
@onready var assignment_panel: AssignmentPanelScript = $UI/AssignmentPanel
@onready var storyboard_panel: StoryboardPanelScript = $UI/StoryboardPanel
@onready var asset_library_panel: AssetLibraryPanelScript = $UI/AssetLibraryPanel
@onready var inspector_panel: InspectorPanelScript = $UI/InspectorPanel
@onready var layers_panel: LayersPanelScript = $UI/LayersPanel
@onready var timeline_panel: TimelinePanelScript = $UI/TimelinePanel
@onready var animation_controls: AnimationControlsScript = $UI/AnimationControls
@onready var hint_panel: HintPanelScript = $UI/HintPanel
@onready var tutorial_overlay: TutorialOverlayScript = $UI/TutorialOverlay
@onready var submission_panel: SubmissionPanelScript = $UI/SubmissionPanel
@onready var score_panel: ScorePanelScript = $UI/ScorePanel
@onready var studio_panel: StudioPanelScript = $UI/StudioPanel
@onready var music_player: AudioStreamPlayer = $Audio/MusicPlayer
@onready var sfx_player: AudioStreamPlayer = $Audio/SFXPlayer

enum Mode {GUIDED = 0, STUDIO = 1}

## Guided-flow state. studio unlocks in the Creative Studio mode (Task 16)
## and is read back from AnimationLabSaveData on boot (Task 15).
var mode: int = Mode.GUIDED
var guided_completed := false
var last_score: AnimationScoreData
var _previewing := false
var _submission_refresh := 0.0


func _ready() -> void:
	scoring = ScoringController.new()
	_apply_tuning()
	_wire_controller_refs()
	_register_starter_lights()
	_register_starter_order()
	_wire_panels()
	_setup_audio()
	if autosave_enabled:
		save_controller = SaveController.new()
	studio = CreativeStudioController.new()
	studio.save = save_controller if save_controller != null else SaveController.new()
	assignment_manager.stage_changed.connect(on_stage_changed)
	assignment_manager.stage_changed.connect(_autosave_stage_changed)
	assignment_manager.assignment_loaded.connect(_on_assignment_loaded)
	world.objects_changed.connect(_on_objects_changed)
	library.refresh()
	_apply_saved_state()
	assignment_manager.load_assignment(DEFAULT_ASSIGNMENT)
	top_bar.set_mode_label("GUIDED")
	top_bar.set_studio_unlocked(guided_completed)
	on_stage_changed(assignment_manager.current_stage())


## Boot-time unlock read (spec §15: the studio gate lives in the lab's own
## save, not only in LevelProgression). _complete_guided_flow persists the
## completed flag, so a later boot re-opens the studio.
func _apply_saved_state() -> void:
	if save_controller == null:
		return
	var saved := save_controller.load_data()
	if saved.guided_completed:
		guided_completed = true


func _process(delta: float) -> void:
	if _previewing:
		preview.step(delta)
	if submission_panel.visible:
		_submission_refresh -= delta
		if _submission_refresh <= 0.0:
			_submission_refresh = 0.25
			_refresh_submission()


func _apply_tuning() -> void:
	timeline.min_fps = fps_min
	timeline.max_fps = fps_max
	timeline.max_duration = max_duration
	timeline.set_fps(default_fps)
	timeline.set_duration(default_duration)


func _wire_controller_refs() -> void:
	timeline.frame_controller_ref = frames
	preview.timeline = timeline
	preview.frames = frames
	preview.keyframes = keyframes
	preview.world = world
	preview.camera = camera
	preview.lighting = lighting
	assignment_manager.frame_sources = frames
	assignment_manager.keyframe_sources = keyframes
	assignment_manager.timeline_sources = timeline


## The scene's starter lights (StarterKeyLight/StarterFillLight) are authored
## in the .tscn, so adopt them into the LightingController's measurable set
## instead of duplicating them with add_light.
func _register_starter_lights() -> void:
	var dir := get_node_or_null(
		"UI/SceneViewportContainer/SceneViewport/World/LightingRoot/StarterKeyLight") as DirectionalLight3D
	var omni := get_node_or_null(
		"UI/SceneViewportContainer/SceneViewport/World/LightingRoot/StarterFillLight") as OmniLight3D
	if dir != null:
		lighting.register_existing("starter_key", dir)
	if omni != null:
		lighting.register_existing("starter_fill", omni)


## B2 layer ordering: the authored starter nodes (StarterBackdrop/
## StarterCharacter/StarterWorkstation) are NOT registered in the composition
## stack, so they must never out-rank a player layer. Pin them all to
## STARTER_PRIORITY (= 0): sprites carry it on the instance, the workstation
## material gets duplicated into the transparent pass at priority 0 (opaque
## meshes sort by depth, which would break the painter's order). Player
## layers start at layer_priority(0) = 16, strictly above them. Idempotent:
## safe to re-run on every lab boot.
func _register_starter_order() -> void:
	var world_root := "UI/SceneViewportContainer/SceneViewport/World"
	for path in [
		world_root + "/BackgroundRoot/StarterBackdrop",
		world_root + "/CharacterRoot/StarterCharacter",
		world_root + "/PropRoot/StarterWorkstation",
	]:
		var node := get_node_or_null(path) as Node3D
		if node != null:
			RenderOrder.set_layer_priority(node, RenderOrder.STARTER_PRIORITY)


func _wire_panels() -> void:
	# TopBar is the LAST child of UI in animation_production_lab.tscn on
	# purpose: later siblings both draw and pick first, so the always-visible
	# Exit/Continue/Studio controls must sit above the full-rect modal panels
	# (AssignmentPanel, AssetLibraryPanel, TimelinePanel, SubmissionPanel,
	# TutorialOverlay — all default STOP mouse_filter). A panel added after
	# TopBar would swallow TopBar clicks again; keep it last.
	top_bar.exit_requested.connect(exit_lab)
	top_bar.studio_requested.connect(unlock_creative_studio)
	top_bar.continue_requested.connect(_on_continue_pressed)
	top_bar.undo_requested.connect(_on_topbar_undo)
	top_bar.redo_requested.connect(_on_topbar_redo)
	top_bar.dock_toggle_requested.connect(_on_dock_toggle)
	world.history.history_changed.connect(_on_history_changed)
	assignment_panel.brief_acknowledged.connect(_on_brief_acknowledged)
	storyboard_panel.order_submitted.connect(_on_order_submitted)
	asset_library_panel.add_requested.connect(_on_asset_add_requested)
	inspector_panel.object_selected.connect(_on_inspector_object_selected)
	inspector_panel.transform_edited.connect(_on_inspector_transform_edited)
	inspector_panel.visibility_toggled.connect(_on_inspector_visibility_toggled)
	inspector_panel.delete_requested.connect(_on_inspector_delete)
	layers_panel.layer_selected.connect(_on_layers_selected)
	layers_panel.add_requested.connect(_on_layers_add)
	layers_panel.delete_requested.connect(_on_layers_delete)
	layers_panel.duplicate_requested.connect(_on_layers_duplicate)
	layers_panel.rename_requested.connect(_on_layers_rename)
	layers_panel.visibility_toggled.connect(_on_layers_visibility_toggled)
	layers_panel.lock_toggled.connect(_on_layers_lock_toggled)
	layers_panel.move_up_requested.connect(_on_layers_reorder.bind("move_up"))
	layers_panel.move_down_requested.connect(_on_layers_reorder.bind("move_down"))
	layers_panel.to_front_requested.connect(_on_layers_reorder.bind("to_front"))
	layers_panel.to_back_requested.connect(_on_layers_reorder.bind("to_back"))
	layers_panel.forward_requested.connect(_on_layers_reorder.bind("forward"))
	layers_panel.backward_requested.connect(_on_layers_reorder.bind("backward"))
	world.selection_changed.connect(_on_world_selection_changed)
	world.layer_order_changed.connect(_refresh_layers_panel)
	timeline_panel.frame_added.connect(_on_frame_added)
	timeline_panel.frame_removed.connect(_on_frame_removed)
	timeline_panel.frame_texture_requested.connect(_on_frame_texture_requested)
	animation_controls.play_toggled.connect(_on_play_toggled)
	animation_controls.rewind_requested.connect(_on_rewind_requested)
	animation_controls.fps_changed.connect(_on_fps_changed)
	animation_controls.duration_changed.connect(_on_duration_changed)
	tutorial_overlay.tutorial_closed.connect(_on_tutorial_closed)
	submission_panel.submit_requested.connect(on_submit_pressed)
	score_panel.continue_to_studio.connect(unlock_creative_studio)
	studio_panel.new_requested.connect(_on_studio_new)
	studio_panel.save_requested.connect(_on_studio_save)
	studio_panel.load_requested.connect(_on_studio_load)
	studio_panel.rename_requested.connect(_on_studio_rename)
	studio_panel.duplicate_requested.connect(_on_studio_duplicate)
	studio_panel.delete_requested.connect(_on_studio_delete)


## Stage -> panel visibility map. One panel (plus the persistent top bar) is
## visible per stage. score_panel is independent — shown only by submitting.
func show_stage_ui(stage: int) -> void:
	score_panel.hide()
	studio_panel.hide()
	# Dock toggles are Studio-only: in guided the stage map alone drives
	# panel visibility, and there is no undo/redo or resizing to unlock.
	top_bar.set_dock_toggles_visible(false)
	# The tutorial overlay is a full-screen dark layer (backdrop 0.75 alpha):
	# it owns the boot intro at BRIEF and must drop away for every working
	# stage, or the stage world is dimmed to ~25% for the whole run.
	tutorial_overlay.visible = stage == STAGE_BRIEF and not assignment_manager.tutorial_completed
	assignment_panel.visible = stage == STAGE_BRIEF
	storyboard_panel.visible = stage == STAGE_PLAN
	asset_library_panel.visible = stage == STAGE_ASSETS
	layers_panel.visible = stage >= STAGE_STAGING and stage <= STAGE_LIGHTING
	inspector_panel.visible = stage >= STAGE_STAGING and stage <= STAGE_LIGHTING
	timeline_panel.visible = stage >= STAGE_FRAMES and stage <= STAGE_TIMING
	animation_controls.visible = stage >= STAGE_FRAMES and stage <= STAGE_PREVIEW
	hint_panel.visible = stage == STAGE_PREVIEW
	submission_panel.visible = stage == STAGE_SUBMIT
	if stage == STAGE_SUBMIT:
		submission_panel.set_status("All requirements met? Press SUBMIT to finish.")


func on_stage_changed(stage: int) -> void:
	show_stage_ui(stage)
	top_bar.set_stage_label(STAGE_NAMES[clampi(stage, 0, STAGE_NAMES.size() - 1)])
	top_bar.set_continue_visible(_continue_visible_for_stage(stage))
	top_bar.set_status_label("")
	_refresh_visible_panel_data(stage)
	if stage == STAGE_PREVIEW:
		preview.evaluate_review()
		_previewing = true
	else:
		_previewing = false
	if enable_hints:
		hint_panel.set_hints(assignment_manager.hints_for_stage())


## Continue shows while the guided flow still has gates to pass (ASSETS..
## PREVIEW). BRIEF/PLAN panels own their proceed controls and SUBMIT owns its
## Submit button; Studio mode hides it entirely via _enter_studio_mode.
func _continue_visible_for_stage(stage: int) -> bool:
	return stage >= STAGE_ASSETS and stage <= STAGE_PREVIEW


## Shared Continue affordance: for stages that consume a measured snapshot of
## the world (STAGING, mirroring the PLAN order_submitted pattern), re-measure
## it live before asking the manager to advance. On a blocked advance the
## StatusLabel names the first unmet requirement for the current stage.
func _on_continue_pressed() -> void:
	if assignment_manager.current_stage() == STAGE_STAGING:
		var state := world.staging_state()
		assignment_manager.stage_scene_ok(
			bool(state.get("character_before_background", false)),
			bool(state.get("near_prop", false)))
	if assignment_manager.advance_stage():
		top_bar.set_status_label("")
	else:
		top_bar.set_status_label(_first_unmet_requirement())


func _first_unmet_requirement() -> String:
	for req in assignment_manager.stage_requirements():
		if not req.get("passed", false):
			return str(req.get("label", ""))
	return ""


func _refresh_visible_panel_data(stage: int) -> void:
	if stage == STAGE_ASSETS:
		asset_library_panel.set_assets(library.list())
	elif stage >= STAGE_STAGING and stage <= STAGE_LIGHTING:
		inspector_panel.set_object_list(_object_summaries())
		layers_panel.set_layers(world.layer_summaries())
	elif stage >= STAGE_FRAMES and stage <= STAGE_TIMING:
		timeline_panel.set_frame_count(frames.frames.size())
		animation_controls.set_fps(timeline.fps)
		animation_controls.set_duration(timeline.duration)


func _on_assignment_loaded(assign: AnimationAssignment) -> void:
	if assign == null:
		return
	var story_text := ""
	for beat in assign.story_beats:
		story_text += "- " + str(beat.get("text", "")) + "\n"
	assignment_panel.set_brief(
		assign.display_name,
		story_text,
		"Target: %d fps · %.1f s" % [assign.target_fps, assign.target_duration],
	)
	storyboard_panel.set_beats(assign.story_beats)
	tutorial_overlay.set_steps(assignment_manager.tutorial_steps)


func _on_brief_acknowledged() -> void:
	assignment_manager.advance_stage()


func _on_order_submitted(ids: Array[String]) -> void:
	if assignment_manager.order_story_beats(ids):
		storyboard_panel.mark_ok()
		assignment_manager.advance_stage()
	else:
		storyboard_panel.set_status("Order the beats from beginning to end.")


func _on_asset_add_requested(asset: EMCAssetData) -> void:
	world.add_asset(asset, _spawn_position_for(asset.category))


func _spawn_position_for(category: String) -> Vector3:
	match category:
		WorldController.CATEGORY_BACKGROUND:
			return Vector3(0, 1, -6)
		WorldController.CATEGORY_PROP:
			return Vector3(1.2, 0.45, 0)
		_:
			return Vector3(0, 0.5, 0)


func _on_inspector_object_selected(object_id: String) -> void:
	world.select(object_id)
	inspector_panel.select_object(object_id)
	inspector_panel.set_object_data(world.get_object(object_id))


func _on_inspector_transform_edited(object_id: String, property: String, value: Variant) -> void:
	match property:
		"position":
			world.set_object_position(object_id, value as Vector3)
		"rotation":
			world.set_object_rotation(object_id, value as Vector3)
		"scale":
			world.set_object_scale(object_id, value as Vector3)


func _on_inspector_visibility_toggled(object_id: String, visible: bool) -> void:
	world.set_object_visible(object_id, visible)


func _on_inspector_delete(object_id: String) -> void:
	world.remove_object(object_id)
	inspector_panel.set_object_list(_object_summaries())


func _on_layers_selected(object_id: String) -> void:
	world.select(object_id)


func _on_layers_add() -> void:
	var lib_asset := asset_library_panel.selected_asset()
	if lib_asset == null:
		return
	_on_asset_add_requested(lib_asset)


func _on_layers_delete(object_id: String) -> void:
	world.remove_object(object_id)


func _on_layers_duplicate(object_id: String) -> void:
	world.duplicate_object(object_id)


func _on_layers_rename(object_id: String, name: String) -> void:
	world.rename_layer(object_id, name)


func _on_layers_visibility_toggled(object_id: String, visible: bool) -> void:
	world.set_object_visible(object_id, visible)


func _on_layers_lock_toggled(object_id: String, locked: bool) -> void:
	world.set_layer_locked(object_id, locked)


func _on_layers_reorder(object_id: String, op: String) -> void:
	match op:
		"move_up": world.move_layer_up(object_id)
		"move_down": world.move_layer_down(object_id)
		"to_front": world.layer_to_front(object_id)
		"to_back": world.layer_to_back(object_id)
		"forward": world.layer_forward(object_id)
		"backward": world.layer_backward(object_id)


## Studio docker toggles (Task 6): the TopBar check-button rows map 1:1 to
## panel visibility in Studio mode. The companion resize strip hides with
## its docker so a floating divider never lingers after its panel.
func _on_dock_toggle(name: String, on: bool) -> void:
	match name:
		"layers":
			layers_panel.visible = on
			(get_node("UI/LayersResizeStrip") as Control).visible = on
		"inspector":
			inspector_panel.visible = on
		"assets":
			asset_library_panel.visible = on
		"timeline":
			timeline_panel.visible = on
			(get_node("UI/TimelineResizeStrip") as Control).visible = on
	top_bar.set_dock_toggle(name, on)


## Selection is world-owned: LayersPanel rows and Inspector rows both funnel
## through world.select(), and this handler keeps every panel in step. The
## panels never emit back here (setter-only), so there is no loop.
func _on_world_selection_changed(object_id: String) -> void:
	layers_panel.set_selected(object_id)
	inspector_panel.select_object(object_id)
	if object_id != "":
		inspector_panel.set_object_data(world.get_object(object_id))


func _on_objects_changed() -> void:
	if inspector_panel.visible:
		inspector_panel.set_object_list(_object_summaries())
	_refresh_layers_panel()


## The Layers docker's only data source: refresh it from the world whenever
## objects or the composition stack change. Visibility-guarded so hidden
## stages (and the studio's own gating) never pay for an invisible rebuild.
func _refresh_layers_panel() -> void:
	if layers_panel.visible:
		layers_panel.set_layers(world.layer_summaries())


func _object_summaries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for object_id in world.all_objects():
		var data := world.get_object(object_id)
		out.append({
			"id": object_id,
			"category": str(data.get("category", "")),
			"asset_id": str(data.get("asset_id", "")),
		})
	return out


func _on_frame_added() -> void:
	var tex: Texture2D = null
	var lib_asset := asset_library_panel.selected_asset()
	if lib_asset != null:
		tex = library.load_texture(lib_asset)
	frames.add_frame(tex, 0.1)
	timeline_panel.set_frame_count(frames.frames.size())


func _on_frame_removed(index: int) -> void:
	frames.remove_frame(index)
	timeline_panel.set_frame_count(frames.frames.size())


func _on_frame_texture_requested(index: int) -> void:
	var lib_asset := asset_library_panel.selected_asset()
	if lib_asset != null:
		frames.set_frame_texture(index, library.load_texture(lib_asset))


func _on_play_toggled() -> void:
	_previewing = not _previewing
	if _previewing:
		timeline.play()
	else:
		timeline.pause()
	_play_sfx_optional(SFX_BUTTON)


func _on_rewind_requested() -> void:
	timeline.current_time = 0.0


func _on_fps_changed(fps: int) -> void:
	timeline.set_fps(fps)


func _on_duration_changed(duration: float) -> void:
	timeline.set_duration(duration)


func _on_tutorial_closed() -> void:
	assignment_manager.tutorial_done()
	tutorial_overlay.hide()


## Task 14: submission. Gated by can_advance() at SUBMIT; on success the
## review checklist is refreshed, scored, shown, and the level completes.
func on_submit_pressed() -> void:
	if assignment_manager.current_stage() != STAGE_SUBMIT:
		return
	if not assignment_manager.can_advance():
		submission_panel.set_status("Not every requirement is met yet.")
		_play_sfx_optional(SFX_ERROR)
		return
	preview.evaluate_review()
	if not enable_scoring:
		_complete_guided_flow()
		_play_sfx_optional(SFX_SUCCESS)
		return
	last_score = scoring.score(
		assignment_manager.story_order_correct,
		assignment_manager.assignment,
		world, camera, lighting, frames, keyframes, timeline,
		preview.review_checklist,
	)
	score_panel.show_score(last_score)
	_complete_guided_flow()
	_play_sfx_optional(SFX_SUCCESS)


func _complete_guided_flow() -> void:
	guided_completed = true
	var level := load(LEVEL_PATH) as LevelDefinition
	if level != null and not LevelProgression.is_level_completed(level.level_id):
		LevelProgression.complete_level(level)
	# Persist the flag so the studio gate (which boots from its own save,
	# spec §15) re-opens on the next launch.
	_autosave_stage_changed(-1)
	guided_flow_completed.emit()


## Keep the SUBMIT checklist live without rebuilding rows every frame.
func _refresh_submission() -> void:
	submission_panel.set_requirements(assignment_manager.stage_requirements())


## Task 4 undo/redo affordances. Explicit named handlers so the button
## signals and the history_changed refresh live in one place.
func _on_topbar_undo() -> void:
	world.undo()


func _on_topbar_redo() -> void:
	world.redo()


func _on_history_changed() -> void:
	top_bar.set_undo_enabled(world.history.can_undo())
	top_bar.set_redo_enabled(world.history.can_redo())


## Creative Studio unlock gate (spec §5): only after the guided run is
## submitted does the studio open; the flag survives a reboot (Task 15).
func unlock_creative_studio() -> void:
	if not guided_completed or not enable_creative_studio:
		return
	if mode == Mode.STUDIO:
		return
	mode = Mode.STUDIO
	top_bar.set_mode_label("STUDIO")
	top_bar.set_studio_unlocked(false)
	score_panel.hide()
	_enter_studio_mode()


## Task 16: the studio runs the same World/Timeline pipeline, assignment-free
## (spec §5). Guided stage panels drop away; the object/timeline tools and
## the studio panel stay so the player can build and save freely.
func _enter_studio_mode() -> void:
	assignment_panel.hide()
	storyboard_panel.hide()
	submission_panel.hide()
	hint_panel.hide()
	tutorial_overlay.hide()
	top_bar.set_continue_visible(false)
	top_bar.set_undo_redo_visible(true)
	top_bar.set_dock_toggles_visible(true)
	(get_node("UI/LayersResizeStrip") as Control).show()
	(get_node("UI/TimelineResizeStrip") as Control).show()
	asset_library_panel.show()
	asset_library_panel.set_assets(library.list())
	layers_panel.show()
	layers_panel.set_layers(world.layer_summaries())
	inspector_panel.show()
	inspector_panel.set_object_list(_object_summaries())
	timeline_panel.show()
	timeline_panel.set_frame_count(frames.frames.size())
	animation_controls.show()
	animation_controls.set_fps(timeline.fps)
	animation_controls.set_duration(timeline.duration)
	_previewing = false
	timeline.pause()
	studio_panel.show()
	_refresh_studio_projects()
	studio_panel.set_status("Load a project or start a new one.")


func _on_studio_new(name: String) -> void:
	name = name.strip_edges()
	if name.is_empty():
		studio_panel.set_status("Enter a project name first.")
		return
	if studio.new_project(name):
		studio_panel.set_status("Created “%s”." % name)
		_refresh_studio_projects()
	else:
		studio_panel.set_status("Could not create “%s” (name exists or is invalid)." % name)


func _on_studio_save(name: String) -> void:
	name = name.strip_edges()
	if name.is_empty():
		name = studio_panel.selected()
	if name.is_empty():
		studio_panel.set_status("Enter a name or select a project to save.")
		return
	if studio.save_current(collect_save_data(), name):
		studio_panel.set_status("Saved “%s”." % name)
		_refresh_studio_projects()
	else:
		studio_panel.set_status("Could not save “%s”." % name)


func _on_studio_load(name: String) -> void:
	var data := studio.load_project(name)
	if data == null:
		studio_panel.set_status("Could not load “%s”." % name)
		return
	_apply_project_data(data)
	studio_panel.set_status("Loaded “%s”." % name)


func _on_studio_rename(name: String, new_name: String) -> void:
	new_name = new_name.strip_edges()
	if new_name.is_empty():
		studio_panel.set_status("Type the new name in the project field.")
		return
	if studio.rename_project(name, new_name):
		studio_panel.set_status("Renamed “%s” to “%s”." % [name, new_name])
		_refresh_studio_projects()
	else:
		studio_panel.set_status("Could not rename (new name may already exist).")


func _on_studio_duplicate(name: String) -> void:
	if studio.duplicate_project(name):
		studio_panel.set_status("Duplicated “%s”." % name)
		_refresh_studio_projects()
	else:
		studio_panel.set_status("Could not duplicate “%s”." % name)


func _on_studio_delete(name: String) -> void:
	if studio.delete_project(name):
		studio_panel.set_status("Deleted “%s”." % name)
		_refresh_studio_projects()
	else:
		studio_panel.set_status("Could not delete “%s”." % name)


func _refresh_studio_projects() -> void:
	studio_panel.set_projects(studio.list_projects())


## Restore a project snapshot into the live pipeline — the studio's "Load".
## World objects are re-resolved through the asset library; frames, keyframes
## and timeline settings are rebuilt from the serialized dictionaries.
func _apply_project_data(data: AnimationLabSaveData) -> void:
	for object_id in world.all_objects():
		world.remove_object(object_id)
	for obj in data.scene_objects:
		var asset := library.get_asset(str(obj.get("asset_id", ""))) as EMCAssetData
		if asset == null:
			continue
		var object_id := world.add_asset(asset, obj.get("position", Vector3.ZERO) as Vector3)
		if object_id.is_empty():
			continue
		world.set_object_rotation(object_id, obj.get("rotation_degrees", Vector3.ZERO) as Vector3)
		world.set_object_scale(object_id, obj.get("scale", Vector3.ONE) as Vector3)
		world.set_object_visible(object_id, bool(obj.get("visible", true)))
		world.set_object_depth(object_id, float(obj.get("depth", 0.0)))
		world.set_object_layer(object_id, int(obj.get("layer", 0)))
	var cam := camera.camera()
	if cam != null:
		camera.set_transform(
			data.camera_data.get("position", Vector3(0, 0.8, 4)) as Vector3,
			data.camera_data.get("rotation_degrees", Vector3.ZERO) as Vector3,
		)
		cam.fov = float(data.camera_data.get("fov", 60.0))
	while frames.frames.size() > 1:
		frames.remove_frame(frames.frames.size() - 1)
	for i in range(maxi(1, data.frames.size())):
		if i >= frames.frames.size():
			frames.add_frame(null, 0.1)
		var entry: Dictionary = {} if data.frames.is_empty() else data.frames[i]
		frames.set_frame_texture(i, _texture_for(str(entry.get("texture", ""))))
		frames.set_frame_duration(i, float(entry.get("duration", 0.1)))
	keyframes.keyframes.clear()
	for entry in data.keyframes:
		keyframes.add_keyframe(
			float(entry.get("time", 0.0)),
			str(entry.get("target_id", "")),
			int(entry.get("target_type", 0)),
			str(entry.get("property_path", "")),
			entry.get("value", null),
			int(entry.get("interpolation", 0)),
		)
	timeline.set_fps(clampi(int(data.fps), fps_min, fps_max))
	timeline.set_duration(clampf(float(data.duration), 0.1, max_duration))
	timeline_panel.set_frame_count(frames.frames.size())
	animation_controls.set_fps(timeline.fps)
	animation_controls.set_duration(timeline.duration)


func _texture_for(path: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


## Task 15: autosave hook (spec §6) — fires on every stage change while a
## SaveController exists and writes the guided.tres snapshot.
func _autosave_stage_changed(_stage: int) -> void:
	if save_controller == null:
		return
	save_controller.save_data(collect_save_data())


## Snapshot of the current session for autosave / Creative Studio projects
## (Task 16). Fields mirror AnimationLabSaveData (spec §3); every value is a
## plain serializable Variant so the .tres round-trip is lossless.
func collect_save_data() -> AnimationLabSaveData:
	var data := AnimationLabSaveData.new()
	data.guided_completed = guided_completed
	var assign := assignment_manager.assignment
	data.current_assignment_id = "" if assign == null else assign.assignment_id
	data.scene_objects = _collect_scene_objects()
	data.camera_data = _collect_camera_data()
	data.lighting_data = _collect_lighting_data()
	data.frames = _collect_frames()
	data.keyframes = _collect_keyframes()
	data.fps = timeline.fps
	data.duration = timeline.duration
	data.score_data = _collect_score_data()
	data.hints_used = hint_panel.hints_used
	data.creative_projects = _collect_creative_projects()
	return data


func _collect_creative_projects() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if studio == null:
		return out
	for entry in studio.projects:
		out.append({"name": str(entry.get("name", ""))})
	return out


func _collect_scene_objects() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for object_id in world.all_objects():
		var data := world.get_object(object_id)
		out.append({
			"id": object_id,
			"category": str(data.get("category", "")),
			"asset_id": str(data.get("asset_id", "")),
			"position": data.get("position", Vector3.ZERO),
			"rotation_degrees": data.get("rotation_degrees", Vector3.ZERO),
			"scale": data.get("scale", Vector3.ONE),
			"visible": bool(data.get("visible", false)),
			"depth": float(data.get("depth", 0.0)),
			"layer": int(data.get("layer", 0)),
		})
	return out


func _collect_camera_data() -> Dictionary:
	var cam := camera.camera()
	if cam == null:
		return {}
	return {
		"position": cam.position,
		"rotation_degrees": cam.rotation_degrees,
		"fov": cam.fov,
	}


func _collect_lighting_data() -> Dictionary:
	return {"lights": lighting.all_lights()}


func _collect_frames() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for frame in frames.frames:
		out.append({
			"texture": "" if frame.texture == null else frame.texture.resource_path,
			"duration": frame.duration,
			"pose_name": frame.pose_name,
			"notes": frame.notes,
		})
	return out


func _collect_keyframes() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for kf in keyframes.keyframes:
		out.append({
			"time": kf.time,
			"target_id": kf.target_id,
			"target_type": kf.target_type,
			"property_path": kf.property_path,
			"value": kf.value,
			"interpolation": kf.interpolation,
		})
	return out


func _collect_score_data() -> Dictionary:
	if last_score == null:
		return {}
	return {
		"total": last_score.total_score,
		"story": last_score.story_score,
		"staging": last_score.staging_score,
		"camera": last_score.camera_score,
		"lighting": last_score.lighting_score,
		"frame": last_score.frame_animation_score,
		"keyframe": last_score.keyframe_score,
		"timing": last_score.timing_score,
		"technical": last_score.technical_score,
		"creativity": last_score.creativity_score,
	}


## Task 17 hotkeys (spec §8): Space toggles preview playback, Right/Left step
## one frame, Escape exits the lab. Task 4 adds Ctrl+Z (undo), Ctrl+Y and
## Ctrl+Shift+Z (redo). Space routes through _on_play_toggled so it behaves
## exactly like the Play button. Focused GUI controls consume their own keys
## first (a LineEdit swallows Space/arrows AND its own Ctrl+Z text undo), so
## no focus guard is needed here.
func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_SPACE:
			_on_play_toggled()
			get_viewport().set_input_as_handled()
		KEY_RIGHT, KEY_LEFT:
			var dir := 1.0 if key.keycode == KEY_RIGHT else -1.0
			timeline.scrub(dir / float(timeline.fps))
			get_viewport().set_input_as_handled()
		KEY_Z, KEY_Y:
			if not key.ctrl_pressed:
				return
			var redo_key := key.keycode == KEY_Y or key.shift_pressed
			if redo_key:
				world.redo()
			else:
				world.undo()
			get_viewport().set_input_as_handled()
		KEY_ESCAPE:
			exit_lab()
			get_viewport().set_input_as_handled()


## Task 17 audio (spec §8): the lab's own background track, looped by
## connecting finished -> play() directly (no autoload dependency). No
## hard-coded missing asset: listeners stay off when MUSIC_PATH is absent.
func _setup_audio() -> void:
	if ResourceLoader.exists(MUSIC_PATH):
		music_player.stream = load(MUSIC_PATH)
		music_player.finished.connect(_on_music_finished)
		music_player.play()


func _on_music_finished() -> void:
	music_player.play()


## Best-effort SFX: play the first candidate that exists on disk; otherwise
## stay silent. Never an error path (spec §8).
func _play_sfx_optional(candidates: Array[String]) -> void:
	for path in candidates:
		if ResourceLoader.exists(path):
			sfx_player.stream = load(path)
			sfx_player.play()
			return


func exit_lab() -> void:
	lab_closed.emit()
	SceneTransition.change_scene(fallback_scene)