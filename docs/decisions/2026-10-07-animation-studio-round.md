# Animation Studio round — decisions

Settled 2026-10-07. Origin: the revised Animation Production Lab design (revised
2.5D composition / docker UI / timeline brief, 2026-10-07), following the
round-1 grill on the new-system frontier.

Context that shapes this record: the lab (shipped, gate green 72/1/0) already
runs the guided pipeline — assignment → storyboard → assets → staging → camera →
lighting → frames → keyframes → timing → preview → submit → score → studio
unlock — in one scene (`animation_production_lab.tscn`), a 2.5D world of
`Sprite3D` characters/backdrop + primitive `MeshInstance3D` props under a
`SubViewport`, driven by controllers under `Systems/` (`WorldHub`,
`CameraHub`, `LightingHub`, `FrameHub`, `KeyframeHub`, `TimelineHub`,
`AssignmentHub`, `PreviewHub`). Ordering today is coarse: objects live in
category roots (`character_root` / `background_root` / `prop_root`), `depth` is
a z-offset (spatial depth, the only thing that moves render order), and `layer`
is an intra-root sibling index that does not affect 3D draw order. There is no
unified interleaved composition stack, no layers docker, no undo/redo in the
lab, and the "Creative Studio" is project-file CRUD only. The player-relevant
revision: the studio is the main deliverable; the guided flow teaches the same
editor.

## Decisions

| Decision | Choice | Why | Revisit when |
|---|---|---|---|
| Goal | **Creative Studio is the main deliverable** — an open-ended 2.5D animation editor; the guided assignment flow becomes the tutorial layer over the *same* editor | User: "the main goal now is to create the Creative Studio while the other parts/levels will serve as the tutorial in how to use the animation lab features" | a separate studio scene is ever wanted |
| This round's scope | **Docked studio editor core**: unified composition + Layers docker + docked layout (resizable, toggleable) + 2D/3D element placement & transform + undo/redo + studio project save/load. Timeline/preview stay as-is this round | Q5 approved; the multi-track timeline rework and 2D/3D editing-mode UIs are the next round on top of this | timeline rework round starts |
| Placement | **Refactor in place** — the composition layer system lives inside the existing lab scene and scripts; no parallel scene | Preserves the green guided pipeline (assignment/scoring/save/studio untouched in shape); spec §35: isolate ordering behind the composition/rendering system | a from-scratch editor replaces the lab |
| 2.5D element typing | Layer `element_type` ∈ {2D artwork, 3D model}; a **2.5D character/object is a 3D-layer element** whose renderable is a `Sprite3D` (an added feature of 3D layer elements) | User (Q2): "having the 2.5d character or object is fine as an added feature for the 3d layer element"; the lab already places everything in 3D space (spec §35 `Sprite3D` approach) | — |
| Layer granularity | **One layer per placed object instance** | Chosen ("choose what is best"): matches the spec's `AnimationLayerData {asset_id, order_index}` and its asset-instance concept; one-to-one select/rename/vis/lock; simplest for guided + studio | layers-as-groups/folders ever needed |
| Docker depth | **Fixed docked layout, resizable panes, show/hide toggles**; full drag-and-drop panel docking deferred | Q6 approved; a custom docking system is heavy and risky on GL Compatibility + mobile/web; spec §15 warns "do not make the interface overly complicated" | drag-docking is wanted |
| Docker interactions | Buttons/keyboard-first for reorder (up/down, to-front/to-back, forward/backward) and vis/lock/rename/select/add/delete/duplicate; **drag-to-reorder deferred** | Q4 approved — the game targets mobile and web; buttons + keyboard are touch/controller-safe | drag-to-reorder is wanted |
| Undo/redo | **In scope** for editor actions (layer ops + transforms); implemented as a small two-stack editor history **pattern-reusing** the app's existing undo patterns (`digital_art_lab/HistoryManager` swap-old/new; modeling-lab action snapshots) | An open-ended studio without undo/redo feels broken; spec §37; reuse = pattern-level only, no cross-lab script dependency (independence contract) | — |
| Tool reuse | Reuse the illustration/3D-modeling labs' tools as **pattern-level, modular components inside the animation lab** (gizmos, camera orbit, transform, color/material handling) — never importing another lab's scenes/scripts | User: "reuse the tools features we have from the illustration lab and 3d modeling lab"; the standing independence contract forbids depending on other labs' scenes/scripts — each lab boots standalone | a shared `editor_tools/` module is spun up for two+ consumers |
| Perf/modularity | Small single-purpose controllers, no per-frame allocation, GL Compatibility budgets (≤1 dir light + ≤1 omni in play; few transparent layers), mobile/web as first-class targets | User: "keep our game modular in order for the game to run efficiently and optimized" | — |
| Composition ordering mechanism | **B2 — transparent-pass render priority**: every layer renders through the transparent pass with `render_priority = STARTER_PRIORITY + (layer_index + 1) × 16`; sprites carry it on the instance, meshes on a duplicated transparent material; `node.position` stays pure | Locked by the Task 1 windowed probe (evidence recorded in the spec §13.1 appendix + round ledger): with equal z the higher-priority sprite draws on top and the pixel signature flips when the priorities swap; the composition depth-plane candidate was rejected — z already carries the player's spatial depth. STARTER_PRIORITY pins starter nodes below every player layer | transparent-pass overdraw cost is measured at scale (every layer is transparent) or a non-Compatibility renderer is adopted |

## Consequence, stated because it is easy to miss

The guided flow and the studio are now **one editor**. Guided stages keep their
panels and scoring (the stages are the tutorialization of the studio's
features), while the docked layout — Layers, Inspector, Asset Library, Timeline
— is the shared shell. Layer order becomes a **first-class, player-facing
property** decoupled from where the object sits in 3D space, which is the
spec's defining 2.5D feature; it must be testable by stacking assertions (the
same windowed pixel-probe harness used for the stage-visibility fix), not just
by data checks.

## Open / deferred

- Drag-to-reorder in dockers; drag-and-drop panel docking; layout presets.
- Multi-track timeline rework (per-object tracks, clips, zoom, snap); 2D vs 3D
  editing-mode UIs; editor-view vs camera-view split.
- `AnimationLayerData` as a typed `Resource` (spec §33) — deferred until
  timeline tracks need typed layers; the registry-Dictionary API is shaped to
  migrate.