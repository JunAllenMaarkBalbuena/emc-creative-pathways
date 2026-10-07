# Design — 2.5D Animation Production Lab (4th minigame)

> Date: 2026-10-07 · Status: **draft for review**
> Requirement source: the EMC Simulator 2.5D Animation Production Lab brief (user spec, 2026-10-07).
> This document records **decisions and architecture**. It is the contract the implementation plan builds against.

## 0. Decisions (settled before design)

| # | Decision | Choice |
|---|---|---|
| D1 | Plan scope | One architecture spec + phased implementation plan; independent vertical slice first |
| D2 | Integration point | Main-menu tool lab entry (like Programming / Illustration / Modeling); world 5-door chain and its Animation Studio terminal level untouched |
| D3 | Animation engine | **Custom resource-based timeline** (single clock driving a frame channel + keyframe channels); no AnimationPlayer/SpriteFrames dependency |
| D4 | EMC Asset Library | New lightweight **adapter, read-only** on illustration-lab user data (`user://exports/*.png`, `user://drawings/*.tres`) + built-in starter assets under `res://data/asset_library/`; no changes to the illustration lab |
| D5 | 3D props | Project convention already established: **primitives + StandardMaterial3D** (no imported models exist in the tree; none needed) |
| D6 | 2.5D characters | `Sprite3D` (billboard) whose texture is driven by the timeline frame channel; same billboard pattern the player `AnimatedSprite3D` already uses |

## 1. Purpose and scope

A fourth production-tool minigame: a 2.5D Animation Production Lab teaching the
animation production workflow (brief → plan → assets → staging → camera →
lighting → frames → keyframes → timing → preview → submit → score), followed by
an unlocked Creative Studio mode.

**Independence contract** (non-negotiable, from the brief):

- Must boot and run with **built-in starter assets only**; must not depend on
  previous-lab scenes, scripts, or UI; previous-lab data is optional input.
- Must still function if `user://exports/` or `user://drawings/` are empty.
- Reuses only shared scaffolding: `LevelProgression` (completion status reads),
  `SceneTransition` (scene changes), `SettingsManager` (settings read), the
  per-lab save-file convention, and the test-harness convention.
- Previous-lab completion is read through `LevelProgression.is_level_completed(id)`
  inside a `has_method`-style safe check; missing data never blocks the lab.

## 2. Architecture

### 2.1 Scene tree

`scenes/animation_production_lab/animation_production_lab.tscn` — root `CanvasLayer`
(the established tool-lab root type).

```
AnimationProductionLab (CanvasLayer)        ← scripts/animation_production_lab/animation_production_lab.gd
│   (class_name AnimationProductionLab, signal lab_closed, fallback_scene)
│
├── Systems (plain Node children; controllers)
│   ├── AssetLibrary       (RefCounted, owned by root)   # adapter + starter fallback (emc_asset_library.gd)
│   ├── WorldController    (world_controller.gd)          # place/select/move/rotate/scale/
│   │                                                      #   depth/layer/visibility/reset/duplicate
│   ├── CameraController   (camera_controller.gd)         # camera transform, FOV, reset, framing
│   ├── LightingController (lighting_controller.gd)       # add/select/move/intensity/color/shadows
│   ├── TimelineController (timeline_controller.gd)       # clock, FPS, duration, loop, playhead
│   ├── FrameController    (frame_controller.gd)          # frame list: add/remove/dup/reorder/insert
│   ├── KeyframeController (keyframe_controller.gd)       # keyframe tracks on objects/camera/lights
│   ├── PreviewController  (preview_controller.gd)        # animates World from timeline state;
│   │                                                      #   review checklist
│   ├── AssignmentManager  (assignment_manager.gd)        # guided stage machine (data-driven)
│   ├── ScoringController  (scoring_controller.gd)        # measurable requirements → score
│   ├── SaveController     (RefCounted, owned by root)   # FileManager-style .tres → user://animation_lab/
│   └── CreativeStudioController (creative_studio_controller.gd)  # projects CRUD
│
├── UI (separate Control scenes under scenes/animation_production_lab/ui/)
│   ├── TopBar           # lab title, mode, save, help, exit
│   ├── AssignmentPanel  # brief: title, story, requirements, expected length/FPS
│   ├── StoryboardPanel  # plan stage: begin/middle/end ordering + position markers
│   ├── AssetLibraryPanel# browse carts; add/replace/remove items
│   ├── SceneViewport    # SubViewport rendering the World (2.5D view); owns World below
│   │   └── World (Node3D)   # panel-peers under UI, but CHILD of the SubViewport
│   │       ├── EnvironmentRoot            # floor, lab wall/backdrop placeholder, border
│   │       ├── BackgroundRoot             # layered Sprite3D backdrops (fore/mid/back depth)
│   │       ├── CharacterRoot              # placed 2D characters: Sprite3D (billboard) + transform
│   │       ├── PropRoot                   # MeshInstance3D primitives + StandardMaterial3D
│   │       ├── CameraRig (Camera3D)       # perspective; position/rotation/FOV editable
│   │       └── LightingRoot               # one DirectionalLight3D (key) + optional OmniLight3D
│   ├── InspectorPanel   # selected object properties (position/rot/scale/depth/layer/visible/…)
│   ├── TimelinePanel    # playhead, FPS, duration, frame/keyframe markers, play controls
│   ├── AnimationControls# play/pause/stop/loop/speed (used by TimelinePanel)
│   ├── HintPanel        # contextual hint text (from assignment data)
│   ├── TutorialOverlay  # skippable 12-step tutorial; reopenable from Help
│   ├── SubmissionPanel  # submit gate + review checklist
│   └── ScorePanel       # AnimationScoreData breakdown + educational feedback
│
└── Audio
    ├── MusicPlayer      # assets/sound/Level_4_Background_sound.mp3 (existing)
    ├── AmbiencePlayer   # soft loop (reuse existing asset if suitable, else silent)
    └── SFXPlayer        # button/click/success/error sounds (assets/sound/*)
```

`UI/SceneViewport` is a `SubViewport` (1280×720-scaled) rendering the World
node; the rest of the UI overlays it. This keeps 2.5D rendering isolated from
the `CanvasLayer` UI and gives the timeline/preview a stable viewport to drive.

### 2.2 Module responsibilities and communication

- **Signals up, calls down.** Controllers emit `changed`-family signals; the
  root and UI panels connect and update. No controller calls `get_node` into
  another controller's internals.
- **WorldController is the single owner of live scene objects.** Placement,
  selection, transforms, depth/layer ordering, visibility all go through it.
  PreviewController reads the same object list through WorldController to
  apply keyframes.
- **TimelineController owns time.** `step_time(delta)` (pure logic — no
  `_process` dependency) ticks the clock, advances the frame channel at FPS
  boundaries, and evaluates keyframe channels. PreviewController polls
  `TimelineController` state each step and applies it to the World.
- **AssignmentManager owns guided mode state.** Stages:
  `BRIEF → PLAN → ASSETS → STAGING → CAMERA → LIGHTING → FRAMES → KEYFRAME
  → TIMING → PREVIEW → SUBMIT`. It emits `stage_changed(stage)`; the root
  swaps the visible UI panel. Hints and the tutorial overlay are driven from
  this controller. Challenges A–F from the brief map onto stages:
  A sequencing → PLAN, B missing-frame → FRAMES, D add-keyframe → KEYFRAME,
  C FPS → TIMING, E stage-the-scene → STAGING, F logic/trigger ordering →
  KEYFRAME (event-order check: interaction pose keyframe after approach
  movement).
- **Creative Studio** is a second mode (enum on the root controller), not hot
  logic in the guided path. Studio projects reuse the same World + Timeline +
  Save pipeline with an empty assignment.

### 2.3 Data flow (trace)

Guided example — the player's stroke of the pipeline:

1. Root starts guided mode → `AssignmentManager.load_assignment(assignment_id)`
   reads an `AnimationAssignment` resource (`.tres`).
2. Stage `ASSETS`: player clicks an asset → the AssetLibrary adapter returns an
   `EMCAssetData` → root calls `WorldController.add_asset(data)` which spawns
   the matching node type (Sprite3D in CharacterRoot / BackgroundRoot, or
   primitive in PropRoot).
3. Stage `FRAMES`: player adds a frame → FrameController appends an
   `AnimationFrameData`, emits `frames_changed`.
4. Stage `KEYFRAME`: player moves the character then clicks "add keyframe" →
   KeyframeController records `AnimationKeyframeData(time, target,
   property_path, value)` for the selected object; TimelinePanel repaints
   markers.
5. `PREVIEW`/`SUBMIT`: ScoringController reads WorldController + Timeline +
   Assignment requirements → `AnimationScoreData` → SubmissionPanel → on
   submit the root calls `LevelProgression.complete_level(level_def)` and
   unlocks Creative Studio for future sessions via the lab save file.

## 3. Data model (scripts/animation_production_lab/data/)

All `class_name` Resources, mirroring the project's data-as-resource convention
(`DigitalArtData`, `ModelData`, `PuzzleSequence`…).

| Type | Fields (key ones) | Lives in |
|---|---|---|
| `AnimationAssignment` | `assignment_id`, `display_name`, `story_beats` (begin/middle/end strings), `required_categories` (PackedStringArray: char/bg/prop/camera/light), `min_frames`, `required_keyframes` (Array[Dictionary]: target+property), `target_fps`, `fps_tolerance`, `target_duration`, `final_pose_keyframe` (bool), `hints` (Array[String]), `review_checklist` (Array[{label, pass_check}]) | `res://data/assignments/animation/*.tres` |
| `AnimationFrameData` | `frame_index`, `texture` (Texture2D), `duration` (float), `pose_name`, `notes` | in-memory + save |
| `AnimationKeyframeData` | `time`, `target_id`, `target_type` (object/camera/light), `property_path` (String — NodePath re-parsed to `set()`), `value` (Variant), `interpolation` (enum: LINEAR/STEP) | in-memory + save |
| `EMCAssetData` | `asset_id`, `display_name`, `category`, `asset_type`, `source_lab` ("starter"\|"illustration"), `preview_texture`, `path` (res:// or user://), `metadata` | library listing |
| `AnimationLabSaveData` | `guided_completed`, `current_assignment_id`, `scene_objects` (Array[Dictionary]: type, asset_id, path, transform, depth, layer, visible), `camera_data`, `lighting_data`, `frames` (Array[Dictionary]), `keyframes` (Array[Dictionary]), `fps`, `duration`, `score_data`, `hints_used`, `creative_projects` (Array[Dictionary]) | `user://animation_lab/*.tres` |

Rationale: dictionaries inside the save `.tres` (not nested Resource refs)
keep the file robust to missing assets (broken `Resource` sub-refs are the
main corruption vector) — same defensive choice the brief demands (graceful
corruption/missing-data fallback).

### 3.1 EMC Asset Library adapter

- **Starter sources** (`res://data/asset_library/` — committed built-in assets):
  character frames copied from `assets/char_animation/idle|run/*.png`
  (frame-by-frame character), a backdrop from `assets/image/*.png`
  (e.g. `Menu_Bg_image.png` as placeholder lab backdrop), primitives for props.
  Stored as a small index of `EMCAssetData` resources (`data/asset_library/index.tres`).
- **Illustration-lab sources** (read-only, optional): scan
  `user://exports/*.png` (sprites/backgrounds/frames) and
  `user://drawings/*.tres` (DigitalArtData → flattened RGBA8 → preview). Any
  failure or missing dir → skipped silently, starter fallback stands in.
- The adapter is a `RefCounted` with `list(category) → Array[EMCAssetData]`,
  `get(id) → EMCAssetData|null`, `load_texture(data) → Texture2D|null`
  (missing file → null, never crash). UI and gameplay call only these.

## 4. Guided assignment and scoring

### 4.1 Stage machine

Data-driven stages in `AnimationAssignment`; each stage has required checks
evaluated live so the UI can show a progress checklist:

1. **BRIEF** — read the assignment (Continue button; teaches understanding).
2. **PLAN** — storyboard ordering: arrange 3 story beats (begin/middle/end) →
   Challenge A. Plus place 3 marker dots on a 2D strip (character start,
   prop location, final pose) → Challenge E planning half.
3. **ASSETS** — add the required character, background, prop from the library
   (challenge: pick the missing starter item from a shuffled set).
4. **STAGING** — move/scale/depth objects: character near the workstation
   prop, background behind, character in front → Challenge E staging half.
5. **CAMERA** — position/frame the shot (target: character+prop centered,
   distance within acceptable bounds) → measurable framing check.
6. **LIGHTING** — intensity above a floor, no pitch-black frame.
7. **FRAMES** — build the frame sequence; **Challenge B**: one frame is
   missing (choose/insert the correct one from 3 candidates).
8. **KEYFRAME** — add the required keyframes: character walks to the prop
   (position), then pose change (frame channel) → Challenge D + F (ordering:
   pose keyframe time > walk keyframe time).
9. **TIMING** — **Challenge C**: set FPS to the assignment target within
   tolerance; duration within limits.
10. **PREVIEW** — play once, tick the review checklist (10 items from the
    brief).
11. **SUBMIT** — gate: all required checks pass → score + feedback →
    `complete_level` → Creative Studio unlocked.

### 4.2 Scoring (measurable only)

| Category | Measure |
|---|---|
| Story & Sequence | storyboard order correct; begin/middle/end present |
| Scene Staging | required categories all present (null textures reduce the score); character before background, prop near the action (stage gate) |
| Asset Usage | required categories all present; no null textures |
| Camera Composition | position/distance within framing bounds at final keyframe |
| Lighting | intensity ≥ floor; key light exists |
| Frame Animation | frame count ≥ min; all frames have valid textures; ≥ 1 pose change |
| Keyframe Usage | required keyframes exist; ordering constraint satisfied |
| Timing & FPS | FPS within target ± tolerance; duration within limits |
| Technical Completion | animation plays with no missing/erroring resources; review checklist ≥ 7/10 |

`AnimationScoreData` (Resource, from the brief) holds the weighted subscores +
`total_score` + `feedback` (template sentences + condition-specific hints).
Scoring is **additive, non-punitive** — every check passes or fails into the
score; nothing is deducted for experiments. `hints_used` is recorded, not
penalized, in the guided pass.

## 5. Creative Studio

- Unlock: guided completion (flag in `AnimationLabSaveData`; resilient to
  `LevelProgression` data being reset, per the independence contract).
- Projects: new / save / load / rename / duplicate / delete (Array[Dictionary]
  in the save file). Each project points at frames, keyframes, scene objects,
  camera, lighting, FPS, duration.
- Empty assignment — no checks, no scoring; same World/Timeline/Save pipeline.
- Final-shot "showcase" export deferred (see §9).

## 6. Save / load

`SaveController` (RefCounted, FileManager-clone conventions):

- Dir `user://animation_lab/`; files `guided.tres` (AnimationLabSaveData) and
  `projects/<sanitized_name>.tres` (per-project AnimationLabSaveData).
- Safe load: missing file → defaults; parse failure or wrong type → defaults
  + one console warning (never crash); `_sanitize_filename` reuses the
  established alphanumeric+underscore rule.
- Autosave toggle (`@export autosave_enabled`) — save on stage crosses in
  guided mode and on studio actions.

## 7. Integration

- **Main menu** (`scripts/menu/main_menu.gd`): add
  `@export_file("*.tscn") var animation_production_lab_path` + a menu entry
  button next to the other three tool labs.
- **LevelDef**: `data/levels/animation_production_lab.tres`
  (`level_id = "animation_production_lab"`, `starts_unlocked = true`,
  `reward_condition_ids = ["animation_production_lab_complete"]`,
  completion message per convention). Not part of the 5-door sequence chain.
- **Exit**: `lab_closed` → `LevelProgression.complete_level(level_def)` on
  guided completion milestone → `SceneTransition` or `change_scene_to_file`
  back to `fallback_scene` (main menu) — identical to the other tool labs.
- **Settings**: read `SettingsManager` for volume/UI-scale where the existing
  labs do (audio buses are already global).
- **Audio**: `assets/sound/Level_4_Background_sound.mp3` exists — use as the
  lab BGM; `assets/sound/main_menu_Background_sound.mp3` style looping via the
  existing `loop_audio.gd` pattern.

## 8. Input, accessibility, performance

- Primary input is UI-driven (buttons/sliders/drag) so mouse, keyboard, touch
  and Android all work through the same controls; keyboard shortcuts call the
  same controller methods (`Space` play/pause, arrows frame step, `Esc` back)
  via `_unhandled_input` on the root.
- Touch: buttons ≥ existing lab control sizes; timeline rows are tap targets,
  not pixel-precise handles.
- No per-frame allocation in the timeline tick (frame evaluation reuses a
  scratch texture ref / transform dict); the SubViewport renders only while
  the lab is open; lighting limited to 1 directional + at most 1 omni
  (GL Compatibility budget).
- `@export`s on the root for: `default_fps = 12`, `default_duration = 5.0`,
  `max_duration = 30.0`, `fps_min = 1`, `fps_max = 60`,
  `allow_custom_assets = true`, `enable_hints = true`, `enable_scoring = true`,
  `enable_creative_studio = true`, `autosave_enabled = true` (all Inspector-facing).

## 9. Out of scope (deferred)

- YouTube/gif "export or showcase" output (studio showcase) — later phase.
- `AnimationTree` blending, easing-curve editors, multi-layer frame onion
  skinning — not needed for the educational slice.
- Web/mobile-specific build work beyond the touch conventions above.
- Changing the world's Animation Studio terminal level or its cutscene/Carl.

## 10. Implementation phases (plan outline)

The implementation plan (writing-plans) sequences these; phases are gated by
the full test gate after each:

1. **Vertical slice** — scene boots independent headless; World + starter
   assets + place/select/move/reset; SubViewport preview; exit wiring.
2. **Asset library** — adapter + starter index + read-only illustration scan.
3. **Staging/camera/lighting** — transforms, depth/layers, camera rig, lights,
   Inspector panel.
4. **Animation systems** — timeline clock, frame channel, keyframe channel,
   FPS/duration/loop, timeline UI, preview.
5. **Guided assignment** — assignment resources, stage machine, challenges,
   hints, tutorial, review checklist, submission, scoring, complete_level.
6. **Save + Creative Studio** — save/load, studio unlock, project CRUD,
   autosave.
7. **Polish + full gate** — input shortcuts, audio, accessibility,
   performance pass, full gate green.

## 11. Testing strategy

Headless harness tests (existing `PASS:`/`FAIL:` `.gd`/`.tscn` convention in
`tests/`, discovered by `tools/verify-project.ps1`), written TDD per phase:

- `test_animation_timeline.gd` — clock determinism (`step_time`), frame
  channel at FPS boundaries, FPS/duration validation, loop, keyframe
  interpolation (linear + step), invalid input rejection.
- `test_animation_world.gd` — place/select/move/rotate/scale/reset/duplicate,
  depth/layer ordering, visibility.
- `test_animation_asset_library.gd` — starter index present; adapter safe on
  empty/missing `user://` data; missing texture → null, no crash.
- `test_animation_save.gd` — guided + project save/load round-trip; corrupt /
  truncated file falls back to defaults.
- `test_animation_assignment.gd` — stage progression gating, challenge
  checks, scoring measures per category.
- `test_animation_independence.tscn` — lab boots headless with no
  illustration exports present; starter fallback used; gate-able launch.
- `test_animation_menu_integration.gd` — main_menu exposes the new lab path
  (path export non-empty / button wired).

Full gate after every phase: `tools/verify-project.ps1` clean (no new
failures; known-flaky sweep unchanged).

## 12. Starter asset inventory (verified to exist)

- Frame-by-frame 2D character: `assets/char_animation/idle/*.png` (~24),
  `assets/char_animation/run/*.png` (~24) — copied to
  `res://data/asset_library/character/` as named frames.
- Background: `assets/Scene_BG/Menu_Bg_image.png` (+ portraits available).
- 3D prop: generated primitives (`BoxMesh`/`CylinderMesh` workstation + screen
  per lab-theme), `StandardMaterial3D` per convention.
- BGM: `assets/sound/Level_4_Background_sound.mp3`.

## 13. Appendix — studio round design/fork record (added 2026-10-07)

### 13.1 Composition ordering: fork resolved to B2 (transparent-pass priority)

The revised 2.5D composition (§35) listed "composition depth plane" as a
candidate for ordering. It was never viable: Godot 3D sorts opaque objects by
z-depth and transparents by `(render_priority, z)`, so spatial z cannot decide
layer order between two objects on the same plane (background + character share
a plane; the player's own `depth` slider is spatial, not compositional). The
design phase therefore forked:

- **A — composition depth plane**: push selected layers onto their own z-band.
  Rejected: z already carries the player's spatial depth; hijacking it for
  ordering breaks the spatial slider and fights the camera at every angle.
- **B2 — transparent-pass render priority**: every layer renders through the
  transparent pass with `render_priority = STARTER_PRIORITY + (layer_index + 1)
  × 16` (monotonic in the stack; `RenderOrder`, `render_order.gd`). `node.position`
  stays pure. Chosen and implemented.

B2 probe evidence (windowed pixel probe, Task 1, recorded in the round ledger):
with equal z, the sprite holding the higher `render_priority` draws on top —
the pixel signature flips when the two priorities swap. Two implementation
facts surfaced by the probe: `SpriteBase3D` carries `render_priority` on the
instance, but `MeshInstance3D` does **not** — meshes must carry priority on a
transparent material instead (`material_override` → surface override →
authored surface material, duplicated so a shared authored starter material is
never mutated, forced `TRANSPARENCY_ALPHA`, priority on the duplicate).
`STARTER_PRIORITY` pins the fixed starter-scene nodes below every player layer
and player duplicates can never collide with them. Accepted trade-off: every
layer mesh gets a duplicated material (refcounted; churn per priorities pass,
no leak) and alpha blending of fully-opaque colors is visually identical.
Revisit B2 if transparent-pass overdraw is measured costly at scale.

### 13.2 Layers docker behavior (Task 5, `layers_panel.gd`)

- The docker is a **driver, not a mirror**: every interaction (select, reorder
  via row buttons/keyboard, add/duplicate/rename/delete, eye/lock) emits a
  typed signal the lab root routes into `WorldController`. It re-renders only
  from `world.layer_summaries()` pushes.
- Rows read `display_name — element_type` (`2D`/`3D`), toggle on select.
- Keyboard (`[`/`]` step order, `H` hide, `L` lock) uses the root's
  `_unhandled_input` pattern with echo/focus guards; a focused `LineEdit`
  swallows its keys first so typing still works.
- Rebuilds `free()` old rows (not `queue_free()`) deliberately: `set_layers`
  runs during `objects_changed` emission and the structural tests count rows in
  the same frame.

### 13.3 Docked layout + guided vs studio visibility (Task 6)

- Four dockers share the shell: Layers (anchored 0..0.45), Inspector
  (0.55..1.0), Asset Library, Timeline (top 0.55). Two 6px `DockResizeStrip`
  dividers resize the free edges (Layers right edge; timeline top edge) via
  pixel offsets clamped to `>= 120px` and inside the window; offsets — not
  anchor fractions — so the authored anchor layout and a docker's neighbours
  are untouched, and the strip re-glues itself to the moved edge. Drag-dock is
  deferred.
- Guided mode: the stage map is the **sole** docker driver; the TopBar has no
  undo/redo and no dock toggles. Studio mode: TopBar shows 4 CheckButtons
  (Layers/Inspector/Assets/Timeline → `dock_toggle_requested(name, visible)`);
  toggling a docker off hides it and its companion strip.

### 13.4 Undo/redo (Task 4) and save shape (Task 7)

- `EditorHistory` (RefCounted): two-stack linear history of undo/redo closure
  pairs; any fresh push drops the redo stack; `clear()` runs at the end of
  `_apply_project_data` so a project load never lets stale undo resurrect the
  rebuilt world (Review-Focus #3).
- Save shape: `layer_order: Array[String]` (the scene-object ids back-to-front
  from `world.layer_order()`) plus `display_name`/`element_type`/`locked` on
  each `scene_objects` entry. On load, old ids map to regenerated ids by the
  entry's traversal index; the reorder pass runs **before** locks are applied
  (`reorder_layer` refuses locked layers); `_apply_layer_priorities()` re-syncs
  after. Back-compat without a version bump (Review-Focus #4): a save written
  before this round has no `layer_order` (defaults empty → add order IS the
  insertion order) and no new entry keys (asset names kept, layers unlocked).