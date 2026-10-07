# Animation Studio Round — Composition + Docked Editor Core — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the unified 2.5D composition layer stack on the Animation Production Lab (one layer per placed object, order independent of spatial depth) plus a Layers docker, a toggleable/resizable dock layout, editor undo/redo, and layer-order persistence through the existing save — the foundation the Creative Studio editor core (and the later multi-track timeline round) builds on.

**Architecture:** `WorldController` becomes the composition owner — it already holds the registry; it gains an ordered id list (`_layer_order`), per-layer `display_name`/`element_type`/`locked`, and reorder/rename/lock ops. Render order is enforced by **transparent-pass `render_priority`** (layer index → priority, higher = in front) on every registered renderable, so composition order is camera- and z-independent; spatial `position`/`depth` semantics are untouched. New `LayersPanel` docker + thin drag-strips + TopBar toggles (studio) / stage map (guided) form the dock layout. A small `EditorHistory` (two-stack, pattern-reuse of `digital_art_lab/HistoryManager`) records every mutation. Save gains `layer_order` + per-object `display_name`/`element_type`/`locked`, back-compat: old saves load in insertion order.

**Tech Stack:** Godot 4.7, GL Compatibility renderer, GDScript (typed), no C#. Viewport 1280x720, `canvas_items` stretch.

**Spec:** `docs/superpowers/specs/2026-10-07-animation-production-lab-design.md` (revised 2026-10-07 appendix) + `docs/decisions/2026-10-07-animation-studio-round.md`.

## ⚠ Mechanism revision (approved B1 → B2) — read before Task 1

The approved design chose the "composition depth plane" (z-bias per layer). Writing the plan against the real code disproved it:

1. `tests/test_animation_world.gd:60,76-80,108` assert `node.position` mirrors the registry exactly; a bias added to z breaks the mirror contract (would need test rewrite for a cosmetic effect).
2. The depth domain is ±20 (inspector spinboxes) plus the backdrop at z=−6; a bias large enough to dominate that (`STEP ≳ 8`) pushes deep layers behind the camera at z=4 — the feature literally cannot hold from composition far-away layers.
3. The camera already rotates (`AnimationCameraController.rotate_offset`), which a fixed-axis bias cannot survive anyway.

**B2 (this plan):** every registered renderable renders through the **transparent pass with `render_priority` = layer index × step + 1** (starters stay ≤ 0), giving true painter's order decoupled from spatial z, from any camera angle. Cost: alpha blending on the few layer meshes (visually identical at alpha=1), accepted for the player's composition (10s of layers, not thousands). `node.position` semantics are untouched. Task 1 is a fail-fast probe that pins the exact API (`GeometryInstance3D.render_priority` if present, else per-material `render_priority` via `material_override`) and the priority *direction* with a pixel assertion — the engine reality gate; nothing else builds until it is green. If the probe shows the Compatibility renderer cannot honor per-object render order (it can — transparents sort by priority), stop and re-open the mechanism decision with the evidence.

## Global Constraints

- GDScript only, explicit types (`var x: Type`), project conventions from AGENTS.md; no C#.
- Gate command (must end `VERIFY OK`; baseline 72 pass / 1 warn / 0 fail — grows as tests are added):
  `powershell -ExecutionPolicy Bypass -File tools/verify-project.ps1 -Godot "C:\Users\admin\Downloads\0Jam files\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"`; `-Only <single-name>` runs one test.
- Commit rule: explicit `git add` paths (+ `.gd.uid` sidecar for every new/changed `.gd`; `.tscn` has no `.uid`), UTF-8 **no-BOM** message file, `git commit -F <file>`. **Never commit:** `project.godot`, `docs/audit-*.md`, `data/skins/*.tres`, `assets/**/*.import`.
- Tests print `PASS: …`/`FAIL: …` and `quit(0/1)`; throwaway probes must not live in `tests/`; windowed pixel tests follow `tests/test_animation_stage_visible.gd` (scene-harness, `await frame_post_draw`, save PNG under `user://`).
- Lab harnesses under test set `autosave_enabled = false` and `enable_creative_studio = false` before `add_child` (no `user://animation_lab/guided.tres` writes) unless the test explicitly backs up/restores the guided file (see `test_animation_save_roundtrip.gd`).
- Independence contract: no importing other labs' scripts/scenes; reuse at pattern level only.
- `WorldController` "never crash on missing input" contract: all setters return `false` for unknown/missing ids; new ops follow it.

## Review Focus

Inputs the spec implies but no existing test covers (each pinned in the owning task):

1. **Reorder with an eye/locked layer** — move_up/move_down/to_front/to_back must skip `locked` layers (the lock's whole point). Pinned in Task 2 (`test_animation_composition.gd`).
2. **Render order flips visually, not just in data** — two overlapping billboards change which pixel signature wins after reorder, independent of their z. Pinned in Task 1 (probe, becomes the permanent regression test).
3. **Undo after load/apply** — history must not resurrect objects a project Load removed, and must stay consistent after load. `_apply_project_data` rebuilds the world; history clears. Pinned in Task 4.
4. **A save written before this round loads** — `layer_order` missing → insertion order, `locked` missing → false; no version bump, no crash. Pinned in Task 7.
5. **Docker toggles off in guided mode** — stage map owns docker visibility in GUIDED; player toggles only in STUDIO, so a guided run can never reach a state the tests don't expect. Pinned in Task 6.

---

### Task 1: Render-order probe — prove B2 on the Compatibility renderer

**Files:**
- Create: `tests/test_animation_render_order.gd` (+ `.gd.uid`)
- Create (support): `scripts/animation_production_lab/render_order.gd` — a tiny helper that applies render priority to a node by id/layer (used by later tasks; signature below)

**Interfaces:**
- Produces: `RenderOrder.set_layer_priority(node: Node3D, layer_index: int) -> void` — sets the node's transparent-pass priority so higher `layer_index` draws in front. Direction (which property, which sign) is decided here by the probe and locked in a constant:
  `const RenderOrder.PRIORITY_STEP := 16` and `const RenderOrder.STARTER_PRIORITY := 0`.
- Consumes: nothing.

- [ ] **Step 1: Write the failing pixel test** in `tests/test_animation_render_order.gd` (extends Node, scene-harness `add_child` pattern like `test_animation_stage_visible.gd`): a `SubViewport` with its own `World3D`, two overlapping billboard `Sprite3D` at identical z (red texture, 0.5-aplha checker; green texture), camera looking down −Z. Assert: with sprite A "layer 1" and sprite B "layer 2", the pixel at overlap center is the GREEN signature after `frame_post_draw`; reorder (A layer 2 / B layer 1) → RED. Keep sprite z equal — the test proves order independent of z in the same assertion.
- [ ] **Step 2: Run to verify it fails** — `-Only test_animation_render_order`; expected FAIL (both orders render the same signature).
- [ ] **Step 3: Implement the direction/API** by experiment in `render_order.gd`: try `node.render_priority` if that property exists on `GeometryInstance3D` in 4.7 (check `godot-docs-lookup`/property presence at runtime); otherwise override materials (`StandardMaterial3D` with `transparency = TRANSPARENCY_ALPHA`, `albedo_color.a = 1.0`, `render_priority`) — sprites via `material_override`, meshes same. Higher priority must win; adjust sign/step so layer N+1 > layer N wins. Record the actual API + sign in a comment above `PRIORITY_STEP`.
- [ ] **Step 4: Run to verify it passes** — `-Only test_animation_render_order`; expected PASS.
- [ ] **Step 5: Run the whole gate** — full `verify-project.ps1`; expected `VERIFY OK` (baseline intact + 1 new pass).
- [ ] **Step 6: Commit** — `tests/test_animation_render_order.gd`, `tests/test_animation_render_order.gd.uid`, `scripts/animation_production_lab/render_order.gd`, `scripts/animation_production_lab/render_order.gd.uid`.

Skills: `godot-docs-lookup`, `3d-essentials`, `godot-testing`.

---

### Task 2: Composition layer stack in WorldController

**Files:**
- Modify: `scripts/animation_production_lab/world_controller.gd`
- Test: `tests/test_animation_composition.gd` (+ `.gd.uid`)

**Interfaces:**
- Consumes: `RenderOrder.set_layer_priority(node, layer_index)` from Task 1.
- Produces (exact signatures later tasks + the root rely on):
  - `layer_order() -> Array[String]` — ids back-to-front.
  - `layer_index(object_id: String) -> int` — −1 unknown.
  - `reorder_layer(object_id: String, to_index: int) -> bool` — clamped move; refuses `locked`; re-applies priorities for all layers.
  - `move_layer_up(object_id) -> bool`, `move_layer_down(object_id) -> bool`, `layer_to_front(object_id) -> bool`, `layer_to_back(object_id) -> bool`, `layer_forward(object_id) -> bool`, `layer_backward(object_id) -> bool` — forward/backward = +/−1 within the same… none (free stack); all skip and return `false` when the target is `locked` or the move is a no-op.
  - `rename_layer(object_id: String, name: String) -> bool`, `set_layer_locked(object_id: String, locked: bool) -> bool`.
  - Registry entries gain `display_name` (default = asset display name), `element_type` (`"2d"` for character/background, `"3d"` for prop per the Q2 reading), `locked` (default `false`).
  - `layer_summaries() -> Array[Dictionary]` — `{id, display_name, element_type, visible, locked, selected}` in layer order (LayersPanel binds to this).
  - New signal `layer_order_changed`.

- [ ] **Step 1: Write the failing test** `tests/test_animation_composition.gd` (SceneTree harness, mirrors `test_animation_world.gd` bootstrap: three starter roots + `add_asset` char/bg/prop/prop2): asserts insertion order `layer_order()`, `layer_index` per id, `move_layer_up/down/to_front/to_back/forward/backward` rearrange `layer_order()` correctly, `rename_layer` changes `display_name`, `set_layer_locked(true)` makes every reorder op return `false` and leaves the order unchanged, `remove_object` drops the id from `layer_order()`, unknown ids return `false`/−1 (never crash).
- [ ] **Step 2: Run to verify it fails** — `-Only test_animation_composition`; expected FAIL (no `layer_order()`).
- [ ] **Step 3: Implement** in `world_controller.gd`: `_layer_order: Array[String]` appended in `add_asset` (and `duplicate_object`, `_register` in Task 3), erased in `remove_object`; the op methods above operating on `_layer_order` with locked gating; `add_asset`/`duplicate_object`/`reset_object` set the new registry fields; every order-changing op calls `_apply_layer_priorities()` which calls `RenderOrder.set_layer_priority(node, index)` for each registered node, then emits `layer_order_changed` + `objects_changed`.
- [ ] **Step 4: Run to verify it passes** — `-Only test_animation_composition` then the full gate; expected PASS.
- [ ] **Step 5: Commit** — all four files.

Skills: `component-system`, `event-bus`, `gdscript-patterns`.

---

### Task 3: Starter layer ordering (starters always behind player layers)

**Files:**
- Modify: `scripts/animation_production_lab/animation_production_lab.gd` (`_register_starter_lights` → also `_register_starter_order`)

**Interfaces:**
- Consumes: `RenderOrder.STARTER_PRIORITY`; `RenderOrder.set_layer_priority(node, index)`.
- Produces: nothing new.

- [ ] **Step 1: Write the failing test** — extend `tests/test_animation_world.gd`? No — a new focused block in `tests/test_animation_layers_starter.gd`? Fold into Task 2's test instead: a scene-harness test (like `test_animation_ui_stages.gd`) that instantiates the lab, adds a registered background asset + registered character, and asserts the starter nodes (`StarterBackdrop`, `StarterCharacter`, `StarterWorkstation`) carry priority ≤ `RenderOrder.STARTER_PRIORITY` while every registered renderable's effective priority ≥ 1. Write it as part of Task 3's test file `tests/test_animation_starter_order.gd`; run expected FAIL first.
- [ ] **Step 2: Run to verify it fails** — `-Only test_animation_starter_order`.
- [ ] **Step 3: Implement** `_register_starter_order()` in the root, called from `_ready()`: resolve the three starter nodes by their committed paths and `RenderOrder.set_layer_priority(starter, RenderOrder.STARTER_PRIORITY)` (sprites/mesh; idempotent). Player layers already start at index ≥ 1 → priority ≥ PRIORITY_STEP+1 > 0.
- [ ] **Step 4: Run to verify it passes** — `-Only test_animation_starter_order` + full gate.
- [ ] **Step 5: Commit** — 3 files.

Skills: `3d-essentials`, `godot-testing`.

---

### Task 4: EditorHistory — undo/redo for composition + transforms

**Files:**
- Create: `scripts/animation_production_lab/editor_history.gd` (+ `.gd.uid`)
- Modify: `scripts/animation_production_lab/world_controller.gd` (push history per mutation)
- Modify: `scripts/animation_production_lab/ui/top_bar.gd` + `scenes/animation_production_lab/ui/top_bar.tscn` (Undo/Redo buttons)
- Modify: `scripts/animation_production_lab/animation_production_lab.gd` (wire buttons + Ctrl+Z / Ctrl+Y / Ctrl+Shift+Z)
- Test: `tests/test_animation_history.gd` (+ `.gd.uid`)

**Interfaces:**
- Produces:
  - `EditorHistory` (RefCounted): `push(undo: Callable, redo: Callable, label: String) -> void`; `undo() -> bool`; `redo() -> bool`; `can_undo() -> bool`; `can_redo() -> bool`; `clear() -> void`; signal `history_changed`.
  - `WorldController.history: EditorHistory` (owned; created at declaration).
  - `WorldController.undo() -> bool`, `WorldController.redo() -> bool` (delegate).
- Consumes: Task 2 ops + existing setters.

- [ ] **Step 1: Write the failing test** `tests/test_animation_history.gd` (SceneTree harness): push move_layer + position edit + rename + add/remove; assert `undo` restores each (order array back, position value back, name back, removed object resurrected at its layer, added object gone), `redo` re-applies, `history_changed` fires, `undo` returns `false` on empty. Include the Review-Focus #3 case: after a world rebuild equivalent (`_apply_project_data` path is Task 7 — here: simulate by calling `remove_object` for all + `clear()`), stale undo must not resurrect.
- [ ] **Step 2: Run to verify it fails** — `-Only test_animation_history`.
- [ ] **Step 3: Implement** — `editor_history.gd` two-stack with closures; in `world_controller.gd`, wrap each mutating op (position/rotation/scale/depth/visible, add/remove/duplicate, rename/lock, all reorder ops) with `history.push` closures that capture old/new snapshots (`_registry` entry + `_layer_order` slice); new `undo()`/`redo()` on WorldController. TopBar gains UndoButton/RedoButton (visible in Studio mode only) emitting `undo_requested`/`redo_requested`; root wires them + `KEY_Z`/`KEY_Y` (with `KEY_CTRL`; `Shift+Z` → redo) in `_unhandled_input`, guarded so a focused LineEdit still swallows text keys (existing comment pattern).
- [ ] **Step 4: Run to verify it passes** — `-Only test_animation_history` + `-Only test_animation_input_shortcuts` (regression: new hotkeys don't disturb Space/arrows/Escape) + full gate.
- [ ] **Step 5: Commit** — 6 files.

Skills: `component-system`, `gdscript-advanced`, `input-handling`, `godot-ui`.

---

### Task 5: LayersPanel docker

**Files:**
- Create: `scenes/animation_production_lab/ui/layers_panel.tscn`, `scripts/animation_production_lab/ui/layers_panel.gd` (+ `.gd.uid`); layers_panel.gd is class_name-less (project convention)
- Modify: `scenes/animation_production_lab/animation_production_lab.tscn` (instance under `UI`, before TopBar)
- Modify: `scripts/animation_production_lab/animation_production_lab.gd` (preload const, `@onready`, `_wire_panels`, `show_stage_ui` → visible at `STAGING..LIGHTING` in guided + in `_enter_studio_mode`; `_on_layers_*` handlers; `_on_objects_changed` also refreshes layers)
- Test: `tests/test_animation_layers_panel.gd` (+ `.gd.uid`)

**Interfaces:**
- Consumes: `WorldController.layer_summaries()`, `selected()`, ops from Task 2; `EMCAssetLibrary.list()` for Add.
- Produces (signals): `layer_selected(id)`, `add_requested`, `delete_requested(id)`, `duplicate_requested(id)`, `rename_requested(id, name)`, `visibility_toggled(id)`, `lock_toggled(id)`, `move_up_requested(id)`, `move_down_requested(id)`, `to_front_requested(id)`, `to_back_requested(id)`, `forward_requested(id)`, `backward_requested(id)`; setters `set_layers(summaries: Array[Dictionary])`, `set_selected(id: String)`.

- [ ] **Step 1: Write the failing test** — `tests/test_animation_layers_panel.gd` (scene-harness): instantiate lab, `go_to(STAGE_STAGING)`, assert `layers_panel.visible`; `set_layers` populates ItemList (names + element_type tag in label); a button click emits its signal (`move_up_requested` after selecting row 1, etc.); `world.layer_summaries()` round-trips through `set_layers`; selecting a row → `select` on world; `world.select()` → row highlights.
- [ ] **Step 2: Run to verify it fails** — `-Only test_animation_layers_panel`.
- [ ] **Step 3: Implement** — panel scene mirrors `inspector_panel.tscn` structure (Backdrop + Card + VBox): Title "LAYERS", ItemList (`name — 2D/3D`), reorder row (↑ ↓ ⤒ ⤓ ⇧ ⇩), CRUD row (Add, Duplicate, Rename, Delete), eye/lock toggles for the selection; keyboard: Up/Down navigate (existing), `[`/`]` move order, `H` hide, `L` lock — via the same `_unhandled_input` pattern; disabled states when nothing selected. Root wires all signals to the Task 2 ops (delete → `remove_object`, duplicate → `duplicate_object`, add → `_on_asset_add_requested` reuse with the library's selected asset, rename → `rename_layer`, vis/lock → existing/new setters) and refreshes `set_layers(world.layer_summaries())` on `objects_changed`/`layer_order_changed`/`selection_changed`.
- [ ] **Step 4: Run to verify it passes** — `-Only test_animation_layers_panel` + `-Only test_animation_ui_stages` (regression) + `-Only test_animation_ui_layout` + full gate.
- [ ] **Step 5: Commit** — all new/modified files.

Skills: `godot-ui`, `input-handling`, `event-bus`.

---

### Task 6: Dock layout — resize strips + TopBar toggles (studio)

**Files:**
- Create: `scripts/animation_production_lab/ui/dock_resize_strip.gd` (+ `.gd.uid`)
- Modify: `scenes/animation_production_lab/ui/top_bar.tscn` + `top_bar.gd` (4 check buttons: Layers/Inspector/Assets/Timeline + `dock_toggle_requested(name, visible)`, `set_dock_toggle(name, on)`, shown in Studio only)
- Modify: `scenes/animation_production_lab/animation_production_lab.tscn` (LayersPanel anchored left column; vertical strip right of it; horizontal strip above Timeline)
- Modify: `scripts/animation_production_lab/animation_production_lab.gd` (`_enter_studio_mode` shows toggles + LayersPanel; handler `_on_dock_toggle`)
- Test: `tests/test_animation_dock_layout.gd` (+ `.gd.uid`)

**Interfaces:**
- Produces: `DockResizeStrip` — `@export target: NodePath` (a panel), `@export axis` (0 vertical / 1 horizontal), `@export side` (+1/−1); drag updates the target's `anchor_left`/`anchor_right` (vertical) or `anchor_top`/`anchor_bottom` (horizontal) offsets.

- [ ] **Step 1: Write the failing test** — `tests/test_animation_dock_layout.gd` (scene-harness): in Studio mode (boot with a saved `guided_completed` flag via the backup pattern OR call `unlock_creative_studio()` after setting the flag — use the `test_animation_save_roundtrip` backup pattern), assert LayersPanel + toggles visible; toggling Layers off hides the panel and keeps every UI child inside the window (`_inside` copied from `test_animation_ui_layout.gd`); simulating a strip drag (call its `_apply(delta)` with a 40px delta) widens the LayersPanel by 40 while Inspector stays put; in GUIDED mode the toggles are hidden (Review-Focus #5).
- [ ] **Step 2: Run to verify it fails** — `-Only test_animation_dock_layout`.
- [ ] **Step 3: Implement** — strips as thin (6px) `Control` strips with `mouse_filter = STOP` and `_gui_input` drag → `_apply(delta)`; clamp so panels never collapse below 120px and never leave the window. TopBar toggles (check buttons) emitted only in Studio (`set_dock_toggles_visible(bool)`); root `_on_dock_toggle(name, on)` shows/hides the pane; in guided, `show_stage_ui` remains the only driver (no toggle interaction).
- [ ] **Step 4: Run to verify it passes** — `-Only test_animation_dock_layout` + `-Only test_animation_ui_layout` + `-Only test_animation_ui_stages` + full gate.
- [ ] **Step 5: Commit** — 5 files.

Skills: `godot-ui`, `responsive-ui`, `input-handling`.

---

### Task 7: Save/load — layer_order + layer metadata, back-compat

**Files:**
- Modify: `scripts/animation_production_lab/data/animation_lab_save_data.gd` (`@export var layer_order: Array[String] = []`)
- Modify: `scripts/animation_production_lab/save_controller.gd` (`_sanitize` gains `layer_order`)
- Modify: `scripts/animation_production_lab/animation_production_lab.gd` (`_collect_scene_objects` adds `display_name`/`element_type`/`locked`; `collect_save_data` adds `layer_order` = ordered **scene-object ids**; `_apply_project_data` re-applies order by mapping old ids → new ids via traversal index, then `_apply_layer_priorities()`)
- Test: extend `tests/test_animation_save_roundtrip.gd` (+ back-compat case)

**Interfaces:**
- Consumes: Task 2 ops (`layer_order()`, `reorder_layer`), `RenderOrder`.
- Produces: persisted shape — `layer_order` stores the `"id"` values of `scene_objects` entries (the same ids `_collect_scene_objects` already writes); on load, traversal index maps old id → regenerated id.

- [ ] **Step 1: Write the failing test** — extend `test_animation_save_roundtrip.gd`: after staging 3 objects (char, bg, prop), reorder (char to front), set `rename_layer` + `set_layer_locked`; assert `collect_save_data().layer_order` equals `[id_char, id_bg, id_prop]` reordered, and entries carry the new fields; `_apply_project_data(snapshot)` restores order (use `layer_order()` after apply) + names + locks. **Back-compat case** (Review-Focus #4): a hand-built `AnimationLabSaveData` without `layer_order` (delete the key) must load/apply in insertion order with `locked == false`.
- [ ] **Step 2: Run to verify it fails** — `-Only test_animation_save_roundtrip`.
- [ ] **Step 3: Implement** — collect/apply per Interfaces; `_apply_project_data` maps: while adding entries, record `old_id → new_id` by array index of `scene_objects`; after all adds, for each saved id in `layer_order` (falling back to insertion order when absent), `world.reorder_layer(new_id_for(old_id), i)`; finally `_apply_layer_priorities()`. `_sanitize` passes `layer_order` through `is Array`.
- [ ] **Step 4: Run to verify it passes** — `-Only test_animation_save_roundtrip` + `-Only test_animation_save` + full gate.
- [ ] **Step 5: Commit** — 4 files.

Skills: `save-load`, `resource-pattern`, `gdscript-patterns`.

---

### Task 8: Integration hardening + whole-branch review

**Files:**
- Modify: `docs/superpowers/specs/2026-10-07-animation-production-lab-design.md` (appendix — design/fork record)
- Modify: `docs/decisions/2026-10-07-animation-studio-round.md` (mechanism row → B2 + probe evidence)

- [ ] **Step 1: Run the full gate** — expected `VERIFY OK` with **zero** new warnings and ≥ 1 more pass than baseline.
- [ ] **Step 2: Godot code review** — load `godot-code-review`, run its checklist over this round's diffs; fix any criticals/nits found (re-run gate).
- [ ] **Step 3: Update spec appendix + decision record** — B2 revision, LayersPanel/dock behavior, guided vs studio visibility, save shape.
- [ ] **Step 4: Commit** — docs + any review fixes (explicit paths; the two docs are committable — never the audit files).

Skills: `godot-code-review`, `godot-testing`.