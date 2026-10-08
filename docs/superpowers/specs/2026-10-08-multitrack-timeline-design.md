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
TimelinePanel (docker, existing root — frame-list controls stay)
  ├─ TimelineEditor (new Control; custom _draw ruler + lanes)
  │    └─ TimelineLaneModel (RefCounted, pure — derives lanes)
  ├─ editor toolbar (new: snap toggle, zoom in/out, delete selection)
  └─ frame-list controls (existing: Title/Hint/Scroll/ButtonRow)
        ^ signals up to root; root routes into TimelineController /
          KeyframeController / WorldController / LightingController
```

No new autoloads. `TimelineLaneModel` and the editor are `class_name`-less
(`extends RefCounted` / `extends Control`) — the root holds plain references,
matching the LayersPanel / DockResizeStrip convention.

## 3. TimelineLaneModel (pure view-model)

New script `scripts/animation_production_lab/ui/timeline_lane_model.gd`
(`extends RefCounted`). Consumes `WorldController`, `KeyframeController`,
`FrameController`, `LightingController` via plain properties set by the root
(test-injectable, like `PreviewController.timeline`). No signals, no nodes,
no state beyond the inputs' current state.

Lane-kind constants (single source of truth; the editor's signals and the
root's handlers match on these ints):
`const KIND_FRAMES := 0`, `KIND_OBJECT := 1`, `KIND_CAMERA := 2`,
`KIND_LIGHT := 3`.

- `func lanes() -> Array[Dictionary]` — ordered lanes:
  1. frame strip lane: `{"id": "frames", "kind": KIND_FRAMES,
     "label": "Frames", "keys": []}`.
  2. one lane per world layer in `world.layer_order()` order (index 0 =
     back of the stack):
     `{"id": <object_id>, "kind": KIND_OBJECT, "label": <display_name or
     id>, "keys": <Array[Dictionary]>, "locked": <registry locked>}`.
  3. Camera lane: `{"id": "camera", "kind": KIND_CAMERA,
     "label": "Camera", "keys": [...]}`.
  4. one lane per light (`LightingController` — add a read-only
     `light_ids() -> Array[String]`, in `lighting_controller.gd`, without
     changing playback; `_lights` is a Dictionary so `keys()` yields
     registration order): `{"id": <light_id>, "kind": KIND_LIGHT,
     "label": <light_id>, "keys": [...]}`.
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
  on the tempo grid at the current `fps` (entry `i` = `i / fps`) — this IS the
  frame grid: `timeline.frame_index_at()` maps clock time to frames the same
  way (`floori(fps * time)`), and snap targets this grid. Draw the strip lane
  markers from it. (Per-frame `AnimationFrameData.duration` is a hold
  property for the frame controls, not a boundary — do not read it here.)
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
- `func slide_keys(indices: Array[int], delta: float) -> bool` — add `delta`
  to each key at the given flat-list index (indices captured before the call;
  the elements stay the same through the re-sort), each clamped to
  `[0, duration]`, re-sorted. Keys may pack; no collision rejection this
  round. False when `indices` is empty or any index is invalid.
- `func duplicate_keys(indices: Array[int], offset: float) -> bool` — copy
  each key at the given index to `time + offset`, clamped to `[0, duration]`,
  same `target_id`/`property_path`, re-sorted. `offset == 0` duplicates in
  place (stacked). False when `indices` is empty or any index is invalid
  (overlap with existing keys is allowed; copies still land on the grid).

Span ops are resolved by the EDITOR, not the controller: the model's
`range_keys()` turns a lane selection into flat indices, and slide/duplicate
then work on those — so camera-lane keys (arbitrary authored ids, §3)
participate in span operations like any other lane's.

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

Signals (typed, up to the docker; `lane_kind` is a TimelineLaneModel KIND_*
int, §3; every `indices` payload is an Array[int] of flat indices into
`keyframes.keyframes`, resolved by the editor through the model at gesture
start):
- `lane_pressed(lane_id: String, lane_kind: int)`
- `playhead_requested(time: float)`
- `key_add_requested(lane_id: String, lane_kind: int, time: float)`
- `key_move_requested(index: int, from_time: float, to_time: float)`
- `keys_remove_requested(indices: Array[int])`
- `span_slide_requested(indices: Array[int], delta: float)`
- `span_duplicate_requested(indices: Array[int], offset: float)`
- `snap_toggled(on: bool)`

Public test hooks (structural tests call these directly, like
`DockResizeStrip._apply`): `refresh()`, `snap_time(t)`, `resolve_key(lane_id,
x)`, `_on_gesture_*` handlers for tap/drag/double-tap/scroll.

Gestures (touch + mouse; tap vs drag disambiguated by an 8px movement
threshold; `_gui_input` with `accept_event`):
- tap a key tick / lane row → `lane_pressed` (root selects the layer).
- tap the ruler → scrub: `playhead_requested(snap_time(pointer))`.
- double-tap empty lane area → `key_add_requested(lane_id, snap_time(x))`.
- drag a key tick horizontally → `key_move_requested(model.key_index_at(...),
  from, to)` (live while dragging; `to = snap_time(x)` when snap on, raw
  otherwise; index resolved once at drag start).
- drag empty lane area → range-select (marquee over the lane's span;
  selection drawn as a tinted band); the band becomes a selection whose keys
  come from `model.range_keys(lane, start, end)`.
- drag inside a non-empty selection → `span_slide_requested(indices,
  dx_seconds)` where `indices` are the selection's resolved flat indices
  (captured at drag start).
- copy/duplicate of a selection → `span_duplicate_requested(indices,
  offset)` with `offset = drop_seconds - selection_start` (0 = in place).
- a selection toolbar Delete button (and the Delete/Backspace key) →
  `keys_remove_requested(indices)` for the selected keys.
- mouse wheel over the ruler / pinch → zoom; toolbar in/out buttons → zoom.
  Zoom anchors: the time under the pointer (playhead time for the buttons)
  stays at the same x; `pps` ∈ [24, 240]; a draw offset keeps `t = 0` at or
  left of the canvas left edge (no negative-time region).
- snap toggle (checkbox in the toolbar) flips all enter-point snapping;
  snapping never applies to an in-progress pass when toggled mid-drag (the
  gesture captures snap state at drag start).

Selection state lives in the editor (not the model): one selection per lane =
`(start, end)` time span; cleared on `refresh()` when the lane set changes.

## 6. TimelinePanel + root wiring

`scenes/animation_production_lab/ui/timeline_panel.tscn`: add the editor
scene as a child above the frame-list controls, add the toolbar row (snap
toggle CheckButton, zoom in/out buttons, delete-selection button). Existing
signals (`frame_selected`, `frame_added`, ...) unchanged. The panel
**forwards** the editor's signals upward under the same names (lambdas in
`_ready`; the editor emits, the panel re-emits) and the root connects to the
panel — house convention (every other docker routes through panel signals;
the panel stays the docker boundary). New panel API
`bind(world, keyframes, frames, timeline, lighting)` forwards to the editor
(short-hand for the editor's own `set_sources(...)`).

`animation_production_lab.gd` handlers (one per editor signal, wired in
`_wire_panels` like the other docks):
- `_on_timeline_lane_pressed(id, kind)` → by lane kind: KIND_OBJECT →
  `world.select(id)`; KIND_LIGHT → `lighting.select(id)`; KIND_CAMERA and
  KIND_FRAMES → nothing (no selection target).
- `_on_timeline_playhead(t)` → `timeline.scrub(t - timeline.current_time)`.
- `_on_timeline_key_add(id, kind, t)` → `keyframes.add_keyframe(t, <target_id
  by kind>, <target_type by kind>, "position", <value>)` — target_id: the
  object/light id as given, fixed `"camera"` for the camera lane;
  target_type: TARGET_OBJECT / TARGET_CAMERA / TARGET_LIGHT by kind; value:
  the track's evaluated value when it exists
  (`keyframes.evaluate(target_id, "position", t)`), else the live value —
  `world.get_object(id).position` for objects, `camera.camera().position`
  for the camera, the matching light node's position for lights.
- `_on_timeline_key_move(index, _from, to)` → `keyframes.move_key(index, to)`.
- `_on_timeline_keys_remove(indices)` → `keyframes.remove_keys(indices)`.
- `_on_timeline_span_slide(indices, delta)` → `keyframes.slide_keys(indices, delta)`.
- `_on_timeline_span_duplicate(indices, offset)` →
  `keyframes.duplicate_keys(indices, offset)`.
- `_on_timeline_snap_toggled(on)` → `timeline_panel.editor.set_snap(on)`
  (the root also keeps the value for future per-project persistence;
  nothing else consumes it this round).

Editor refresh triggers (subscriptions added in `_wire_panels` beside the
existing ones): `keyframes.keyframes_changed`, `frames.frames_changed`,
`lights.lights_changed`, `world.objects_changed`, `world.layer_order_changed`
→ `timeline_panel.editor.refresh()` (rebuild lanes + redraw; rebuilding on
any of these is cheap at lab scale — no visibility guard). `history_changed`
stays button-only (existing `_on_history_changed`): keyframe undo/redo
re-emits `keyframes_changed` from the closures (§4), so the editor refreshes
on undo/redo through the normal signal path — no root special-casing. Lane
order changes ride `layer_order_changed` (reorder ops already emit it via
`_commit_order`). In `_ready`, wire `keyframes.history = world.history` and
`keyframes.timeline = timeline`, and call `timeline_panel.bind(...)` to wire
the editor's sources.

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
  retained in the flat list; camera lane collects TARGET_CAMERA keys with
  arbitrary authored ids; snap_time nearest-frame + clamp; frame_boundaries
  on the fps tempo grid; range_keys / key_index_at bounds.
- `tests/test_timeline_editor_ops.gd` — move_key clamps + keeps sort + emits;
  remove_keys by index set; slide_keys clamps and packs; duplicate_keys is
  in-lane + clamps; every op pushes history (only when `history` wired) and
  undo/redo round-trips the time/array state; ops on a duration-bounded
  timeline never exceed `[0, duration]`; `set_all` (loader path) pushes no
  history, so undo after a load leaves keyframes untouched.
- `tests/test_timeline_editor_gestures.gd` + `.tscn` — scene harness mounting
  the TimelinePanel docker alone (bare controllers bound via
  `timeline_panel.bind`): synthesized `_gui_input` events (tap lane, tap
  ruler, double-tap add, key drag, marquee, selection drag, Delete key, wheel,
  pinch) produce the §5 signals with resolved indices / snapped times; tap-vs-
  drag 8px threshold; snap frozen at gesture start; zoom pps clamps to
  [24, 240] and the t=0 offset never goes positive; delete with no selection
  emits nothing; many layers clip inside the editor rect.
- `tests/test_timeline_editor_dock.gd` + `.tscn` — full lab: editor + toolbar
  present inside TimelinePanel; editor signals → panel → root handlers route
  to the real controllers (lane tap selects the layer, playhead scrubs, key
  add/move/remove mutate `keyframes`, span slide/duplicate mutate
  `keyframes`, snap toggle set on the editor); `keyframes.history` wired
  (`== world.history`) so undo/redo round-trips a key move through the root
  buttons; after `_apply_project_data` with a synthetic save,
  `world.history.can_undo()` is false (loader quiet via `set_all`).
- Guided gating asserted by the existing stage tests (no new gating logic).
- Full gate expectation: previous 78 pass + 4 new = **82 pass / 1 known-WARN
  / 0 fail**; `test_full_lab_sweep` stays the sole known-WARN.
- Look/feel proof: throwaway windowed probe (not committed) — lane/rule
  rendering, zoom, snap, drag feel; recorded in the round ledger.

## 10. Implementation phases (plan outline for writing-plans)

1. KeyframeController primitives + history wiring + `set_all` (test-first).
2. TimelineLaneModel + `LightingController.light_ids()` (test-first).
3. TimelineEditor canvas + gestures + selection; TimelinePanel scene (editor
   instance + toolbar + forwarded signals) (synthesized-event test; windowed
   feel probe).
4. Root wiring: handlers, refresh subscriptions, `keyframes.history` /
   `timeline` injection, loader swap to `set_all`, guided gating pass.
5. Full gate, godot-code-review, windowed look probe, fork record + ledger.

---

## 11. Fork record — adjustments made and verification (Task 5 wrap)

### Deviations from the pre-planning spec, settled during planning

1. **Index-based span ops.** `KeyframeController.slide_keys` / `duplicate_keys`
   take flat-list indices, not `(target_id, range)`: camera-lane keys carry
   arbitrary authored ids ("cam", …) that cannot be matched by `target_id` on
   the controller. The editor resolves marquee ranges to flat indices through
   the lane model (`range_keys` / `key_index_at`); the controller never sees
   ids.
2. **Camera lane membership by `target_type` only.** Authored camera ids
   vary, so the camera lane groups `TARGET_CAMERA` keys by type and ignores
   `target_id` — verified against playback, which ignores it too.
3. **Quiet `set_all` loader (Task 1).** The load path rebuilds keyframes with
   a single quiet `set_all` (no `keyframes_changed` during load), so no
   commit in the round ever leaves the loader poisoning the freshly-cleared
   undo stack.
4. **Editor + toolbar inside the frame-list docker.** The multi-track canvas
   and its toolbar live in `TimelinePanel` (the existing FRAMES/KEYFRAME/
   TIMING docker), above the frame-list controls — no new top-level panel.
5. **Panel signal forwarding.** The panel is the docker boundary: it forwards
   the editor's eight signals upward under the same names; the root wires only
   to the panel.

### Verified-code claims from the design review (checked before planning)

- `TimelinePanel` is the frame-list docker; fps/duration live on
  `AnimationControls`, not the panel (spec corrected during planning).
- Playback ignores authored camera key target ids (camera-lane membership by
  type verified in code).
- `KeyframeController` ops push `EditorHistory` only when `history` is
  injected (null-safe): bare-controller callers and existing tests keep
  working unchanged.
- Times clamp to `[0, timeline.duration]` only when `timeline` is injected;
  otherwise they floor at 0.
- `evaluate()` is RF4-safe: an unknown target or missing track returns `null`
  instead of erroring.

### godot-code-review checklist results (Task 5 Step 2)

No Criticals. Checklist nits — all already triaged as ship in the ledger:

- `_draw` allocates per lane per pass (`_selection.get(str(id), {})`,
  repeated `str()`) — deferred minor T3-b, sub-editor-scale.
- `_live_position` reads `lighting._lights` directly — deferred minor T4-a;
  fix is a public `get_light_node(id)` accessor.
- The editor subscribes to `keyframes_changed` and the root does too
  (idempotent double refresh).
- Delete/Backspace/Ctrl+D are hardcoded keys, not Input Map actions — matches
  the widget-owned canvas convention (marquee/scrub/pinch are widget events);
  map to actions if a rebind UI ever lands.

### Final windowed probe (Task 5 Step 3) — verdict

Throwaway probe (deleted, never committed): the real lab scene at the guided
FRAMES stage from a save-shaped load (`collect_save_data` →
`_apply_project_data` → `go_to(FRAMES)`), 2 objects + 3 frames + camera +
light keys; gestures driven through the real wiring (marquee, Ctrl-drag
duplicate, double-tap add, key drag); Studio mode re-checked. Verified by
programmatic pixel sampling of the editor rect (no eyeballs on the host):

- 6 lanes render at FRAMES: frames strip + 2 object lanes (regenerated ids)
  + camera + 2 starter lights.
- All six key-tick colors render on the right lanes; ruler labels, per-frame
  ticks and the playhead line draw.
- Edits through the real signal path changed `keyframes` 8 → 11 (marquee
  duplicate +2 camera keys, double-tap add +1, drag moved a visible key
  0.2 → 1.2) and the pixels moved accordingly (camera tick count doubled).
- Studio: the same editor and lanes with the same 11 keys (the project shelf
  is a full-rect modal by design; hidden for the canvas shot).

**Discovered, pre-existing, out-of-scope defect (not introduced by this
round):** `_apply_project_data` regenerates world object ids but copies
keyframe `target_id`s verbatim, so object keyframes orphan after a Studio
Load — object lanes render empty and playback stops applying object animation
until keys are re-added. Camera/light keys survive (their ids are stable).
Pre-dates this round (`test_animation_save_roundtrip` Part 4 asserts
field-wise multiset equality with throwaway ids and never tests remapping)
and touches no task's file list; recorded here and in the ledger. Recommend a
follow-up: remap `TARGET_OBJECT` keyframe ids through the loader's `id_map`.