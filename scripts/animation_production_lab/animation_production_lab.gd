class_name AnimationProductionLab
extends CanvasLayer

## Root of the 2.5D Animation Production Lab (4th EMC Simulator tool lab).
## Holds the World (Node3D under UI/SceneViewport) and the Systems/UI
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
const TimelinePanelScript := preload("res://scripts/animation_production_lab/ui/timeline_panel.gd")
const AnimationControlsScript := preload("res://scripts/animation_production_lab/ui/animation_controls.gd")
const HintPanelScript := preload("res://scripts/animation_production_lab/ui/hint_panel.gd")
const TutorialOverlayScript := preload("res://scripts/animation_production_lab/ui/tutorial_overlay.gd")
const SubmissionPanelScript := preload("res://scripts/animation_production_lab/ui/submission_panel.gd")
const ScorePanelScript := preload("res://scripts/animation_production_lab/ui/score_panel.gd")

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

# Read-only EMC asset adapter (RefCounted; booted with committed assets).
var library := EMCAssetLibrary.new()

# Guided-mode panels (instanced under UI).
@onready var top_bar: TopBarPanel = $UI/TopBar
@onready var assignment_panel: AssignmentPanelScript = $UI/AssignmentPanel
@onready var storyboard_panel: StoryboardPanelScript = $UI/StoryboardPanel
@onready var asset_library_panel: AssetLibraryPanelScript = $UI/AssetLibraryPanel
@onready var inspector_panel: InspectorPanelScript = $UI/InspectorPanel
@onready var timeline_panel: TimelinePanelScript = $UI/TimelinePanel
@onready var animation_controls: AnimationControlsScript = $UI/AnimationControls
@onready var hint_panel: HintPanelScript = $UI/HintPanel
@onready var tutorial_overlay: TutorialOverlayScript = $UI/TutorialOverlay
@onready var submission_panel: SubmissionPanelScript = $UI/SubmissionPanel
@onready var score_panel: ScorePanelScript = $UI/ScorePanel

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
	_wire_panels()
	if autosave_enabled:
		save_controller = SaveController.new()
	assignment_manager.stage_changed.connect(on_stage_changed)
	assignment_manager.stage_changed.connect(_autosave_stage_changed)
	assignment_manager.assignment_loaded.connect(_on_assignment_loaded)
	world.objects_changed.connect(_on_objects_changed)
	library.refresh()
	assignment_manager.load_assignment(DEFAULT_ASSIGNMENT)
	top_bar.set_mode_label("GUIDED")
	on_stage_changed(assignment_manager.current_stage())


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
		"UI/SceneViewport/World/LightingRoot/StarterKeyLight") as DirectionalLight3D
	var omni := get_node_or_null(
		"UI/SceneViewport/World/LightingRoot/StarterFillLight") as OmniLight3D
	if dir != null:
		lighting.register_existing("starter_key", dir)
	if omni != null:
		lighting.register_existing("starter_fill", omni)


func _wire_panels() -> void:
	top_bar.exit_requested.connect(exit_lab)
	assignment_panel.brief_acknowledged.connect(_on_brief_acknowledged)
	storyboard_panel.order_submitted.connect(_on_order_submitted)
	asset_library_panel.add_requested.connect(_on_asset_add_requested)
	inspector_panel.object_selected.connect(_on_inspector_object_selected)
	inspector_panel.transform_edited.connect(_on_inspector_transform_edited)
	inspector_panel.visibility_toggled.connect(_on_inspector_visibility_toggled)
	inspector_panel.delete_requested.connect(_on_inspector_delete)
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


## Stage -> panel visibility map. One panel (plus the persistent top bar) is
## visible per stage. score_panel is independent — shown only by submitting.
func show_stage_ui(stage: int) -> void:
	score_panel.hide()
	assignment_panel.visible = stage == STAGE_BRIEF
	storyboard_panel.visible = stage == STAGE_PLAN
	asset_library_panel.visible = stage == STAGE_ASSETS
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
	_refresh_visible_panel_data(stage)
	if stage == STAGE_PREVIEW:
		preview.evaluate_review()
		_previewing = true
	else:
		_previewing = false
	if enable_hints:
		hint_panel.set_hints(assignment_manager.hints_for_stage())


func _refresh_visible_panel_data(stage: int) -> void:
	if stage == STAGE_ASSETS:
		asset_library_panel.set_assets(library.list())
	elif stage >= STAGE_STAGING and stage <= STAGE_LIGHTING:
		inspector_panel.set_object_list(_object_summaries())
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


func _on_objects_changed() -> void:
	if inspector_panel.visible:
		inspector_panel.set_object_list(_object_summaries())


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
		return
	preview.evaluate_review()
	if not enable_scoring:
		_complete_guided_flow()
		return
	last_score = scoring.score(
		assignment_manager.story_order_correct,
		assignment_manager.assignment,
		world, camera, lighting, frames, keyframes, timeline,
		preview.review_checklist,
	)
	score_panel.show_score(last_score)
	_complete_guided_flow()


func _complete_guided_flow() -> void:
	guided_completed = true
	var level := load(LEVEL_PATH) as LevelDefinition
	if level != null and not LevelProgression.is_level_completed(level.level_id):
		LevelProgression.complete_level(level)
	guided_flow_completed.emit()


## Keep the SUBMIT checklist live without rebuilding rows every frame.
func _refresh_submission() -> void:
	submission_panel.set_requirements(assignment_manager.stage_requirements())


## Creative Studio unlock gate (spec §5): only after the guided run is
## submitted does the studio open; the flag survives a reboot (Task 15).
func unlock_creative_studio() -> void:
	if not guided_completed or not enable_creative_studio:
		return
	if mode == Mode.STUDIO:
		return
	mode = Mode.STUDIO
	top_bar.set_mode_label("STUDIO")
	score_panel.hide()


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
	data.creative_projects = []
	return data


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


func exit_lab() -> void:
	lab_closed.emit()
	SceneTransition.change_scene(fallback_scene)