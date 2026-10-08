# Multi-track timeline rework — decisions

Settled 2026-10-08. Origin: the Animation Studio round (2026-10-07) deferred the
multi-track timeline rework as "the next round on top of this"; this record
settles the rework's decisions before any design or code. Carries forward
without re-asking (recorded in `2026-10-07-animation-studio-round.md` and the
lab spec D-table): undo/redo applies to editor actions; saves stay
back-compatible with no version bump; touch-first with buttons/keyboard where
touch is weak; one layer per placed object; the guided flow is the same editor
as the Creative Studio.

| Decision | Choice | Why | Revisit when |
|---|---|---|---|
| Editing depth | **Direct manipulation** — the player adds/moves/deletes keyframes and slides clip spans in the timeline UI | The rework's point is a real timeline editor, not a read-only lane view; "per-object tracks, clips, zoom, snap" all imply manipulation | — |
| Track model | **Derived tracks over the flat keyframe list** — `KeyframeController.keyframes` stays the source of truth; lanes are a 1:1 view grouped by `target_id`; clips are selection spans | Save format and review/scoring stay untouched (back-compat for free); lane identity is already `object_id` | timeline tracks need per-track state (mute/color/visibility), then the typed-`AnimationLayerData` migration |
| Clip semantics | **Selection-span clips** — a clip is a range selected on a lane; the keys inside slide/copy as one unit; no clip objects, no new save state | Consistent with derived tracks; "delay the walk cycle by half a second" = select span, drag right | video-editor-style named clip blocks are wanted |
| Lane set | **All animated targets** — frame-channel strip + one lane per world layer (mirroring the Layers docker stack order) + Camera lane + one lane per light | The engine already keys all four target kinds; the ruler must reflect everything playback uses | — |
| Guided vs studio | **Same editor** — the timeline docker with lanes appears in guided from the FRAMES stage onward, tutorialized | The round's guiding principle: guided teaches the editor the studio uses | — |
| Tempo grid & snapping | **Snap to the frame grid (1/fps), default on, toggleable** in the docker | The frame channel is the tempo; a grid keeps clip slides aligned, and the toggle covers free-placement choreography | — |
| Copy reach | **In-lane duplicate only** — a copied selection duplicates within its own lane at the drop point; cross-lane clipboard paste deferred | Covers the common "extend the walk cycle" case without a paste-target model | a cross-lane clipboard is wanted |
| Zoom controls | **Mouse wheel over the ruler + touch pinch + in/out buttons**; pixels-per-second scale; playhead stays anchored; frame grid re-draws; clamped so lanes never get unusably dense | Touch-first rule; no hidden capabilities on mobile/web | — |
| Lane tap | **Tap a lane selects that layer in the world** (Layers docker + Inspector follow); tap the ruler scrubs the playhead | Matches how the dockers already behave; selection and cursor are different targets, no mode confusion | — |
| Timeline edits & undo | Timeline editing ops (add/move/delete key, slide/duplicate span) push `EditorHistory` exactly like transform edits | Recorded studio-round decision: undo/redo in scope for editor actions | — |
| Rendering | Ruler + lanes drawn by a custom `_draw` canvas (no per-frame allocation, no container-per-key); keys drawn as per-property ticks with a legend | Godot fact, not a question: lane counts are small but per-key containers would churn on every drag | lane counts grow into the thousands |
| Lane order | Lane list mirrors `world.layer_order()` and reorders with it | The timeline is the Layers docker's time dimension | — |
| Orphan keys | Keys whose target is gone stay in the flat list and are skipped by playback (existing RF4) but show no lane | Preserves current load/wipe behavior; no data-migration churn | an orphan cleanup pass is wanted |

## Open / deferred

- Cross-lane clipboard paste (copy = in-lane duplicate this round).
- Typed `AnimationLayerData`/track Resources — deferred with the derived-track
  model; revisit when tracks need per-track state.
- Timeline layout presets / collapsed lane groups.
- 2D vs 3D editing-mode UIs; editor-view vs camera-view split (separate round,
  already queueed).

## Task 5 wrap note (2026-10-09)

- **Copy reach is now two-trigger.** The "Copy reach" decision (in-lane
  duplicate) ships as Ctrl+drag *and* a toolbar Duplicate button (offset = the
  selection-span length; one-frame fallback) — the button is the touch-reachable
  path, per the touch-first rule that buttons exist where touch is weak. Final
  review finding #2 drove the button.
- **Snap covers span slide/duplicate.** "Tempo grid & snapping" now also
  applies while a selection span is dragged/duplicated: the selection's left
  edge lands on the frame grid whenever snap is on (snap state captured at
  drag activation), snap-off carries the raw pointer delta. Final review
  finding #1.
- **Pre-existing loader defect surfaced by the wrap probe** (out of scope):
  `_apply_project_data` regenerates object ids without remapping object
  keyframes, orphaning them after a Studio Load. See spec appendix §11.