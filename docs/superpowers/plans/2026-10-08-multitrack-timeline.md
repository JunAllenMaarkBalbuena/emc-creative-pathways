# Multi-track Timeline Editor — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the Animation Production Lab's Timeline docker into a real timeline editor — per-target keyframe lanes under a time ruler, direct manipulation (add / move / delete keys, slide / duplicate selection-span clips), snap-to-frame, and zoom — in both the guided flow (from the FRAMES stage) and the Creative Studio, with every edit undoable and the save format untouched.

**Architecture:** A pure `TimelineLaneModel` (RefCounted) derives lanes from the existing flat keyframe list (`KeyframeController.keyframes` stays the source of truth) grouped by target: frame strip + one lane per world layer (stack order) + Camera lane + one lane per light. A custom-drawn `TimelineEditor` Control (ruler + lanes in one `_draw` pass, no per-frame allocation) handles all touch/mouse gestures and emits typed requests; the root routes them to new index-based `KeyframeController` primitives that push `EditorHistory` (closures restore the array **and** re-emit `keyframes_changed`, the verified world convention — so undo/redo refreshes the editor through the normal signal path). Playback, `evaluate_review()`, scoring, and `AnimationLabSaveData` are untouched.

**Tech Stack:** Godot 4.7, GL Compatibility renderer, GDScript (explicit types), no C#. Viewport 1280x720, `canvas_items` stretch.

**Spec:** `docs/superpowers/specs/2026-10-08-multitrack-timeline-design.md` + `docs/decisions/2026-10-08-multitrack-timeline.md`. The spec's §10 phases map 1:1 to Tasks 1–5.

## Global Constraints

- GDScript only, explicit types (`var x: Type`), AGENTS.md conventions; no C#. The AGENTS.md skills table wins: load the listed domain skills per task and **state the pattern you chose and the alternative you rejected** before implementing (both round-1 and this round apply the rule).
- Gate command (must end `VERIFY OK`; baseline after this round's docs commit is 78 pass / 1 warn / 0 fail, grows +1 per new test): `powershell -ExecutionPolicy Bypass -File tools/verify-project.ps1 -Godot "C:\Users\admin\Downloads\0Jam files\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"`. `-Only <single-name>` runs one test (`.tscn` inferred when the stem has one).
- Test kinds: `*.gd extends SceneTree` run via `--script`; `*.tscn` harnesses whose root script `extends Node` print `PASS: …` / `FAIL: …` and call `get_tree().quit(0|1)`, killed by the `--quit-after 600` budget — a harness needs **at least one PASS marker** to count. `test_full_lab_sweep.gd` is the sole known-WARN; never "fix" it.
- Commit rule: explicit `git add` paths (+ `.gd.uid` sidecar for every **new** `.gd`; existing `.gd` and all `.tscn` have no sidecar), UTF-8 **no-BOM** message file in `.superpowers/sdd/2026-10-08-multitrack-timeline/commit-taskN.txt`, `git commit -F <file>`. **Never commit:** `project.godot`, `docs/audit-*.md`, `data/skins/*.tres`, `assets/**/*.import`.
- Lab harnesses set `autosave_enabled = false` and `enable_creative_studio = false` before `add_child` unless the test needs studio (the dock test sets `enable_creative_studio = true`, mirroring `test_animation_dock_layout.gd`).
- Independence contract: no importing other labs' scripts/scenes; reuse at pattern level only.
- Untouched (contract): `TimelineController`, `FrameController`, `PreviewController` (incl. `evaluate_review()` 10-item checklist), `AnimationFrameData`/`AnimationKeyframeData`, `AnimationLabSaveData` shape, scoring, `AnimationControls` docker, and `_on_history_changed` (stays TopBar-button-only). `evaluate_review()` must stay green at the end.
- Time invariants (copy verbatim from spec §8): all time values clamp to `[0, duration]`; duration floor `0.01` (existing `set_duration`); fps ∈ [1, 60] (existing); snap rounds to the nearest `1/fps` boundary; ops never exceed `[0, duration]`.
- `KeyframeController` "never crash on missing input" contract: every new op returns `false` for invalid indices / empty input.
- Throwaway probes must not live in `tests/` and are never committed; results go in `.superpowers/sdd/2026-10-08-multitrack-timeline/progress.md`.
- Per-task cycle: RED → `-Only` fail → implement → `-Only` pass → full gate `VERIFY OK` → ledger line → commit. Push to `origin/progress-two-emcsem` only after Task 5 (finishing-a-development-branch governs).

## Review Focus

Inputs the spec implies but no existing test covers (each pinned in the owning task):

1. **Docker with many layers** — lane overflow must clip inside the editor rect and every UI child stays inside the viewport; the docker never grows or crashes. Pinned in Task 3 (gestures test).
2. **Orphan / older-save keys + undo after load** — keys whose target is gone render no lane but stay in the flat list and playback skips them; undo after a load can never un-add loaded keys (loader is quiet via `set_all`). Pinned in Task 1 (ops test) + Task 4 (dock test wiring).
3. **Camera lane key authorship** — keys authored with arbitrary `target_id`s (saves/tests use `"cam"`) still appear in and slide/duplicate within the Camera lane; playback ignores the id (verified: `_apply_camera` reads only `property_path`). Pinned in Task 2 (lane model) + Task 3 (span path through the resolved Camera lane).
4. **Snap toggled mid-gesture** — snapping never applies to an in-progress drag; the gesture captures snap state at drag start. Pinned in Task 3.
5. **Zoom bounds and ruler stability** — `pps` clamps to [24, 240], the draw offset keeps `t = 0` at or left of the left edge, and ruler labels decimate so they never overlap. Pinned in Task 3.

---

### Task 1: KeyframeController editing primitives + history + `set_all`

**Files:**
- Modify: `scripts/animation_production_lab/keyframe_controller.gd` (add methods + `history`/`timeline` vars; keep all existing signatures)
- Modify: `scripts/animation_production_lab/animation_production_lab.gd` (loader swap: `_apply_project_data` keyframe loop → `set_all`, ~8 lines)
- Test: `tests/test_timeline_editor_ops.gd` (+ `.gd.uid`)

**Interfaces:**
- Consumes: `EditorHistory` (existing: `push(undo: Callable, redo: Callable, label: String)`, `undo() -> bool`, `redo() -> bool`, signal `history_changed`); `TimelineController` (existing: `duration`, `fps`); `AnimationKeyframeData` (existing: `time`, `target_id`, `target_type`, `property_path`, `value`, `interpolation`).
- Produces (exact — Tasks 3–4 rely on these):
  - `var history: EditorHistory` (default `null` — ops push only when non-null, so every existing bare-controller test stays untouched).
  - `var timeline: TimelineController` (default `null` — when unset, clamp is floor-at-0 only).
  - `func move_key(index: int, time: float) -> bool` — clamp, set `keyframes[index].time`, `_sort()`, emit `keyframes_changed`. `false` only on invalid index.
  - `func remove_keys(indices: Array[int]) -> bool` — remove by flat-list index (internally descending so indices stay valid), emit. `false` on empty/invalid.
  - `func slide_keys(indices: Array[int], delta: float) -> bool` — add `delta` to each key's time, clamp `[0, duration]`, `_sort()`, emit. `false` on empty/invalid.
  - `func duplicate_keys(indices: Array[int], offset: float) -> bool` — copy each key to `time + offset` (clamped `[0, duration]`, same `target_id`/`property_path`), `_sort()`, emit. `false` on empty/invalid. `offset == 0` duplicates in place.
  - `func set_all(keys: Array[AnimationKeyframeData]) -> void` — `keyframes.assign(keys)`, `_sort()`, emit once, **no history** (quiet loader path; undo after a load must not touch loaded keys).
  - `add_keyframe` / `remove_keyframe` gain the same null-safe history push (signatures unchanged — every existing caller, incl. tests, keeps working).
- History closure shape (spec §4, verified world convention): push with `undo = func(): keyframes.assign(prev); keyframes_changed.emit()` and redo mirroring the new array + emit; `prev` is a `duplicate()` copy. Closures capture only `duplicate()` arrays plus the long-lived controller — never scene nodes. Labels: `"Move Key"`, `"Delete Keys"`, `"Slide Keys"`, `"Duplicate Keys"`, `"Add Key"`, `"Delete Key"`.

- [ ] **Step 1: Write the failing test** `tests/test_timeline_editor_ops.gd` (`extends SceneTree`, harness style of `test_animation_keyframes.gd`): build a bare `TimelineController` (fps 12, duration 5.0) + `EditorHistory`, wire `ctrl.timeline`/`ctrl.history`, seed keys via `add_keyframe`. Assert:
  - `move_key` re-times and keeps the array sorted; moving `time = 9.0` clamps to `5.0`; invalid index returns `false`.
  - `remove_keys([i, j])` removes both (indices into the pre-call list) and emits.
  - `slide_keys([i, j], 0.5)` adds 0.5 to both, clamps at `duration`, packs (no collision rejection needed); empty array returns `false`.
  - `duplicate_keys([i], 0.0)` doubles the key (in place); `duplicate_keys([i], 1.0)` copies at `time + 1.0`; a copy clamping past `duration` lands at `duration`; works for a `TARGET_CAMERA` key whose `target_id` is `"cam"` (not `"camera"`).
  - Every op pushes history when wired: after each op `history.can_undo()` is true; `undo()` restores the pre-op times/array and `redo()` re-applies; ops on a bare controller (no `history`) push nothing.
  - **Review-Focus #2 (controller half):** `set_all(built)` emits once, pushes nothing (`history.can_undo()` stays false), and `undo()` after it leaves keyframes untouched.
- [ ] **Step 2: Run to verify it fails** — `-Only test_timeline_editor_ops`; expected FAIL (`move_key` not defined).
- [ ] **Step 3: Implement** in `keyframe_controller.gd`: the five methods + `history`/`timeline` vars + history pushes on `add_keyframe`/`remove_keyframe`/the new mutators, per the closure shape above. Clamp via `clampf(t, 0.0, timeline.duration)` when `timeline != null`, else `maxf(t, 0.0)`. Keep `_sort()`/`_before` as-is. Then the **loader swap in the same commit** (no regression window — a load must never poison the fresh history): in `_apply_project_data` replace the `keyframes.keyframes.clear()` + `add_keyframe` loop (currently after `world.history.clear()` at line ~798) with building an `Array[AnimationKeyframeData]` from the save dicts and calling `keyframes.set_all(built)` — no history entries, one `keyframes_changed` emit.
- [ ] **Step 4: Run to verify it passes** — `-Only test_timeline_editor_ops`; expected PASS.
- [ ] **Step 4b: Regression — save round-trip** — `-Only test_animation_save_roundtrip`; expected PASS (a load still rebuilds the identical keyframes array through `set_all`).
- [ ] **Step 5: Run the whole gate** — full `verify-project.ps1`; expected `VERIFY OK` (78 + 1 = **79 pass / 1 warn / 0 fail**) — with the loader swapped, the existing full-lab suites (save round-trip, guided flow, preview, scoring) all stay green against the quiet load path.
- [ ] **Step 6: Commit** — `scripts/animation_production_lab/keyframe_controller.gd`, `scripts/animation_production_lab/animation_production_lab.gd`, `tests/test_timeline_editor_ops.gd`, `tests/test_timeline_editor_ops.gd.uid`, via `commit-task1.txt`. Also add the Task 1 line to `.superpowers/sdd/2026-10-08-multitrack-timeline/progress.md`.

Skills: `gdscript-patterns`, `gdscript-advanced`, `godot-testing`.

---

### Task 2: TimelineLaneModel + `LightingController.light_ids()`

**Files:**
- Create: `scripts/animation_production_lab/ui/timeline_lane_model.gd` (+ `.gd.uid`)
- Modify: `scripts/animation_production_lab/lighting_controller.gd` (add one method, nothing else)
- Test: `tests/test_timeline_lane_model.gd` (+ `.gd.uid`)

**Interfaces:**
- Consumes: `WorldController.layer_order() -> Array[String]`, `get_object(id) -> Dictionary` (keys `display_name`, `locked`), `all_objects()` (bootstrap); `KeyframeController.keyframes` + `TARGET_OBJECT`/`TARGET_CAMERA`/`TARGET_LIGHT` consts; `FrameController.frames`; `TimelineController.fps`/`duration`; `LightingController.light_ids()` (new).
- Produces (exact — Task 3 uses all of these; class_name-less, referenced by preload):
  - `const KIND_FRAMES := 0` / `KIND_OBJECT := 1` / `KIND_CAMERA := 2` / `KIND_LIGHT := 3` (single source of truth for lane kinds, spec §3).
  - Injectable plain vars (set by root/test): `world: WorldController`, `keyframes: KeyframeController`, `frames: FrameController`, `timeline: TimelineController`, `lighting: LightingController`.
  - `func lanes() -> Array[Dictionary]` — spec §3 shape: frame strip lane, one lane per `world.layer_order()` entry (index 0 = back of stack), Camera lane, one lane per `lighting.light_ids()`; each lane has `id`, `kind` (int const), `label`, `keys` (per-key `{target_id, property_path, time, interpolation}`, sorted by time), objects also `locked`. Membership: object/light lanes match by `target_type` **and** `target_id`; the Camera lane matches `TARGET_CAMERA` by type only (arbitrary authored ids — verified). Orphan keys (target gone) are excluded from lanes but stay in the flat list.
  - `func snap_time(time: float) -> float` — `clampf(roundf(time * fps) / fps, 0.0, duration)`.
  - `func frame_boundaries() -> Array[float]` — `[i / fps for i in frames.frames.size()]` (the fps tempo grid — do NOT read `AnimationFrameData.duration`).
  - `func range_keys(lane_id: String, start: float, end: float) -> Array[int]` — flat indices of that lane's keys with `start <= time <= end`.
  - `func key_index_at(lane_id: String, time: float, tolerance: float) -> int` — index of the lane's key nearest `time` within `tolerance`, else `-1`.
  - `LightingController.light_ids() -> Array[String]` — `_lights.keys()` (Dictionary insertion order = registration order).
- Bootstrap for the test: mirror `test_animation_composition.gd` (three starter roots + `add_asset` char/bg/prop, then `register_existing` a light + `frames.add_frame` a couple, `keyframes.add_keyframe` seeds across object/camera/light lanes + one orphan id never added to the world).

- [ ] **Step 1: Write the failing test** `tests/test_timeline_lane_model.gd` (`extends SceneTree`): assert lane order = frames strip, then `world.layer_order()` back-to-front, then Camera, then lights; reordering the world (`move_layer_up`) re-orders the object lanes on the next `lanes()` call; object/light membership requires matching id + type; the Camera lane collects a key authored as `"cam"`/`TARGET_CAMERA` (**Review-Focus #3**) and `range_keys`/`key_index_at` resolve that key; an orphan key (`target_id` never registered) appears in no lane but is still in `keyframes.keyframes` (**Review-Focus #2**); `snap_time(0.37)` at fps 12 → `0.333…` and `snap_time(-1)`/`snap_time(99)` clamp to `[0, duration]`; `frame_boundaries()` = `[0, 1/12, 2/12, …]`.
- [ ] **Step 2: Run to verify it fails** — `-Only test_timeline_lane_model`; expected FAIL (script missing).
- [ ] **Step 3: Implement** `timeline_lane_model.gd` (pure functions over the injected refs; no signals/nodes) + `light_ids()` in `lighting_controller.gd`.
- [ ] **Step 4: Run to verify it passes** — `-Only test_timeline_lane_model`; expected PASS.
- [ ] **Step 5: Run the whole gate** — expected `VERIFY OK` (**80 pass / 1 warn / 0 fail**).
- [ ] **Step 6: Commit** — the two `.gd` + two `.gd.uid` + test + test `.uid`, via `commit-task2.txt`; ledger line.

Skills: `gdscript-patterns`, `godot-testing`.

---

### Task 3: TimelineEditor widget + TimelinePanel docker scene + gestures

**Files:**
- Create: `scenes/animation_production_lab/ui/timeline_editor.tscn`, `scripts/animation_production_lab/ui/timeline_editor.gd` (+ `.gd.uid`)
- Create: `tests/test_timeline_editor_gestures.gd` (+ `.gd.uid`), `tests/test_timeline_editor_gestures.tscn`
- Modify: `scenes/animation_production_lab/ui/timeline_panel.tscn` (instance editor + toolbar row), `scripts/animation_production_lab/ui/timeline_panel.gd` (bind + forwarding + toolbar wiring)
- Probe (throwaway, NEVER committed): `tools/probes/timeline_editor_probe.gd` + minimal scene — windowed look/feel; results (incl. screenshots via `godot-agent-vision`) recorded in the ledger.

**Interfaces:**
- Consumes: Task 1 (signals/method names for the flow it will emit), Task 2 (model: kinds, `lanes()`, `snap_time`, `frame_boundaries`, `range_keys`, `key_index_at`), panel conventions (`test_animation_dock_layout.gd` for scene-harness style).
- Produces (exact — Task 4 connects to all of these):
  - `TimelineEditor` (Control, class_name-less, no children — one `_draw` pass):
    - `func set_sources(world, keyframes, frames, timeline, lighting) -> void` — stores refs, creates/updates its internal `TimelineLaneModel`, `refresh()`.
    - `func refresh() -> void` — rebuild lanes from the model, `queue_redraw()`; clears per-lane selections when the lane set (ids) changed.
    - `func set_snap(on: bool) -> void`; `func get_snap() -> bool`; `func snap_time(t: float) -> float` (model delegate); `func get_pps() -> float`.
    - Playback redraw (spec §7): when sources are wired, subscribe to `timeline.time_changed` → move the playhead x + `queue_redraw()` only (never rebuild lanes); `refresh()` is the only path that rebuilds.
    - `func zoom_in() -> void` / `zoom_out() -> void` — `pps *= 1.5` / `/= 1.5`, clamped [24, 240] (**Review-Focus #5**), anchored so the time under the playhead keeps its x (buttons) / under the pointer (wheel, pinch); draw offset `minf(0, anchor_x - anchor_time * pps)` keeps `t = 0` ≤ left edge.
    - `func delete_selection() -> void` — emits `keys_remove_requested(indices)` for the current selection; no-op (no signal) when empty (**Review-Focus #1b**).
    - `func get_playhead_time() -> float` (test hook for the §7 redraw assertion).
    - Signals (spec §5, exact payloads): `lane_pressed(lane_id: String, lane_kind: int)`, `playhead_requested(time: float)`, `key_add_requested(lane_id: String, lane_kind: int, time: float)`, `key_move_requested(index: int, from_time: float, to_time: float)`, `keys_remove_requested(indices: Array[int])`, `span_slide_requested(indices: Array[int], delta: float)`, `span_duplicate_requested(indices: Array[int], offset: float)`, `snap_toggled(on: bool)`.
    - `_draw` (spec §5, px values verbatim): ruler 32px (minor tick per frame, label every 5th frame decimated so labels never overlap — at least 48px apart), lane rows 24px with 96px label gutter, key ticks 3px with the spec palette (`position #4caf50`, `rotation #2196f3`, `scale #ffc107`, `visible #9c27b0`, camera `#00bcd4`, light `#ff7043`), selection tinted band, playhead line + handle; world-time → x is `x = offset + time * pps`; lanes draw only within `size.y` (**Review-Focus #1** — clip, never overflow).
    - Touch input in `_gui_input` (spec §5 gestures): tap-vs-drag 8px threshold; two-finger pinch (track two `InputEventScreenTouch` indices, distance delta → zoom); `accept_event()`.
  - `TimelinePanel`: `var editor: Control` (`%TimelineEditor`); `func bind(world, keyframes, frames, timeline, lighting) -> void` (forwards to editor); forwards the editor's 8 signals under the same names via lambdas in `_ready`; toolbar `%SnapToggle` (CheckButton, `button_pressed = true`), `%ZoomIn`, `%ZoomOut`, `%DeleteSelection` wired to `editor.set_snap` / `zoom_in` / `zoom_out` / `delete_selection` and the `snap_toggled` signal.
- Gesture → signal rules (spec §5, verbatim behavior): tap lane → `lane_pressed(id, kind)`; tap ruler → `playhead_requested(snap_time(x))`; double-tap empty lane → `key_add_requested(id, kind, snap_time(x))`; drag a key tick → `key_move_requested(index, from, to)` (index resolved once at drag start via `key_index_at`; `to = snap_time(x)` when snap on); drag empty lane → marquee selection whose keys come from `range_keys`; drag inside a selection → `span_slide_requested(indices, dx_seconds)`; duplicate gesture → `span_duplicate_requested(indices, drop_seconds - selection_start)`; Delete/Backspace + toolbar → `delete_selection()`; wheel over ruler / pinch → zoom.

- [ ] **Step 1: Write the failing test** `tests/test_timeline_editor_gestures.gd` (`extends Node`, harness) + `.tscn`: mount `timeline_panel.tscn`, `bind(...)` bare controllers bootstrapped as in Task 2 (2 objects, camera key authored `"cam"`, 1 light, 2 frames; `timeline` fps 12 / duration 5). Set the editor rect explicitly (`editor.size = Vector2(800, 220)`) before synthesizing. Assert by calling `editor.call("_gui_input", event)` with constructed `InputEventMouseButton`/`InputEventMouseMotion`/`InputEventScreenTouch`/`InputEventScreenDrag`:
  - tap a lane row → `lane_pressed` with the right `(id, kind)`; tap the ruler at x=96 (pps default 96) → `playhead_requested(1.0)` (snapped).
  - double-tap empty lane at x=48 → `key_add_requested(id, kind, 0.5)`.
  - drag a key tick from x=48 to x=96 → `key_move_requested(index, 0.5, 1.0)` with the correct flat index; with snap off → raw `1.0` time for x=90.
  - marquee across a lane → selection band; drag inside it → `span_slide_requested(indices, dx_seconds)` where `indices` match `range_keys` for the band and the **Camera lane's** `"cam"`-authored key is included (**Review-Focus #3**).
  - Delete with a selection → `keys_remove_requested(indices)`; Delete with none → no signal (**Review-Focus #1b**).
  - wheel-up over the ruler → `get_pps()` grows but stays ≤ 240 after many steps; `zoom_in()` at 240 doesn't move (**Review-Focus #5**); the `t=0` draw offset never exceeds 0.
  - reasonably-spaced taps (movement < 8px) are taps, a >8px move becomes a drag (**threshold**); synthetic second tap within the double-tap window doubles.
  - **Playback redraw (spec §7):** after `bind(...)`, emitting `timeline.time_changed(3.0)` moves the playhead (expose `get_playhead_time()`) and does **not** rebuild lanes (expose a `refresh()` call counter or assert lane object identity), while a `keyframes_changed` emission does rebuild.
  - **Review-Focus #4:** start a key drag with snap on, toggle snap off mid-drag, release — the emitted `to` is still snapped (state captured at drag start).
  - **Review-Focus #1:** register 10 objects → `lanes()` has 10+ lanes, the editor's rect is unchanged and every `TimelinePanel` descendant stays inside the viewport; `_draw` never throws for an editor shorter than the lane stack.
- [ ] **Step 2: Run to verify it fails** — `-Only test_timeline_editor_gestures`; expected FAIL (scene drill: `%TimelineEditor` missing).
- [ ] **Step 3: Implement the canvas** — `timeline_editor.tscn` + `timeline_editor.gd` draw path first (ruler/lanes/keys/selection/playhead, zoom + offset + clipping); run the test to see gesture asserts fail, then add `_gui_input` handling + selection + signals, then wire the panel scene (editor instance + toolbar) + `bind`/forwarding in `timeline_panel.gd`. (One task, one test, one commit — the widget is one unit; a reviewer accepts or rejects it whole.)
- [ ] **Step 4: Run to verify it passes** — `-Only test_timeline_editor_gestures`; expected PASS.
- [ ] **Step 5: Run the whole gate** — expected `VERIFY OK` (**81 pass / 1 warn / 0 fail**).
- [ ] **Step 6: Windowed feel probe** — run the throwaway probe windowed (NOT headless, NOT in `tests/`): check ruler labels, key tick colors/legend, selection band, zoom-at-playhead feel, touch drag; screenshot via `godot-agent-vision`; record verdict + screenshots path in the ledger. Delete the probe or leave it gitignored — never commit it.
- [ ] **Step 7: Commit** — 4 new files (+ the two new `.gd.uid`), 2 modified files (no uids), via `commit-task3.txt`; ledger line.

Skills: `godot-ui`, `input-handling`, `2d-essentials` (custom drawing), `gdscript-advanced` (no per-frame allocation), `responsive-ui`, `godot-testing`, `godot-agent-vision` (probe).

---

### Task 4: Root wiring + guided gating pass

**Files:**
- Modify: `scripts/animation_production_lab/animation_production_lab.gd` (wiring + handlers + injection; the loader swap landed in Task 1)
- Create: `tests/test_timeline_editor_dock.gd` (+ `.gd.uid`), `tests/test_timeline_editor_dock.tscn`

**Interfaces:**
- Consumes: Task 1 (`keyframes.history`, `keyframes.timeline`, `move_key`, `remove_keys`, `slide_keys`, `duplicate_keys`, `set_all`, `add_keyframe`), Task 2 (KIND_* consts), Task 3 (panel `bind`, `editor` accessor, the 8 forwarded signals, `editor.refresh()`).
- Produces (root-side, exact names):
  - `_wire_panels` additions (spec §6, verbatim): panel signal connects for all 8 editor signals; refresh subscriptions `keyframes.keyframes_changed`, `frames.frames_changed`, `lights.lights_changed`, `world.objects_changed`, `world.layer_order_changed` → `timeline_panel.editor.refresh()`; `keyframes.history = world.history`; `keyframes.timeline = timeline`; `timeline_panel.bind(world, keyframes, frames, timeline, lighting)`.
  - Handlers: `_on_timeline_lane_pressed(id, kind)` (KIND_OBJECT → `world.select(id)`, KIND_LIGHT → `lighting.select(id)`, else no-op), `_on_timeline_playhead(t)` → `timeline.scrub(t - timeline.current_time)`, `_on_timeline_key_add(id, kind, t)` → `add_keyframe` with per-kind target_id/type and the §6 default value (evaluate first, live value fallback: `world.get_object(id).position` / `camera.camera().position` / light node position), `_on_timeline_key_move(index, _from, to)` → `move_key`, `_on_timeline_keys_remove(indices)` → `remove_keys`, `_on_timeline_span_slide` / `_span_duplicate` → `slide_keys` / `duplicate_keys`, `_on_timeline_snap_toggled(on)` → `editor.set_snap(on)` (root stores the bool for future persistence).
  - Loader quietness: guaranteed by Task 1's `set_all` swap; Task 4 only asserts it (Step 1).
  - Stage map / `_on_history_changed` / `show_stage_ui` / `_enter_studio_mode`: **unchanged** (guided gating already shows the panel from FRAMES onward; the editor renders with the panel).

- [ ] **Step 1: Write the failing test** `tests/test_timeline_editor_dock.gd` (`extends Node`, harness, mirror of `test_animation_dock_layout.gd`: `enable_creative_studio = true`, boot, `await` frames) + `.tscn`. Assert:
  - The lab's `timeline_panel` contains `%TimelineEditor` + the 4 toolbar nodes; panel visible in Studio after `unlock_creative_studio()`.
  - Routing: `timeline_panel.lane_pressed.emit("obj_2", TimelineLaneModel.KIND_OBJECT)` → `world.selected() == "obj_2"`; `timeline_panel.playhead_requested.emit(2.0)` → `timeline.current_time == 2.0`; `key_add_requested.emit(id, KIND_OBJECT, 1.0)` → `keyframes` gained a `TARGET_OBJECT`/`"position"` key at 1.0 for that id; `key_move_requested.emit(idx, 1.0, 2.0)` → that key's time is 2.0 (resolved here is just pass-through — indices come from the editor, fake one from `key_index_at`); `keys_remove_requested.emit([idx])` and `span_slide_requested.emit([idx], 0.5)` / `span_duplicate_requested.emit([idx], 1.0)` mutate `keyframes` accordingly; `snap_toggled.emit(false)` → `editor.get_snap() == false` (expose `get_snap()`).
  - Wiring: `lab.keyframes.history == lab.world.history`; `lab.keyframes.timeline == lab.timeline`; **undo/redo round-trip through the root buttons**: `top_bar` undo_requested → a `move_key` op reverses, `redo` re-applies, and the editor refreshed (spot-check: `keyframes.keyframes[i].time` restored).
  - Loader quiet (**Review-Focus #2 root half**): `_apply_project_data` with a 2-key synthetic `AnimationLabSaveData` → `world.history.can_undo()` is `false`, keyframes hold the 2 keys.
  - `evaluate_review()` still fills all 10 checklist items (`review_checklist.size() == 10`) after the edits above (scoring intact).
- [ ] **Step 2: Run to verify it fails** — `-Only test_timeline_editor_dock`; expected FAIL (handlers missing / `keyframes.history` not wired).
- [ ] **Step 3: Implement** the `_wire_panels` additions + handlers + injection in `animation_production_lab.gd` exactly per §6.
- [ ] **Step 4: Run to verify it passes** — `-Only test_timeline_editor_dock`; expected PASS.
- [ ] **Step 5: Run the whole gate** — expected `VERIFY OK` (**82 pass / 1 warn / 0 fail**).
- [ ] **Step 6: Commit** — the root script + 2 test files (+ `.gd.uid`), via `commit-task4.txt`; ledger line.

Skills: `event-bus`, `component-system`, `godot-testing`.

---

### Task 5: Wrap — full gate, code review, probe pass, fork record, push

**Files:**
- Modify: `docs/superpowers/specs/2026-10-08-multitrack-timeline-design.md` (add a fork/adjustment appendix: the deviations found during planning — index-based span ops, camera membership by target_type, `set_all` quiet loader, editor + toolbar inside the frame-list docker, panel signal forwarding; the five verified-code claims from the design review) — mirror round 1's "appendix §13" wrap
- Ledger: `.superpowers/sdd/2026-10-08-multitrack-timeline/progress.md` final lines (all task lines + probe verdicts + gate counts)

- [ ] **Step 1: Run the full gate** — expected `VERIFY OK`, **82 pass / 1 warn / 0 fail**; note it in the ledger (evidence before assertions).
- [ ] **Step 2: Run `godot-code-review`** over the branch diff (`bdd0687..HEAD`): no criticals; any nits go into the spec appendix (round-1 precedent: material-duplicate churn, strip pointer-capture).
- [ ] **Step 3: Final windowed probe pass** — exercise the editor in a real window from a guided FRAMES-stage save; confirm look/feel + that lanes appear at FRAMES onward and in Studio; screenshots + verdict in the ledger.
- [ ] **Step 4: Write the spec appendix + decision-record cross-note** (the decisions file gains a one-line "implemented" note; no decision changes).
- [ ] **Step 5: Commit docs** — spec + decisions files, via `commit-task5.txt`.
- [ ] **Step 6: Push** — `git push origin progress-two-emcsem` (finishing-a-development-branch governs; confirm remote branch + no stray files).

Skills: `godot-code-review`, `godot-agent-vision`, `verification-before-completion`.