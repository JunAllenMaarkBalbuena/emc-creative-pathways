# 2.5D Animation Production Lab — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the fourth EMC Simulator minigame — an independent 2.5D Animation Production Lab (guided animation assignment + Creative Studio) that reuses only shared scaffolding and never touches the other labs or the world.

**Architecture:** A `CanvasLayer`-root lab scene (the existing tool-lab pattern) whose `Node3D` World renders inside a `SubViewport`. Controllers are plain `Node`/`RefCounted` classes under `AnimationProductionLab` / `Systems`, communicating signals-up / calls-down. A single custom clock (`TimelineController.step_time`) drives a frame channel (Sprite3D texture swaps) and keyframe channels (linear/step property interpolation); all logic is pure enough to test headless with `--script` tests.

**Tech Stack:** Godot 4.7.2 (GL Compatibility), GDScript only, Resources for data (`.tres`), `DirAccess`/`ResourceLoader`/`ResourceSaver` for user data, existing `verify-project.ps1` gate.

**Spec:** `docs/superpowers/specs/2026-10-07-animation-production-lab-design.md`

## Global Constraints

- Godot **4.7.2 stable**, GL Compatibility renderer, **GDScript only** — no C# anywhere.
- Viewport **1280×720**, stretch `canvas_items`, aspect `expand`.
- Autoloads are fixed: `LevelProgression`, `SettingsManager`, `SceneTransition` (+ `_mcp_game_helper`). **Add no autoloads.**
- **Only two pre-existing files may be modified**: `scripts/menu/main_menu.gd` and `scenes/main_menu.tscn` (one `@export` + one Button + one handler). The world chain, the Animation Studio terminal level, and the three other labs must remain byte-identical — do not open them for editing.
- New files live under `scenes/animation_production_lab/`, `scripts/animation_production_lab/`, `data/levels/`, `data/assignments/animation/`, `tests/`.
- `.tres` resource files follow the existing header convention (`database/levels/digital_art_lab.tres` as the template: `[gd_resource type="Resource" script_class="LevelDefinition" load_steps=2 format=3]` + `[ext_resource type="Script" path="res://scripts/level_definition.gd" ...]`).
- Filenames sanitized to `[A-Za-z0-9_]` + `_` for spaces (existing `FileManager._sanitize_filename` rule).
- Tests print `PASS:`/`FAIL:` markers; pure-logic tests are SceneTree `--script` (`.gd` with `extends SceneTree`), scene tests are `.tscn` harnesses (root script `extends Node`). Single-test runs: `powershell -ExecutionPolicy Bypass -File tools\verify-project.ps1 -Only <name>`.
- The full gate after each task must stay green: `... verify-project.ps1` (known-flaky `test_full_lab_sweep.gd` stays WARN, not FAIL).
- PowerShell 5: no `&&`; commit messages written via `[System.IO.File]::WriteAllText(path, msg, (New-Object System.Text.UTF8Encoding($false)))` + `git commit -F path`; commit **by explicit path** (`git add <paths>`, never `git add -A`).
- Saves live under `user://animation_lab/`; `SaveController.base_dir` and `EMCAssetLibrary`'s user-root list are injectable so tests never touch real user data.
- **Deviation from spec §3.1/§12 (declared, not silent):** starter assets are referenced **in place** (`res://assets/char_animation/...`, `res://assets/Scene_BG/Menu_Bg_image.png`), not copied to `res://data/asset_library/`. They are committed files already; copying would duplicate art. The built-in starter index is code-built constants + `DirAccess` listing, not a hand-authored `index.tres`.

## Review Focus

Inputs the spec implies but no task's tests might otherwise exercise, with the test pinning each line:

1. **`user://exports/` and `user://drawings/` missing or empty** → adapter lists starter-only results, never errors, never crashes. → Task 4 (`test_animation_asset_library.gd`, missing-dir cases).
2. **`EMCAssetData.path` points at a file that does not exist** → `load_texture()` returns `null`, previews show a placeholder, scoring counts the asset as missing; never a hard error. → Task 4 + Task 12 (null-texture scoring case).
3. **FPS/duration inputs out of range** (`0`, `-5`, `999`) → clamped to `[fps_min, fps_max]` and `[1ms, max_duration]`, setters return `false` for invalid input. → Task 8 (`test_animation_timeline.gd`, range cases).
4. **A keyframe/saved object references a target that no longer exists** (object deleted or absent after load) → evaluation skips the target silently; save/load round-trip keeps no dangling crash. → Task 9 + Task 15 (orphan cases).
5. **Hand-edited save holds the wrong types** (`1` instead of `true`, missing keys, a string where a float is expected) → per-key fallback to defaults, one warning, no hard-fail (mirror the untyped-dictionary pattern of `LevelProgression._load_progress()`). → Task 15 (`test_animation_save.gd`, tainted-file case).

---

### Task 1: Level definition + main-menu entry

**Files:**
- Create: `data/levels/animation_production_lab.tres`
- Modify: `scripts/menu/main_menu.gd` (add export + handler), `scenes/main_menu.tscn` (add one `Button` named `AnimButton` beside `ModelButton`, matching its style/anchors, `text` "Animation Lab")
- Test: `tests/test_animation_level_setup.gd` (SceneTree), `tests/test_animation_menu_integration.tscn` (scene harness)

**Interfaces:**
- Consumes: `LevelDefinition` (scripts/level_definition.gd), `MainMenu` (scripts/menu/main_menu.gd), `SceneTransition`, `Platform` (from `addons/`)
- Produces: `data/levels/animation_production_lab.tres` — `level_id = "animation_production_lab"`, `display_name = "2.5D Animation Production Lab"`, `description = "Plan, stage, and animate a short 2.5D scene."`, `starts_unlocked = true`, `next_level_id = ""`, `reward_condition_ids = PackedStringArray("animation_production_lab_complete")`, `completion_message = "Animation Production Lab Completed!"`

- [ ] **Step 1: Write the failing test** — `tests/test_animation_level_setup.gd` (`extends SceneTree`, `_init()` runs sync assertions, prints `PASS:`/`FAIL:` and `quit(0|1)`):

```gdscript
func _init() -> void:
	var lvl := load("res://data/levels/animation_production_lab.tres") as LevelDefinition
	if lvl == null or lvl.level_id != "animation_production_lab" \
		or not lvl.starts_unlocked \
		or lvl.reward_condition_ids.size() != 1 \
		or lvl.reward_condition_ids[0] != "animation_production_lab_complete":
		print("FAIL: animation level definition missing or misconfigured")
		quit(1)
		return
	print("PASS: animation_production_lab LevelDefinition is configured")
	quit(0)
```

- [ ] **Step 2: Run test to verify it fails** — `tools\verify-project.ps1 -Only test_animation_level_setup.gd` → the `.tres` doesn't exist yet; expect FAIL (load returns null).
- [ ] **Step 3: Create `data/levels/animation_production_lab.tres`** — header + the six fields from Produces (copy the structure of `data/levels/digital_art_lab.tres`).
- [ ] **Step 4: Run test to verify it passes** — expect `PASS: animation_production_lab LevelDefinition is configured`, summary `1 pass, 0 fail`.
- [ ] **Step 5: Write the failing menu test** — `tests/test_animation_menu_integration.tscn` (root `Node` + script `extends Node`): instantiate `res://scenes/main_menu.tscn`, `add_child`, `await get_tree().process_frame`, then assert all of: `main.get_node("AnimButton") != null`; `main.animation_production_lab_path.ends_with("animation_production_lab.tscn")`; `FileAccess.file_exists(main.animation_production_lab_path)`; `main.get_node("AnimButton").visible`. Print `PASS: main menu exposes the animation lab entry` (`quit(0)`) or `FAIL:` + `quit(1)`.
- [ ] **Step 6: Run it to verify it fails** — expect the harness to print no PASS (AnimButton missing).
- [ ] **Step 7: Wire the menu** — in `scripts/menu/main_menu.gd`: add `@export_file("*.tscn") var animation_production_lab_path := "res://scenes/animation_production_lab/animation_production_lab.tscn"`, `@onready var anim_button: Button = $AnimButton`, connect `anim_button.pressed` in `_ready()` (guard `if anim_button:` like the other optional buttons), and add `func _on_anim_pressed() -> void: SceneTransition.change_scene(animation_production_lab_path)`. In `scenes/main_menu.tscn` add the `AnimButton` `Control`-`Button` child mirroring `ModelButton`'s anchors/theme, text "Animation Lab".
- [ ] **Step 8: Run both tests to verify they pass** — `-Only test_animation_menu_integration.tscn` and `-Only test_animation_level_setup.gd`.
- [ ] **Step 9: Commit** — `git add data/levels/animation_production_lab.tres scripts/menu/main_menu.gd scenes/main_menu.tscn tests/test_animation_level_setup.gd tests/test_animation_menu_integration.tscn tests/test_animation_menu_integration.gd; git commit -F <msgfile>` (msg: `feat(animation-lab): level definition and main-menu entry`).

---

### Task 2: Independent lab scene skeleton (vertical slice — boots)

**Files:**
- Create: `scenes/animation_production_lab/animation_production_lab.tscn`, `scripts/animation_production_lab/animation_production_lab.gd`
- Test: `tests/test_animation_independence.tscn` (scene harness)

**Interfaces:**
- Consumes: `SceneTransition`, `LevelProgression`, `SettingsManager`
- Produces: `class_name AnimationProductionLab extends CanvasLayer` with:
  - `signal lab_closed`
  - `@export_file("*.tscn") var fallback_scene := "res://scenes/main_menu.tscn"`
  - `@export var default_fps := 12`, `@export var default_duration := 5.0`, `@export var max_duration := 30.0`, `@export var fps_min := 1`, `@export var fps_max := 60`, `@export var allow_custom_assets := true`, `@export var enable_hints := true`, `@export var enable_scoring := true`, `@export var enable_creative_studio := true`, `@export var autosave_enabled := true` (Inspector-facing, values from spec §8)
  - `func exit_lab() -> void` — emits `lab_closed`, then `SceneTransition.change_scene(fallback_scene)`

- [ ] **Step 1: Write the failing test** — `tests/test_animation_independence.tscn`: instantiate `res://scenes/animation_production_lab/animation_production_lab.tscn`, `add_child`, `await get_tree().process_frame`, assert: root script is `AnimationProductionLab`; `get_node("UI/SceneViewport")` exists and `UI/SceneViewport/World` is a `Node3D` with a `Camera3D` descendant; `UI/SceneViewport/World/CharacterRoot` has ≥ 1 child with a non-null `Sprite3D.texture`; `PropRoot` has ≥ 1 `MeshInstance3D`; there is ≥ 1 `Node3D` of class `DirectionalLight3D` or `OmniLight3D` in `LightingRoot`. Print `PASS: animation lab boots independently with starter world` / `FAIL:` + cause. (Script `extends Node`; use `print(_fail_reason)` before `quit(1)`.)
- [ ] **Step 2: Run to verify it fails** — scene path doesn't exist; harness reports FAIL.
- [ ] **Step 3: Build `scenes/animation_production_lab/animation_production_lab.tscn`** per spec §2.1 exactly: root `CanvasLayer` with the script; child `Systems` (empty `Node` for now, controllers arrive in later tasks); child `UI` containing a `Control`-anchored `SceneViewport` (`SubViewport` `size = Vector2i(1280, 720)`, `render_target_update_mode = 2`, `own_world_3d = true`? — **no**: leave default world; the World lives inside the SubViewport) whose child is `World` (`Node3D`) with `EnvironmentRoot`, `BackgroundRoot`, `CharacterRoot`, `PropRoot` (all `Node3D`), `CameraRig` (`Camera3D`, `current = true`, `position = Vector3(0, 0.8, 4)`, `fov = 60`), `LightingRoot` (one `DirectionalLight3D` `rotation` pitched ~ -45° toward the origin, energy 1.0, **no shadows in GL-Compat budget**; one `OmniLight3D` disabled by default). Child `Audio` with three `AudioStreamPlayer` named `MusicPlayer`, `AmbiencePlayer`, `SFXPlayer` (no streams yet). Starter content in `World`: one `Sprite3D` in `CharacterRoot` with `texture = preload` of the first sorted `res://assets/char_animation/idle/` PNG, `billboard = BaseMaterial3D.BILLBOARD_ENABLED`, `position = Vector3(0, 0.5, 0)`, `pixel_size = 0.01`; one `Sprite3D` in `BackgroundRoot` with `texture = preload("res://assets/Scene_BG/Menu_Bg_image.png")`, `position = Vector3(0, 1, -6)`, `pixel_size = 0.02`; one `MeshInstance3D` in `PropRoot` — `BoxMesh` `size = Vector3(0.8, 0.9, 0.6)`, `StandardMaterial3D` `albedo_color = Color(0.35, 0.45, 0.6)`, `position = Vector3(1.2, 0.45, 0)` — the starter workstation.
  - `scripts/animation_production_lab/animation_production_lab.gd`: the class header + exports + `exit_lab()`, plus `_ready()` keeping `Audio` players silent unless `SettingsManager` says otherwise (read-only: it already drives global buses; nothing to do beyond defaults). Because the first `.tres`/scene add `.uid` files, commit them too.
- [ ] **Step 4: Run to verify the scene boots** — `-Only test_animation_independence.tscn` → PASS.
- [ ] **Step 5: Commit** — `git add scenes/animation_production_lab/ scripts/animation_production_lab/animation_production_lab.gd tests/test_animation_independence.tscn tests/test_animation_independence.gd` — msg `feat(animation-lab): independent lab scene skeleton with starter 2.5D world`.

---

### Task 3: WorldController — place / select / transform / depth / layers

**Files:**
- Create: `scripts/animation_production_lab/world_controller.gd`
- Test: `tests/test_animation_world.gd` (SceneTree)

**Interfaces:**
- Consumes: `EMCAssetData` (Task 4) — for now tests fabricate it? **No**: Task 4 defines `EMCAssetData`; to keep order, Task 3 uses it via the class cache. Create the tiny `scripts/animation_production_lab/data/emc_asset_data.gd` in this task (one `@export` field per spec §3) so Task 3's tests compile; Task 4 fills the library around it. Same for nothing else.
- Produces: `class_name WorldController extends Node`:
  - `signal objects_changed`, `signal selection_changed(object_id: String)`
  - `@export_node_path("Node3D") var character_root`, `@export_node_path("Node3D") var background_root`, `@export_node_path("Node3D") var prop_root`
  - `func add_asset(asset: EMCAssetData, position: Vector3) -> String` (id `"obj_<n>"`; `""` on null/invalid; sprite for `character`/`background` categories into the matching root with `billboard` for characters; `MeshInstance3D`+primitive for `prop` using `asset.metadata.get("shape", "box")` — `"box"`→`BoxMesh(size=Vector3(0.8,0.9,0.6))`, `"cylinder"`→`CylinderMesh(radius=0.35, height=0.9)` — with `StandardMaterial3D` albedo from `asset.metadata.get("color", Color(0.6,0.6,0.6))`)
  - `func remove_object(object_id: String) -> bool`, `func duplicate_object(object_id: String) -> String`
  - `func replace_object_asset(object_id: String, asset: EMCAssetData) -> bool` — swaps the node's texture/mesh family for the new asset (sprite ↔ sprite, or rebuilds the primitive mesh), keeps transform; `false` on unknown id or null asset (spec Stage 3 "replace an asset")
  - `func get_object_node(object_id: String) -> Node3D`, `func get_object(object_id: String) -> Dictionary` (registry entry: `{id, asset_id, category, type, path, position, rotation_degrees, scale, depth, layer, visible}`)
  - `func select(object_id: String)`, `func selected() -> String`, `func clear_selection()`
  - `func set_object_position(id, pos: Vector3) -> bool`, `set_object_rotation(id, rot_deg: Vector3) -> bool`, `set_object_scale(id, s: Vector3) -> bool`, `set_object_visible(id, v: bool) -> bool`, `set_object_depth(id, depth: float) -> bool` (z-adds the depth offset), `set_object_layer(id, layer: int) -> bool` (re-parents within its root, `move_child`), `reset_object(id) -> bool` (restores spawn defaults: position as given, rotation 0, scale 1, visible true, depth 0, layer 0)
  - `func all_objects() -> Array[String]`

- [ ] **Step 1: Write the failing test** — `tests/test_animation_world.gd` (`extends SceneTree`): build a scratch tree (`Node3D` roots added to a scratch `Node3D`), `WorldController.add_asset` a character (`EMCAssetData` with `category = "character"`, `path = "res://assets/char_animation/idle/" + first_sorted` loaded via `DirAccess`), a background (`path = "res://assets/Scene_BG/Menu_Bg_image.png"`), a prop (`metadata = {shape="box"}`). Assert: 3 objects registered; `get_object_node(prop_id).mesh is BoxMesh`; `set_object_position(character, Vector3(1,2,3))` → node position matches and registry matches; rotation/scale/visible round-trip; `set_object_depth` moves only z; `set_object_layer` reorders; `reset_object` restores defaults; `duplicate_object` returns a distinct id with the same mesh class; `replace_object_asset(prop_id, cylinder_asset)` swaps the mesh to `CylinderMesh` and keeps the transform; `remove_object` removes from registry and tree; `select`/`selected`/`clear_selection` work; `add_asset(null)` returns `""`. One `FAIL:` line naming the first failed assertion, else `PASS: world controller place/select/transform/depth/layers`.
- [ ] **Step 2: Run to verify it fails** — `-Only test_animation_world.gd` (identifier not declared).
- [ ] **Step 3: Implement `scripts/animation_production_lab/world_controller.gd` and `scripts/animation_production_lab/data/emc_asset_data.gd`** — keep the registry as the source of truth; apply to nodes (positions `Vector3`; nodes parented under the right root; `visible` on the node; `depth` = `node.position.z += depth`). Tree access via `get_node_or_null(NodePath)` resolved in `_ready` (and on first use, so tests that add children later still work).
- [ ] **Step 4: Run to verify it passes.**
- [ ] **Step 5: Commit** — msg `feat(animation-lab): world controller for placing and transforming objects`.

---

### Task 4: EMC Asset Library adapter (starter fallback + read-only user scan)

**Files:**
- Create: `scripts/animation_production_lab/emc_asset_library.gd`, `scripts/animation_production_lab/starter_assets.gd`
- Test: `tests/test_animation_asset_library.gd` (SceneTree)

**Interfaces:**
- Consumes: `EMCAssetData` (Task 3), `DigitalArtData` (existing, `scripts/digital_art_lab/`)
- Produces:
  - `class_name StarterAssets` — `static func build() -> Array[EMCAssetData]`:
    - character: `DirAccess.open("res://assets/char_animation/idle")` and `.../run`, each `.png` sorted by name → `EMCAssetData` with `display_name` = filename, `source_lab = "starter"`, `path = "res://assets/char_animation/<dir>/<file>"`, `metadata = {pose = "idle"|"run"}`; all `category = "character"`, `asset_type = "sprite"`, `preview_texture = null`
    - background: fixed entry for `res://assets/Scene_BG/Menu_Bg_image.png`, `display_name = "Lab Backdrop"`, `category = "background"`
    - prop: two entries, `category = "prop"`, `asset_type = "primitive"`, `path = ""`, `metadata = {shape = "box"|"cylinder", color = Color(0.35,0.45,0.6)|Color(0.5,0.3,0.2)}`
  - `class_name EMCAssetLibrary extends RefCounted`:
    - `var user_roots: Array[String] = ["user://exports", "user://drawings"]` (injectable for tests)
    - `func list(category: String = "") -> Array[EMCAssetData]`
    - `func get(asset_id: String) -> EMCAssetData` (`null` when unknown)
    - `func load_texture(data: EMCAssetData) -> Texture2D` (`null` when `path` empty or `ResourceLoader.exists(path)` is false; `ResourceLoader.load(path, "Texture2D")` otherwise)
    - `func refresh() -> void`
- **User-scan mapping (declared):** `user://exports/*.png` → `category = "user_art"`, `asset_type = "sprite"`, `source_lab = "illustration"`, `display_name` = filename stem. `user://drawings/*.tres` (loaded as `DigitalArtData`) → `category = "user_art"`, `asset_type = "drawing"`, `path` = the `.tres` path. `asset_id = "user_<n>"`. Missing dirs → skipped, no error.

- [ ] **Step 1: Write the failing test** — `tests/test_animation_asset_library.gd` (`extends SceneTree`): `refresh()`, then assert: `list()` includes >0 characters, `list("background")` has the `Lab Backdrop` entry with a non-empty path, `list("prop")` has 2, `get("definitely-missing")` is null, `load_texture(bg)` returns a non-null `Texture2D`, `load_texture(EMCAssetData with path "res://does_not_exist.png")` returns null and prints no error; **Review Focus RF1**: rebuild the adapter with `user_roots = ["user://no_such_dir_a", "user://no_such_dir_b"]` → `list()` still returns starters, `refresh()` doesn't crash; **RF2**: `load_texture` on a `user_art` entry with a dead path returns null. `PASS: asset library falls back to starters and stays safe on missing user data`.
- [ ] **Step 2: Run to verify it fails.**
- [ ] **Step 3: Implement both scripts** — `starter_assets.gd` as a static builder (runtime `DirAccess` listing — the image filenames are not authorable constants); `emc_asset_library.gd` merging starters first, user scan second. Parse `DigitalArtData` defensively: any failed `ResourceLoader.load` in the scan is skipped, never fatal.
- [ ] **Step 4: Run to verify it passes.**
- [ ] **Step 5: Commit** — msg `feat(animation-lab): EMC asset library adapter with starter fallback`.

---

### Task 5: CameraController

**Files:**
- Create: `scripts/animation_production_lab/camera_controller.gd`
- Test: `tests/test_animation_camera.gd` (SceneTree)

**Interfaces:**
- Consumes: nothing beyond a `Camera3D` node in the tree
- Produces: `class_name CameraController extends Node`:
  - `@export_node_path("Camera3D") var camera_path`
  - `func camera() -> Camera3D` (lazy `get_node_or_null`)
  - `func set_transform(pos: Vector3, rot_deg: Vector3) -> void`, `func move_offset(offset: Vector3) -> void`, `func rotate_offset(delta_deg: Vector3) -> void`
  - `func set_zoom(factor: float) -> void` (moves along `-global_transform.basis.z` by `factor`; clamps camera distance to `[0.5, 12.0]`)
  - `func reset() -> void` (restores `Vector3(0, 0.8, 4)` / `Vector3.ZERO` rotation / FOV 60)
  - `func framing_ok(center: Vector3, targets: Array[Vector3], max_distance: float) -> bool` — true when `center.distance_to(cam.global_position) <= max_distance` and every target projects inside the view frustum (`camera.is_position_in_frustum(t)`); used as the measurable framing check (spec §4.2).
- Step budget: the bodies here are 2–4 lines each; keep them that size.

- [ ] **Step 1: Write the failing test** — `extends SceneTree`: scratch tree `root` with `Camera3D` + controller; `camera_path` set via `NodePath("../Camera3D")`; assert `set_transform`/`set_zoom` move real camera transforms; `reset()` restores defaults; `framing_ok` with camera 4 units from origin and targets on-screen → true, and with `max_distance = 1.0` → false; `framing_ok` with a target 200 units behind the camera → false. `PASS: camera controller transform/zoom/reset/framing`.
- [ ] **Step 2: Run to verify it fails.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run to verify it passes.**
- [ ] **Step 5: Commit** — msg `feat(animation-lab): camera controller with measurable framing`.

---

### Task 6: LightingController

**Files:**
- Create: `scripts/animation_production_lab/lighting_controller.gd`
- Test: `tests/test_animation_lighting.gd` (SceneTree)

**Interfaces:**
- Produces: `class_name LightingController extends Node`:
  - `signal lights_changed`
  - `@export_node_path("Node3D") var lighting_root`
  - `const LIGHT_DIRECTIONAL := 0`, `const LIGHT_OMNI := 1`
  - `func add_light(type: int, position: Vector3) -> String` — creates `DirectionalLight3D`/`OmniLight3D` under `lighting_root`, `light_energy = 1.0`, `shadow_enabled = false`; **budget cap**: `false`/`""` (and no node) when adding a 2nd directional or a 2nd omni (spec §8: 1 directional + at most 1 omni)
  - `func remove_light(id: String) -> bool`, `func select(id: String)`, `func selected() -> String`
  - `func set_intensity(id: String, energy: float) -> bool` (clamps to `[0.0, 5.0]`), `func set_color(id: String, color: Color) -> bool`, `func set_shadows(id: String, enabled: bool) -> bool`
  - `func key_light_exists() -> bool` (≥1 directional with energy > 0), `func min_intensity() -> float`, `func light_count() -> int`
- Tests pin the gl-compat budget and the scoring measures (intensity floor, key light exists).

- [ ] **Step 1: Write the failing test** — `extends SceneTree`: scratch `Node3D` root; assert `add_light(DIRECTIONAL)` and `add_light(OMNI)` succeed; second directional and second omni both return `""` and add nothing; `set_intensity` clamps (`999` → `5.0`); `set_shadows` toggles; `remove_light` frees the node; `key_light_exists` true only with an energized directional. `PASS: lighting controller respects budget and exposes scoring measures`.
- [ ] **Step 2: Run to verify it fails.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run to verify it passes.**
- [ ] **Step 5: Commit** — msg `feat(animation-lab): lighting controller with GL-Compat budget cap`.

---

### Task 7: FrameController + AnimationFrameData

**Files:**
- Create: `scripts/animation_production_lab/data/animation_frame_data.gd`, `scripts/animation_production_lab/frame_controller.gd`
- Test: `tests/test_animation_frames.gd` (SceneTree)

**Interfaces:**
- Produces:
  - `class_name AnimationFrameData extends Resource`: `@export var frame_index: int = 0`, `@export var texture: Texture2D`, `@export var duration: float = 0.1`, `@export var pose_name: String = ""`, `@export var notes: String = ""`
  - `class_name FrameController extends Node`: `signal frames_changed`; `var frames: Array[AnimationFrameData] = []`; `func add_frame(texture: Texture2D = null, duration: float = 0.1) -> AnimationFrameData` (appends, auto-indexes, returns it); `func remove_frame(index: int) -> bool` (**false when `frames.size() <= 1`** — a timeline always has ≥ 1 frame, Review Focus framing); `func duplicate_frame(index: int) -> bool`; `func insert_frame(index: int, frame: AnimationFrameData) -> bool`; `func move_frame(from: int, to: int) -> bool`; `func set_frame_texture(index: int, texture: Texture2D) -> bool`; `func set_frame_duration(index: int, duration: float) -> bool` (clamps to `>= 0.01`); `func reindex() -> void`
- [ ] **Step 1: Write the failing test** — `extends SceneTree`: add 3 frames → `frames.size() == 3`, indexes 0..2, durations default 0.1; `move_frame(0, 2)` reorders; `duplicate_frame(1)` copies texture ref; `set_frame_duration(0, 0)` → clamped to 0.01; `remove_frame` down to 1 OK; removing the last frame returns `false` and leaves size 1. `PASS: frame list add/remove/duplicate/reorder with min-1 invariant`.
- [ ] **Step 2: Run to verify it fails.**
- [ ] **Step 3: Implement** both files (the test's Assert uses `Texture2D` only as a ref; `preload` one starter PNG for the texture case).
- [ ] **Step 4: Run to verify it passes.**
- [ ] **Step 5: Commit** — msg `feat(animation-lab): frame-by-frame list with min-one-frame invariant`.

---

### Task 8: TimelineController — clock, FPS/duration, frame channel

**Files:**
- Create: `scripts/animation_production_lab/timeline_controller.gd`
- Test: `tests/test_animation_timeline.gd` (SceneTree)

**Interfaces:**
- Consumes: `FrameController` (Task 7) via `@export_node_path` when in-scene; a unit test may set `frame_controller` directly (a plain `Node` property, not only a path — declare `var frame_controller_ref: FrameController` populated from the path in `_ready`, overridable in tests).
- Produces: `class_name TimelineController extends Node`:
  - `signal playback_started`, `signal playback_stopped`, `signal time_changed(time: float)`
  - `var fps: int = 12`, `var duration: float = 5.0`, `var loop: bool = false`, `var current_time: float = 0.0`
  - `var min_fps := 1`, `var max_fps := 60`, `var max_duration := 30.0`
  - `func set_fps(value: int) -> bool` — **RF3**: `false` and no change for `< min_fps` or `> max_fps`; clamps nothing beyond those, but `set_duration(value)` clamps negatives to `0.01` and rejects `> max_duration`
  - `func play() -> void`, `func pause() -> void`, `func stop() -> void` (resets `current_time = 0`), `func is_playing() -> bool`
  - `func step_time(delta: float) -> void` — pure clock: while playing, `current_time += delta`; clamp to `duration`; at the end, stop (emit `playback_stopped`) unless `loop` (wrap to 0); emit `time_changed`
  - `func frame_index_at(time: float) -> int` — `floori(fps * time)` clamped to `frames.size() - 1`
  - `func current_frame_index() -> int`, `func current_frame_progress() -> float` (`fmod(fps * time, 1.0)`)

- [ ] **Step 1: Write the failing test** — `extends SceneTree`, `set_fps(12)`, `set_duration(5.0)`:
  - determinism: `step_time(0.5)` ×2 → `current_time == 1.0` without any engine frames (pure call)
  - play/stop: `play()`; `step_time(5.0)` → stops, `current_time == 5.0`, `is_playing() == false`; `play()` again with `loop = true` → `step_time(6.0)` wraps to `1.0` and still playing
  - frame channel: with 3 frames and fps 12, `frame_index_at(0.0) == 0`, `frame_index_at(0.5) == 6` → clamped to 2 when `current_frame_index()` is used at time ≥ 0.25
  - **RF3**: `set_fps(0) == false`, `set_fps(13) == true` and `fps == 13`, `set_fps(61) == false`; `set_duration(-1) == false` (rejected) — the `-1` input must be **rejected**, `0.0` accepted and clamped to `0.01`
  - `frame_index_at` never exceeds `frames.size() - 1` even for huge time.
  `PASS: timeline clock, fps/duration validation, frame channel at fps boundaries`
- [ ] **Step 2: Run to verify it fails.**
- [ ] **Step 3: Implement** — `set_duration` accepts `<= 0` as `false` (reject) except exactly `0.0` clamps to `0.01`; reject `> max_duration`. One scratch `FrameController` instance with 3 default frames feeds `frames.size()`.
- [ ] **Step 4: Run to verify it passes.**
- [ ] **Step 5: Commit** — msg `feat(animation-lab): timeline clock with fps/duration validation`.

---

### Task 9: KeyframeController + AnimationKeyframeData + interpolation

**Files:**
- Create: `scripts/animation_production_lab/data/animation_keyframe_data.gd`, `scripts/animation_production_lab/keyframe_controller.gd`
- Test: `tests/test_animation_keyframes.gd` (SceneTree)

**Interfaces:**
- Produces:
  - `class_name AnimationKeyframeData extends Resource`: `@export var time: float = 0.0`, `@export var target_id: String = ""`, `@export var target_type: int = 0` (0=object, 1=camera, 2=light), `@export var property_path: String = "position"`, `@export var value: Variant`, `@export var interpolation: int = 0` (0=LINEAR, 1=STEP)
  - `class_name KeyframeController extends Node`:
    - `signal keyframes_changed`
    - `const TARGET_OBJECT := 0`, `TARGET_CAMERA := 1`, `TARGET_LIGHT := 2`; `const LINEAR := 0`, `STEP := 1`
    - `var keyframes: Array[AnimationKeyframeData] = []` (sorted by `time`)
    - `func add_keyframe(time: float, target_id: String, target_type: int, property_path: String, value: Variant, interpolation: int = LINEAR) -> AnimationKeyframeData`
    - `func remove_keyframe(index: int) -> bool`
    - `func keyframes_for(target_id: String) -> Array[AnimationKeyframeData]`
    - `func keyframe_times(target_id: String) -> Array[float]`
    - `func evaluate(target_id: String, property_path: String, time: float) -> Variant` — **RF4-safe**: `null` when the target has no track for that property; before first key → first key's value; after last → last key's value; between → LINEAR: `Vector3`/`float`/`Color` lerp by `t` (`Vector3.lerp`, `lerpf`, `Color.lerp`), STEP → before-key value.
- [ ] **Step 1: Write the failing test** — `extends SceneTree`:
  - linear: returns `Vector3(0,0,0)`→`Vector3(4,0,0)` at t=0.5 → `Vector3(2,0,0)`; float lerp; STEP gives the before value
  - clamping: before-first → first value; after-last → last value
  - sorting: add keys at t=2.0 then t=1.0 → array sorted ascending
  - **RF4**: `evaluate("ghost_id", "position", 1.0)` → `null`, no error; `evaluate` for a property with no track → `null`
  - `PASS: keyframe add/remove/evaluate with linear & step interpolation, orphan-safe`
- [ ] **Step 2: Run to verify it fails.**
- [ ] **Step 3: Implement** both files.
- [ ] **Step 4: Run to verify it passes.**
- [ ] **Step 5: Commit** — msg `feat(animation-lab): keyframe tracks with linear/step interpolation`.

---

### Task 10: PreviewController — apply timeline to the world

**Files:**
- Create: `scripts/animation_production_lab/preview_controller.gd`
- Test: `tests/test_animation_preview.gd` (SceneTree)

**Interfaces:**
- Consumes: `TimelineController` (Task 8), `FrameController` (Task 7), `KeyframeController` (Task 9), `WorldController` (Task 3), `CameraController` (Task 5), `LightingController` (Task 6) — all via plain `Node`/`Object` properties set by the root (`var timeline: TimelineController` etc.), callable in tests with hand-built controllers.
- Produces: `class_name PreviewController extends Node`:
  - `func apply_frame() -> void` — for each registered frame-owner (objects whose category is `character`): set the `Sprite3D.texture` to `frames[timeline.current_frame_index()].texture` (null-safe: missing texture → keep current, don't crash)
  - `func apply_keyframes() -> void` — for each target channel: `evaluate(target_id, property_path, timeline.current_time)`; route by `target_type` + path: object → `world.set_object_position|rotation|scale|visible` by mapping `property_path` (`"position"`, `"rotation"`, `"scale"`, `"visible"`); camera → `camera.set_transform`/`set_zoom`; light → `lighting.set_intensity|set_color`. **RF4**: unknown target_id → skip silently.
  - `func step(delta: float) -> void` — `timeline.step_time(delta)` then `apply_keyframes()` then `apply_frame()` at frame-boundary changes.
  - `var review_checklist: Dictionary = {}` — `{label: String, passed: bool}`; `func evaluate_review() -> void` fills the 10 spec items (character visible, background visible, main action understandable (≥1 movement keyframe), camera framed, lighting sufficient (key light + min intensity > 0.0), beginning/middle/end present (≥3 frames), timing correct (fps within `[12-2, 12+2]` default), final pose visible, ≥ 1 pose change (≥ 2 distinct frame textures), plays without errors). Each check is read-only over the consumed controllers.

- [ ] **Step 1: Write the failing test** — `extends SceneTree`: hand-build `FrameController` (3 frames, textures from starter PNGs, one duplicated vs distinct), `TimelineController`, `KeyframeController`, `WorldController` (scratch tree with one character), `CameraController`, `LightingController`. Assert: `apply_frame()` swaps the sprite texture to frame 1's texture at `current_time = 1/fps`; `apply_keyframes()` moves the object for a linear position track at mid-time; `evaluate_review()` marks character-visible true / lighting false when energy 0 / timing false when fps 30 / pose-change true with distinct textures; no errors when a keyframe references `"ghost"`. `PASS: preview applies frames & keyframes and evaluates the review checklist`.
- [ ] **Step 2: Run to verify it fails.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run to verify it passes.**
- [ ] **Step 5: Commit** — msg `feat(animation-lab): preview controller applies timeline to world, review checklist`.

---

### Task 11: AnimationAssignment + AnimationScoreData + assignment resource + stage machine

**Files:**
- Create: `scripts/animation_production_lab/data/animation_assignment.gd`, `scripts/animation_production_lab/data/animation_score_data.gd`, `scripts/animation_production_lab/assignment_manager.gd`, `data/assignments/animation/day_in_emc_lab.tres`
- Test: `tests/test_animation_assignment.gd` (SceneTree)

**Interfaces:**
- Produces:
  - `class_name AnimationAssignment extends Resource`: `assignment_id: String`, `display_name: String`, `story_beats: Array[Dictionary]` (`{id, text, order}`), `required_categories: PackedStringArray`, `min_frames: int`, `candidate_frame_paths: Array[String]` (3 shuffled starter PNG paths), `correct_frame_path: String`, `required_keyframes: Array[Dictionary]` (`{target_type, property_path}`), `target_fps: int`, `fps_tolerance: int`, `target_duration: float`, `final_pose_keyframe: bool`, `hints: Array[String]`, `review_checklist_hint: String`
  - `class_name AnimationScoreData extends Resource`: `story_score`, `staging_score`, `camera_score`, `lighting_score`, `frame_animation_score`, `keyframe_score`, `timing_score`, `technical_score`, `creativity_score`, `total_score` (all `float`), `feedback: Array[String]`
  - `class_name AssignmentManager extends Node`:
    - `enum Stage {BRIEF, PLAN, ASSETS, STAGING, CAMERA, LIGHTING, FRAMES, KEYFRAME, TIMING, PREVIEW, SUBMIT}`
    - `signal stage_changed(stage: int)`, `signal assignment_loaded(assignment: AnimationAssignment)`
    - `var assignment: AnimationAssignment`
    - `func load_assignment(path: String) -> bool` (load + type-check; `false` on failure, keeps previous/default, never crashes)
    - `func current_stage() -> int`, `func can_advance() -> bool`, `func advance_stage() -> bool`, `func go_to(stage: int) -> void`
    - `func stage_requirements() -> Array[Dictionary]` — `{label, check: Callable, passed}` re-evaluated live each call
    - challenge helpers (spec §4.1, Challenges A–F): `func order_story_beats(ids: Array[String]) -> bool` (A), `func stage_scene_ok(character_before_background: bool, near_prop: bool) -> bool` (E), `func missing_frame_ok(texture: Texture2D) -> bool` (B — compares against `correct_frame_path`), `func fps_ok(fps: int) -> bool` (C), `func keyframe_order_ok() -> bool` (D+F: a `TARGET_OBJECT`/`"position"` keyframe at earlier time than a frame-channel pose change; pose change detected via ≥ 2 distinct frame textures, see Task 10)
    - `func hints_for_stage() -> Array[String]`
    - `var tutorial_steps: Array[String]` (built-in, 12 items; `func tutorial_done() -> void`)
- `data/assignments/animation/day_in_emc_lab.tres`: `assignment_id = "day_in_emc_lab"`, `display_name = "A Day in the EMC Laboratory"`, `story_beats` = begin/middle/end (enter lab → approach workstation → final pose at workstation), `required_categories = PackedStringArray("character", "background", "prop")`, `min_frames = 3`, `candidate_frame_paths`/`correct_frame_path` = three `res://assets/char_animation/run/` PNGs (correct = the pose showing the approach), `required_keyframes = [{target_type: 0, property_path: "position"}, {target_type: 0, property_path: "visible"}]`, `target_fps = 12`, `fps_tolerance = 2`, `target_duration = 5.0`, `final_pose_keyframe = true`, `hints` = the spec §hints examples, `review_checklist_hint`.

- [ ] **Step 1: Write the failing test** — `extends SceneTree`: `load_assignment("res://data/assignments/animation/day_in_emc_lab.tres")` → true, then: `advance_stage()` from BRIEF to PLAN succeeds — BRIEF only gates on the assignment being loaded (`_assignment_loaded_ok`; spec §4.1 "read the assignment, Continue"); `advance_stage()` from PLAN fails while the story beats are unordered (gating — a failed advance leaves the stage put); `go_to(STAGING)`; `order_story_beats` correct order → true, jumbled → false; `missing_frame_ok(correct)` true and wrong texture false; `fps_ok(12)`/`fps_ok(13)` true, `fps_ok(20)` false (tolerance 2); `keyframe_order_ok` false with only a position key (no pose change) and true with a later pose-change frame set; `load_assignment("res://missing.tres")` → `false` without crashing and keeps previous assignment; `hints_for_stage()` non-empty; resource type-taint (RF-ish): a hand-edited .tres loads to defaults rather than a crash — assert via `load_assignment` failure path returning `false`. `PASS: assignment loads and stage machine gates challenges A–F`.
- [ ] **Step 2: Run to verify it fails.**
- [ ] **Step 3: Implement** the two Resource classes, the manager, and the `.tres` (`.tres` authored by hand in the `[resource]` block with `Array[Dictionary]`/`PackedStringArray` literal syntax; verify it parses by running the test).
- [ ] **Step 4: Run to verify it passes.**
- [ ] **Step 5: Commit** — msg `feat(animation-lab): data-driven assignment, stage machine, challenges a–f`.

---

### Task 12: ScoringController — measurable scoring + feedback

**Files:**
- Create: `scripts/animation_production_lab/scoring_controller.gd`
- Test: `tests/test_animation_scoring.gd` (SceneTree)

**Interfaces:**
- Consumes: Task 10's `review_checklist`, `AssignmentManager` (Task 11), `WorldController`, `CameraController`, `LightingController`, `FrameController`, `KeyframeController`, `TimelineController`
- Produces: `class_name ScoringController extends RefCounted`:
  - `func score(assignment: AnimationAssignment, world: WorldController, camera: CameraController, lighting: LightingController, frames: FrameController, keyframes: KeyframeController, timeline: TimelineController, review: Dictionary) -> AnimationScoreData`
  - Measures (spec §4.2, 0..100 each): `story_score` = storyboard order correct (via `assignment.story_beats` passed in? no — take `story_order_correct: bool` param) 100/0; `staging_score` = required categories present (`world.all_objects()` categories ⊉ required → 0 else 100, minus 20 per extra null-texture asset — **RF2**: `load_texture` via Task 4 returns null → category present but "no valid texture" → 50); `camera_score` = `camera.framing_ok(...)` 100/0; `lighting_score` = key light + `min_intensity() > 0.0` 100/0; `frame_animation_score` = `frames.frames.size() >= min_frames` (100) + pose-change bonus, null textures → 50; `keyframe_score` = every `assignment.required_keyframes` present on a matching target 100/0 (missing → 0); `timing_score` = `abs(fps - target_fps) <= tolerance` (100) and duration within limits (else 50); `technical_score` = review `plays_without_errors` + checklist pass ratio (`passed/total`, ≥ 7/10 for full); `creativity_score` = 100 when ≥ 1 extra keyframe or prop beyond requirements, else 75. `total_score = sum of the nine × weights` — weights 0.125 each ×8 + creativity 0.1? **Fixed, declared:** story 0.125, staging 0.125, camera 0.10, lighting 0.10, frame 0.125, keyframe 0.125, timing 0.10, technical 0.10, creativity 0.10 → sums to 1.0. `feedback` = one template sentence per category under 100 + condition-specific hint lines (non-punitive phrasing).
- [ ] **Step 1: Write the failing test** — `extends SceneTree`, build a fully-satisfied world/camera/lights/frames/keyframes/timeline + correct review → total 100, every subscore 100; then the "empty" world variant (no objects, no lights, fps 20 off-target, review all false) → total ≈ 0 and feedback non-empty; a "half" variant with only required categories present and fps 13 → frame/staging full but timing 100 (tolerance), lighting 0 → total midway; **RF2**: character object whose texture path is dead → `frame_animation_score` 50, no crash. `PASS: scoring measures nine categories from measurable requirements`.
- [ ] **Step 2: Run to verify it fails.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run to verify it passes.**
- [ ] **Step 5: Commit** — msg `feat(animation-lab): measurable scoring with category weights and feedback`.

---

### Task 13: Guided-mode workspace UI (panels + stage switching)

**Files:**
- Create (under `scenes/animation_production_lab/ui/`): `top_bar.tscn`, `assignment_panel.tscn`, `storyboard_panel.tscn`, `asset_library_panel.tscn`, `inspector_panel.tscn`, `timeline_panel.tscn`, `animation_controls.tscn`, `hint_panel.tscn`, `tutorial_overlay.tscn` — each a `Control` root with a `class_name`-less `extends Control` script baked into the `.tscn` (a small `.gd` per scene under `scripts/animation_production_lab/ui/`), emitting typed signals to the root; wire them into `animation_production_lab.tscn` (Task 2 modified)
- Modify: `scenes/animation_production_lab/animation_production_lab.tscn`, `scripts/animation_production_lab/animation_production_lab.gd`
- Test: `tests/test_animation_ui_stages.tscn` (scene harness — drives Stage switching)

**Interfaces:**
- Consumes: all controllers from Tasks 3–12 (wired in the root `_ready`)
- Produces (root additions in `animation_production_lab.gd`):
  - `@onready` refs to the panels; `func show_stage_ui(stage: int)` — one visible panel per stage: BRIEF→`AssignmentPanel`, PLAN→`StoryboardPanel`, ASSETS→`AssetLibraryPanel`, STAGING/CAMERA/LIGHTING/INSPECTOR→`InspectorPanel` + world, FRAMES/KEYFRAME/TIMING→`TimelinePanel`/`AnimationControls`, PREVIEW→play + `HintPanel`, SUBMIT→`SubmissionPanel`; TopBar always visible
  - `func on_stage_changed(stage: int)` connected to `AssignmentManager.stage_changed` → `show_stage_ui`
  - Wire panel signals to the matching controller methods (e.g. `AssetLibraryPanel.add_requested` → `world.add_asset`; `TimelinePanel.fps_changed` → `timeline.set_fps`; `InspectorPanel.transform_edited` → `world.set_object_*`)
- All panels are `Container`-based, touch-target buttons ≥ 40×40 css px, `mouse_filter` defaults, labels ≥ 16px. Timeline rows are tap-target rows, not pixel handles (spec §8).

- [ ] **Step 1: Write the failing test** — `tests/test_animation_ui_stages.tscn`: instantiate the lab, `await process_frame`; assert `TopBar` exists and shows the mode label; call `assignment_manager.load_assignment(<day_in_emc_lab>)` then drive `go_to(BRIEF)` → `AssignmentPanel.visible == true` and `TimelinePanel.visible == false`; `go_to(PLAN)` → StoryboardPanel visible; `go_to(FRAMES)` → TimelinePanel visible; `go_to(SUBMIT)` → SubmissionPanel visible. Print `PASS: stage-driven panel switching` / FAIL with the mismatched panel.
- [ ] **Step 2: Run to verify it fails.**
- [ ] **Step 3: Build the 9 panels** (scenes + scripts). Keep each script minimal: exported signals + label/button wiring only. Root wiring: connect `AssignmentManager.stage_changed` in `_ready`.
- [ ] **Step 4: Run to verify it passes.**
- [ ] **Step 5: Commit** — msg `feat(animation-lab): guided-mode workspace UI with stage switching`.

---

### Task 14: Submission, scoring display, completion, studio unlock

**Files:**
- Create: `scenes/animation_production_lab/ui/submission_panel.tscn`, `scenes/animation_production_lab/ui/score_panel.tscn` (+ scripts)
- Modify: `animation_production_lab.gd`, `animation_production_lab.tscn`
- Test: `tests/test_animation_guided_flow.tscn` (scene harness — full scripted guided run)

**Interfaces:**
- Produces (root):
  - `func on_submit_pressed() -> void` — gate: `assignment_manager.can_advance()` at SUBMIT and `preview.evaluate_review()`; compute `score = scoring.score(...)`; `ScorePanel.show_score(score)`; set `guided_completed = true` on the in-memory save data; call `LevelProgression.complete_level(level_def)` (load `res://data/levels/animation_production_lab.tres`, guard `LevelProgression.is_level_completed` no-op); emit `guided_completed`
  - `func unlock_creative_studio() -> void` — `mode = Mode.STUDIO` available (flag on root `var guided_completed: bool`; the Creative Studio unlock is read from this flag on boot, resilient even if `LevelProgression` data resets — spec §5)
  - `ExitButton.pressed` → `exit_lab()` (Task 2)
- `SubmissionPanel`: Submit button + live requirement checklist (from `stage_requirements()`); disabled until `can_advance()`.
- `ScorePanel`: `label` breakdown per category + `total` + `feedback` list + "Continue to Creative Studio" → `unlock_creative_studio()`.

- [ ] **Step 1: Write the failing test** — `tests/test_animation_guided_flow.tscn`: instantiate lab; load assignment; drive the full pipeline **through controllers**: `order_story_beats` (correct), add the 3 required categories via `world.add_asset`, add 3 frames (`min_frames`), correct missing frame, add the required keyframes with correct ordering, `fps = 12`, `duration = 5.0`; then `on_submit_pressed()`; assert `ScorePanel` visible and `score.total_score >= 90`; `guided_completed == true`; `LevelProgression.is_level_completed("animation_production_lab") == true` (after the guard it fires); `unlock_creative_studio()` switches mode. Also a second run with nothing done → `can_advance()` false at SUBMIT and submit produces no unlock. `PASS: guided flow gates submission, scores, completes level, unlocks studio`.
- [ ] **Step 2: Run to verify it fails.**
- [ ] **Step 3: Implement** panels + root methods (submit gate → score → complete_level → unlock).
- [ ] **Step 4: Run to verify it passes.**
- **Warning:** this test calls `LevelProgression.complete_level` — it writes `user://level_progression.json`. On desktop that's the real progression file used by the game at runtime. After this test, restore: the test harness **backs up the file before running and restores it after** (`DirAccess.copy_absolute`/`FileAccess` write-back); note the warning in the test header comment, mirroring how `test_full_lab_sweep.gd` interacts with progression.
- [ ] **Step 5: Commit** — msg `feat(animation-lab): submission, scoring UI, completion and studio unlock`.

---

### Task 15: SaveController + AnimationLabSaveData (safe round-trip)

**Files:**
- Create: `scripts/animation_production_lab/data/animation_lab_save_data.gd`, `scripts/animation_production_lab/save_controller.gd`
- Modify: `scripts/animation_production_lab/animation_production_lab.gd` (autosave wiring)
- Test: `tests/test_animation_save.gd` (SceneTree)

**Interfaces:**
- Produces:
  - `class_name AnimationLabSaveData extends Resource` — fields exactly from spec §3: `guided_completed: bool`, `current_assignment_id: String`, `scene_objects: Array[Dictionary]`, `camera_data: Dictionary`, `lighting_data: Dictionary`, `frames: Array[Dictionary]`, `keyframes: Array[Dictionary]`, `fps: int`, `duration: float`, `score_data: Dictionary`, `hints_used: int`, `creative_projects: Array[Dictionary]`
  - `class_name SaveController extends RefCounted`:
    - `var base_dir := "user://animation_lab/"` (injectable for tests)
    - `func save_data(data: AnimationLabSaveData, project_name: String = "") -> bool` — `guided.tres` when `project_name` empty, else `projects/<sanitized_name>.tres`; `ResourceSaver.save`; returns `err == OK`
    - `func load_data(project_name: String = "") -> AnimationLabSaveData` — missing file → `new()` defaults; wrong type / parse failure → `new()` + one `push_warning`; successful load → **per-key type sanitize** — **RF5**: each field validated (`guided_completed` via `bool(v)`, `fps` via `int(v)` guarded, arrays via `if v is Array`), invalid/missing keys fall back to defaults
    - `func list_projects() -> Array[Dictionary]` (`{name, path}` sorted), `func delete_project(name: String) -> bool`, `func rename_project(old_name: String, new_name: String) -> bool`, `func project_exists(name: String) -> bool`
    - `func _sanitize_filename(name: String) -> String` — FileManager alphanumeric+underscore rule
    - `func _ensure_dirs() -> void`
- [ ] **Step 1: Write the failing test** — `extends SceneTree`, `base_dir = "user://animation_lab_test/"` (clean it at start and end via `DirAccess.remove_absolute`):
  - round-trip: fill an `AnimationLabSaveData` (guided_completed=true, 2 scene_objects, 1 keyframe dict, fps=12, creative_projects=[{name:"proj"}]), `save_data` → `load_data` → all fields equal
  - projects: `save_data(data, "My Project")` → `list_projects()` contains it; `rename_project("My Project", "Renamed")`, `project_exists("Renamed")` true; `delete_project` removes; name sanitization: `save_data(data, "a/b:c d")` writes `projects/a_b_c_d.tres`
  - **RF1/RF5**: `load_data("nope")` → defaults, no crash; wrote a hand-tainted file (`FileAccess` writes `"garbage not a resource"`) → `load_data` → defaults + a warning printed; hand-edited `guided.tres` with `guided_completed = 1` (int) and `fps = "12"` (string) → sanitized to bool/`int`, no crash (**RF5**)
  - **RF4**: `load_data` where `keyframes` references `"ghost"` targets → the arrays load verbatim (evaluation stays Task 9-safe)
  - `PASS: save/load round-trip with sanitization and corrupt fallback`
- [ ] **Step 2: Run to verify it fails.**
- [ ] **Step 3: Implement** both files (refactor: `FileManager._sanitize_filename` logic is copied, not shared — the existing class is art-lab-owned). In `animation_production_lab.gd`, `_ready()` connects `AssignmentManager.stage_changed` to an autosave hook: when `autosave_enabled` and a `SaveController` exists, `save_data(current_data)` on every stage change (spec §6 autosave; the current-data builder is a root helper `collect_save_data() -> AnimationLabSaveData` that snapshots world/camera/lighting/frames/keyframes/fps/duration/score/hints — implemented here, consumed by Task 16).
- [ ] **Step 4: Run to verify it passes.**
- [ ] **Step 5: Commit** — msg `feat(animation-lab): save controller with sanitized round-trip and corrupt fallback`.

---

### Task 16: Creative Studio mode + project CRUD

**Files:**
- Create: `scripts/animation_production_lab/creative_studio_controller.gd`, `scenes/animation_production_lab/ui/studio_panel.tscn` (+ script)
- Modify: `animation_production_lab.gd`, `animation_production_lab.tscn`
- Test: `tests/test_animation_creative_studio.gd` (SceneTree)

**Interfaces:**
- Consumes: `SaveController` (Task 15), the root's `collect_save_data()` helper (Task 15), `AnimationLabSaveData` (Task 15)
- Produces: `class_name CreativeStudioController extends Node`:
  - `var save: SaveController` (injected), `var projects: Array[Dictionary] = []` (mirror of `AnimationLabSaveData.creative_projects` + `{name, path}`)
  - `func new_project(name: String) -> bool` (fails on duplicate/empty name; creates a blank `AnimationLabSaveData` with 1 frame + default fps/duration, saves it)
  - `func load_project(name: String) -> AnimationLabSaveData`, `func save_current(data: AnimationLabSaveData, name: String) -> bool`, `func rename_project(old_name, new_name) -> bool`, `func duplicate_project(name: String) -> bool`, `func delete_project(name: String) -> bool`, `func list_projects() -> Array[String]`
- Root wiring: `Mode.STUDIO` runs the same World/Timeline/Save pipeline with no assignment (spec §5); the studio lock reads `guided_completed` on boot and reveals the Studio button in TopBar only when unlocked (**spec §15 unlock independence**: from the lab's own save flag, not just LevelProgression).

- [ ] **Step 1: Write the failing test** — `extends SceneTree` with a temp `base_dir`: `new_project("A")` true; `new_project("A")` false (duplicate); `load_project("A")` returns non-null data with 1 frame; `duplicate_project("A")` → "A (copy)" exists; `rename_project`; `delete_project` removes the file; `list_projects()` matches; a blank studio project at `frames.size() >= 1` (RF: new project is immediately playable — ties to Task 7 min-1 invariant). `PASS: creative studio project CRUD over the save layer`.
- [ ] **Step 2: Run to verify it fails.**
- [ ] **Step 3: Implement** controller + `StudioPanel` (project name field, New / Save / Load / Rename / Duplicate / Delete buttons, project list) + root mode wiring + TopBar unlock gate.
- [ ] **Step 4: Run to verify it passes.**
- [ ] **Step 5: Commit** — msg `feat(animation-lab): creative studio with project crud and unlock gate`.

---

### Task 17: Polish — input, audio, accessibility, perf, full gate

**Files:**
- Modify: `animation_production_lab.gd`, `timeline_controller.gd` (if needed)
- Test: reuse existing harnesses + full gate; add `tests/test_animation_input_shortcuts.tscn` (scene harness)

- [ ] **Step 1: Write the failing test** — `tests/test_animation_input_shortcuts.tscn`: instantiate lab; push `InputEventKey` for `Space` (play/pause toggle: after event, `timeline.is_playing()` true then false), `Right` (frame step: `current_time` advances by `1.0/fps`), `Escape` (emits `lab_closed` without changing scene — the harness intercepts by checking the signal, not the transition). `PASS: keyboard shortcuts drive the timeline` / FAIL.
- [ ] **Step 2: Run to verify it fails.**
- [ ] **Step 3: Implement** — root `_unhandled_input(event)` routing to `timeline.play()/pause()`, `timeline.step_time(1.0/fps)` on right/left frame-step, `exit_lab()` on Escape. Audio: set `MusicPlayer.stream` to `preload("res://assets/sound/Level_4_Background_sound.mp3")`; loop by connecting `finished` → `play()` (no autoload dependency). SFX players for button/success/error use `assets/sound/*` assets **only if the file exists** (`ResourceLoader.exists`), else stay silent — never an error path. Accessibility: read `SettingsManager` for UI scale where the other labs do; keep all text ≥ 16px and color-plus-label (no color-only instruction) — no new hard-coded colors in interaction paths. Perf (spec §8): no allocations inside `step_time` hot path (frame index + transform dict reuse scratch vars); lights capped (Task 6 already enforces).
- [ ] **Step 4: Run the full gate** — `powershell -ExecutionPolicy Bypass -File tools\verify-project.ps1` → summary must be **48 pass / 1 warn / 0 fail** (new tasks' 7 tests green; `test_full_lab_sweep.gd` still WARN-only; **no existing test may change status**).
- [ ] **Step 5: Commit** — msg `chore(animation-lab): input shortcuts, audio, accessibility, perf pass`.

---

## Cross-task type map (drift guard)

`TimelineController.frames` lives on `FrameController`; `TimelineController.current_frame_index()` reads `frames.size()`. `KeyframeController.evaluate(target_id, property_path, time) -> Variant`. `WorldController.set_object_position|rotation|scale|visible|depth|layer` all return `bool` and take `(id, value)`. `PreviewController.apply_frame` / `apply_keyframes` / `step(delta)`. `AssignmentManager.Stage` enum order is fixed (BRIEF=0 … SUBMIT=10). `ScoringController.score(...)` returns `AnimationScoreData`. `SaveController.base_dir` default `"user://animation_lab/"`. `EMCAssetLibrary.get/list/load_texture/refresh`. Do not rename these — later tasks call them by these exact names.