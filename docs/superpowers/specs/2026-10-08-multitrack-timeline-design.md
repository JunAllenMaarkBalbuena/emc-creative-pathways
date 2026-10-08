# Design — Multi-track timeline editor (Animation Production Lab)

2026-10-08. Next round on top of the Animation Studio round (2026-10-07). All
design decisions settled in `docs/decisions/2026-10-08-multitrack-timeline.md`
(grill + brainstorming); this spec is the implementation contract.

## 1. Purpose and scope

Turn the Timeline docker into a real timeline editor: per-target keyframe
lanes under a time ruler, direct manipulation (add / move / delete keys, slide
and duplicate selection-span clips), horizontal zoom, and snap-to-frame. The
player choreographs per-layer, camera, and light animation in one view that
mirrors the Layers docker.

**In scope:** lane model + custom-drawn editor canvas + gestures (touch and
mouse); editing primitives on `KeyframeController` with undo/redo; docker
toolbar (snap toggle, zoom, delete selection); guided+studio same-editor
gating; structural + headless tests; throwaway windowed look probe.

**Out of scope (decision record, Open / deferred):** cross-lane clipboard
paste (copy = in-lane duplicate only); typed `AnimationLayerData`/track
Resources; layout presets / collapsed lane groups; 2D vs 3D editing-mode UIs;
editor-view vs camera-view split.

**Untouched by design (contract, do not modify):** `TimelineController`,
`FrameController`, `PreviewController` (evaluate + 10-item review checklist),
`AnimationFrameData`/`AnimationKeyframeData`, `AnimationLabSaveData` shape,
scoring, and the save migration surface. The flat `keyframes` array remains
the source of truth; old saves load unchanged (back-compat, no version bump).

## 2. Architecture

One new widget (the editor canvas) inside the existing `TimelinePanel` docker,
a pure view-model that derives lanes, and editing primitives on
`KeyframeController`. Interaction is one-way: gesture -> editor signal ->
root handler -> controller op (history push, `*_changed` emit) -> editor
refresh.

```
TimelinePanel (docker, existing root)
  ├─ TimelineEditor (new Control; custom _draw ruler + lanes)
  │    └─ TimelineLaneModel (RefCounted, pure — derives lanes)
  ├─ toolbar (new: snap toggle, zoom in/out, delete selection)
  └─ fps/duration controls (existing)
        ^ signals up to root; root routes into TimelineController /
          KeyframeController / WorldController
```

No new autoloads. `TimelineLaneModel` and the editor are `class_name`-less
(`extends RefCounted` / `extends Control`) — the root holds plain references,
matching the LayersPanel / DockResizeStrip convention.

## 3. TimelineLaneModel (pure view-model)

New script `scripts/animation_production_lab/ui/timeline_lane_model.gd`
(`extends RefCounted`). Consumes `WorldController`, `KeyframeController`,
`FrameController` via plain properties set by the root (test-injectable, like
`PreviewController.timeline`). No signals, no nodes, no state beyond the
inputs' current state.

- `func lanes() -> Array[Dictionary]` — ordered lanes:
  1. frame strip lane: `{"id": "frames", "kind": "frames", "label": "Frames",
     "keys": []}` (frame boundary markers read separately, see below).
  2. one lane per world layer in `world.layer_order()` order (index 0 =
     back of the stack):
     `{"id": <object_id>, "kind": "object", "label": <display_name or id>,
     "keys": <Array[Dictionary]>, "locked": <registry locked>}`.
  3. Camera lane: `{"id": "camera", "kind": "camera", "label": "Camera",
     "keys": [...]}`.
  4. one lane per light (`LightingController` must expose the ordered light
     ids — add a read-only `light_ids() -> Array[String]`, in
     `lighting_controller.gd`, without changing playback; `_lights` is a
     Dictionary so `keys()` yields registration order).
  Lane membership is by target type: object/light lanes collect keys with
  matching `target_type` **and** `target_id`; the camera lane collects
  `TARGET_CAMERA` keys regardless of the authored `target_id` (playback
  ignores it — `preview_controller._apply_camera` reads only
  `property_path`, and saves/tests author ids like `"cam"`).
  Lane `keys` entries: `{"target_id": <id>, "property_path": <path>,
  "time": <float>, "interpolation": <0|1>}` — one entry per key in the flat
  list for that lane, sorted by time. Keys whose target no longer exists
  (orphans) are **not** listed but remain in the flat list (RF4 playback
  skips them).
- `func snap_time(time: float) -> float` — nearest frame boundary
  (`roundf(time * fps) / fps`), clamped to `[0, duration]`; `fps`/`duration`
  read from `TimelineController` (injectable property).
- `func frame_boundaries() -> Array[float]` — the frame channel's start times
  on the tempo grid at the current `fps` (one entry per frame: `i / fps`),
  used to draw the strip lane markers. If the frame channel ever supports
  per-frame durations, this is the single place to change.
- `func range_keys(lane_id: String, start: float, end: float) -> Array[int]`
  — indices into `keyframes.keyframes` for keys of that lane with
  `start <= time <= end`.
- `func key_index_at(lane_id: String, time: float, tolerance: float) -> int`
  — index of the key on that lane within `tolerance` of `time`, else -1
  (used to resolve a grabbed key tick to a flat-list index).

## 4. Editing primitives on KeyframeController

New methods on `scripts/animation_production_lab/keyframe_controller.gd`. All
mutate the flat list, keep it sorted, emit `keyframes_changed`, clamp to
`[0, timeline.duration]` via a new injectable `timeline` property (pattern:
`PreviewController.timeline`; null-safe — no upper clamp when unset, time
still floored at 0), and push `EditorHistory` exactly like `WorldController`
ops — so editing ops routed through the existing Inspector UI become undoable
too, matching the "editor actions are undoable" record.

History wiring: the controller gains `var history: EditorHistory` (the root
wires `world.history`); every op pushes only when `history != null`, so tests
that construct the controller bare (all existing keyframe tests) keep working
unchanged. Per op the undo closure restores the whole prior `keyframes`
array (`prev` a `duplicate()` copy) **and emits `keyframes_changed`**; redo
re-applies the new array and emits. This mirrors the verified world
convention — the world's closures call quiet helpers that restore and emit
`objects_changed`/`layer_order_changed`, so panels refresh purely off signals
and no root special-casing is needed for undo/redo. Closures capture only
`duplicate()` arrays plus the long-lived controller (`self`), never scene
nodes.

- `func move_key(index: int, time: float) -> bool` — clamp, set
  `keyframes[index].time`, sort, emit. False when `index` invalid.
- `func remove_keys(indices: Array[int]) -> bool` — remove by flat-list
  index (descending sort internally so indices stay valid). False when empty.
- `func slide_span(lane_id: String, start: float, end: float, delta: float) -> bool` —
  for every key of `lane_id` in `[start, end]`, add `delta` to its time
  (clamped to `[0, duration]`, re-sorted after). Keys may pack; no collision
  rejection this round. False when no keys move.
- `func duplicate_span(lane_id: String, start: float, end: float, drop_time: float) -> bool` —
  copy each key in `[start, end]` to `time + (drop_time - start)`, clamped to
  `[0, duration]`, re-sorted, same `target_id`/`property_path`. `drop_time ==
  start` duplicates in place (stacked). False only when the span has no keys
  (overlap with existing keys is allowed; copies still land on the grid).

Existing `add_keyframe` / `remove_keyframe` / `evaluate` / `keyframes_for`
keep their signatures; `add_keyframe` and `remove_keyframe` gain the same
null-safe history push (both are editor-facing ops). New quiet bulk helper
`func set_all(keys: Array[AnimationKeyframeData]) -> void` — assign + sort +
single `keyframes_changed` emit, **no history** — used by the loader: today
`_apply_project_data` calls `add_keyframe` per entry *after*
`world.history.clear()` (line 798), so pushing from the load path would leave
fresh keyframe entries in the cleared history and undo-after-load would
un-add loaded keys. `set_all` keeps the load path quiet and
`clear()` correct.

## 5. TimelineEditor (canvas widget)

New scene `scenes/animation_production_lab/ui/timeline_editor.tscn` + script
`scripts/animation_production_lab/ui/timeline_editor.gd` (`extends Control`,
no children — everything is one `_draw` pass).

Layout (1280-wide docker reference, all values device-independent px):
- Ruler: 32px tall at the top — frame tick grid (minor tick per frame,
  label every 5th frame with the `s` time), playhead (vertical line + handle
  triangle), current-time label in the docker header.
- Lanes below: 24px per lane, full width, key ticks 3px tall. Lane row
  header is a left gutter (96px) with the lane label — the editor draws it;
  the Layers docker remains the stack editor, this gutter is read-only.
- Key tick colors by property (legend in the toolbar):
  `position` = `#4caf50`, `rotation` = `#2196f3`, `scale` = `#ffc107`,
  `visible` = `#9c27b0`, camera/light keys use their lane's single color
  (`#00bcd4` camera, `#ff7043` light). A lane's keys draw in stack order
  (later lanes on top within the same column).
- Zoom: pixels-per-second `pps` in `[24, 240]`, default `96`; each wheel
  notch / pinch step multiplies by `1.5`; the playhead x stays anchored while
  zooming; the frame tick grid re-derives from `pps` (labels decimate so they
  never overlap).
- The frame strip lane draws frame boundary markers from
  `model.frame_boundaries()` and a subtle filmstrip background strip.

Pure-draw rules: `_draw` re-issues only on refresh requests; nothing runs per
engine frame except moving the playhead (see §7). No per-frame allocation.

Signals (typed, up to the docker):
- `lane_pressed(lane_id: String)`
- `playhead_requested(time: float)`
- `key_add_requested(lane_id: String, time: float)`
- `key_move_requested(lane_id: String, from_time: float, to_time: float)`
- `keys_remove_requested(lane_ids: Array[String], times: Array[float])`
- `span_slide_requested(lane_id: String, start: float, end: float, delta: float)`
- `span_duplicate_requested(lane_id: String, start: float, end: float, drop_time: float)`
- `snap_toggled(on: bool)`

Public test hooks (structural tests call these directly, like
`DockResizeStrip._apply`): `refresh()`, `snap_time(t)`, `resolve_key(lane_id,
x)`, `_on_gesture_*` handlers for tap/drag/double-tap/scroll.

Gestures (touch + mouse; tap vs drag disambiguated by an 8px movement
threshold; `_gui_input` with `accept_event`):
- tap a key tick / lane row → `lane_pressed` (root selects the layer).
- tap the ruler → scrub: `playhead_requested(snap_time(pointer))`.
- double-tap empty lane area → `key_add_requested(lane_id, snap_time(x))`.
- drag a key tick horizontally → `key_move_requested(lane_id, from, to)`
  (live while dragging; `to = snap_time(x)` when snap on, raw otherwise).
- drag empty lane area → range-select (marquee over the lane's span;
  selection drawn as a tinted band); keys in the band become selected.
- drag inside a non-empty selection → `span_slide_requested(lane_id,
  selection_start, selection_end, dx_seconds)`.
- a selection toolbar Delete button (and the Delete/Backspace key) →
  `keys_remove_requested(selected_lane_ids, selected_times)`.
- mouse wheel over the ruler / pinch → zoom; toolbar in/out buttons → zoom.
- snap toggle (checkbox in the toolbar) flips all enter-point snapping;
  snapping never applies to an in-progress pass when toggled mid-drag.

Selection state lives in the editor (not the model): one selection per lane =
`(start, end)` time span; cleared on `refresh()` when the lane set changes.

## 6. TimelinePanel + root wiring

`scenes/animation_production_lab/ui/timeline_panel.tscn`: add the editor
scene as a child above the fps/duration controls, add the toolbar row (snap
toggle CheckButton, zoom in/out buttons, delete-selection button). Existing
signals (`fps_changed`, `duration_changed`, ...) unchanged. The panel
**forwards** the editor's signals upward under the same names and the root
connects to the panel — house convention (every other docker routes through
panel signals; the panel stays the docker boundary). The editor itself holds
no knowledge of the root.

`animation_production_lab.gd` handlers (one per editor signal):
- `_on_timeline_lane_pressed(id)` → object lane: `world.select(id)`; light
  lane: `lighting.select(id)`; camera/frames lanes: no selection target
  (tap selects nothing there); empty id deselects.
- `_on_timeline_playhead(t)` → `timeline.scrub(t - timeline.current_time)`.
- `_on_timeline_key_add(id, t)` → `keyframes.add_keyframe(t, id, <target_type
  of the lane>, "position", <value>)` where target_type is TARGET_OBJECT /
  TARGET_CAMERA / TARGET_LIGHT by lane kind (camera keys use the fixed
  target_id "camera" — display and membership are by target_type, §3), and
  value = `keyframes.evaluate(id, "position", t)` when the track exists,
  else the live value (`world.get_object(id).position`).
- `_on_timeline_key_move(id, from, to)` → `keyframes.move_key(
  keyframes.key_index_at(id, from, 0.05), to)`.
- `_on_timeline_keys_remove(ids, times)` → batch `remove_keys` by resolving
  indices.
- `_on_timeline_span_slide(...)/_span_duplicate(...)` → the corresponding
  primitive.
- `_on_timeline_snap_toggled(on)` → `editor.set_snap(on)`.

Editor refresh triggers (subscriptions added in `_wire_panels` beside the
existing ones): `keyframes.keyframes_changed`, `frames.frames_changed`,
`lights.lights_changed`, `world.objects_changed`, `world.layer_order_changed`
→ `timeline_editor.refresh()` (rebuild lanes + redraw). `history_changed`
stays button-only (existing `_on_history_changed`): keyframe undo/redo
re-emits `keyframes_changed` from the closures (§4), so the editor refreshes
on undo/redo through the normal signal path — no root special-casing. Lane
order changes ride `layer_order_changed` (reorder ops already emit it via
`_commit_order`).

Guided gating: unchanged stage map — the panel (now containing the editor) is
shown at the FRAMES stage onward and hidden before it; studio always. No new
gating logic.

## 7. Playback and redraw

`timeline.time_changed` moves only the playhead: the editor redraws the
playhead line (and optional auto-scroll keeps it visible), never rebuilds
lanes. Lane geometry rebuild happens on the refresh triggers in §6. The
docker's existing transport (AnimationControls) is untouched.

## 8. Invariants / error handling

- All time values clamp to `[0, duration]`; duration floor `0.01` keeps the
  grid non-degenerate (existing `set_duration`).
- Snap rounds to the nearest frame boundary; keys always land on the grid
  while snap is on.
- Orphan keys (target removed by load/wipe) render no lane, stay in the flat
  list, and playback skips them (RF4 — existing `evaluate` null path).
- Selection is invalidated when the lane set changes (refresh).
- Undo/redo restores the whole keyframes array; the world-rebuild guard from
  the studio round stands (`history.clear()` after `_apply_project_data`).
- Touch: tap-vs-drag threshold 8px; two-finger drag reserved for future pan
  (not this round); pinch zoom has no conflict with lane drags.
- Zoom clamps to `[24, 240]` pps so a lane never degenerates and the
  playhead never scrolls out of the ruler.

## 9. Testing strategy

Headless/structural, per house style (SceneTree harnesses + `.tscn` wrapper
where the gate requires it; gate: `tools/verify-project.ps1`):

- `tests/test_timeline_lane_model.gd` — lanes() mirrors
  `world.layer_order()` (reorder rides through), frame/camera/light lanes
  present and ordered, keys sorted per lane, orphans excluded from lanes but
  retained in the flat list; snap_time nearest-frame + clamp; range_keys /
  key_index_at bounds.
- `tests/test_timeline_editor_ops.gd` — move_key clamps + keeps sort + emits;
  remove_keys by index set; slide_span clamps and packs; duplicate_span is
  in-lane + clamps; every op pushes history and undo/redo round-trips the
  time/array state; ops on a duration-bounded timeline never exceed
  `[0, duration]`; `set_all` (loader path) pushes no history, so undo after a
  load leaves keyframes untouched.
- `tests/test_timeline_editor_dock.gd` + `.tscn` — editor + toolbar present
  inside TimelinePanel; signals wired to root handlers; gesture hooks route
  to the expected controller mutations (structural, like
  `test_animation_dock_layout`).
- Guided gating asserted by the existing stage tests (no new gating logic).
- Full gate expectation: previous 78 pass + 3 new = **81 pass / 1 known-WARN
  / 0 fail**; `test_full_lab_sweep` stays the sole known-WARN.
- Look/feel proof: throwaway windowed probe (not committed) — lane/rule
  rendering, zoom, snap, drag feel; recorded in the round ledger.

## 10. Implementation phases (plan outline for writing-plans)

1. KeyframeController primitives + history wiring + `set_all` + loader swap
   (`_apply_project_data` -> `set_all`; test-first) — model-neutral.
2. TimelineLaneModel (test-first).
3. TimelineEditor canvas: ruler/lanes draw, zoom, playhead (probe).
4. Gestures + selection + toolbar; docker scene wiring + root handlers.
5. Guided gating pass, full gate, review, commit sequence.