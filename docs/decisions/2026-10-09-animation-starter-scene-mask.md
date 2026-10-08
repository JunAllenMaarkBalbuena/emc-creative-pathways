# Starter-scene mask + rename prefill — decisions

Settled 2026-10-09. Origin: the three-item bug report on the Animation
Production Lab — (1) rename "does not give the user the ability to customize
the name", (2) the Continue button in the layering part does not advance to the
next stage, (3) QoL: the order in the scene objects should mirror the Layers
docker order in real time.

## Root cause (headless probe, real lab scene — `tools/probes/starter_probe`,
## throwaway, not committed)

The three symptoms share **one** defect. The lab scene ships three authored
"starter" nodes — `StarterBackdrop` (0, 1, −6), `StarterCharacter` (0, 0.5, 0),
`StarterWorkstation` (1.2, 0.45, 0) — **visible in the 2.5D viewport from
boot** at exactly the library spawn points, but (per the B2 ruling, approved
2026-10-07) **not registered** in the composition stack. The Layers docker,
rename, reorder and the STAGING gate all operate on the registry only, so at a
bare-boot guided run:

| Symptom report | Probe evidence | Explanation |
|---|---|---|
| Rename can't customize | `layer rows = 0`, `RenameButton.disabled = true` at STAGING while the scene shows 3 objects | The visible scene has no layer rows; nothing can be selected or renamed. Player copies also spawn exactly on the starters (same texture, same position) so the scene never visibly changes |
| Continue doesn't advance | `staging_state() = {character_before_background: false, near_prop: false}` at boot; Continue stays on STAGING with status "Character placed first, prop nearby" | The ASSETS gate only requires an assignment, so STAGING can be reached with the registry empty; the gate measures registered objects, so a scene that already *looks* staged counts for nothing |
| Scene order ≠ layers order | The 3 visible objects have no rows (they're not registered); reorders are visually invisible under identical overlapping starters | The docker cannot reflect or drive the visible starters at all |

The gate logic itself is sound — registering character + background + prop at
their default spawns flips the state to `{true, true}` and Continue advances to
CAMERA (probe). The blocker is **registration vs visibility**: the visible
scene and the data the tools measure diverge.

## Decisions

| Decision | Choice | Why | Revisit when |
|---|---|---|---|
| Guided working-stage scenery | **Hide the authored starters during guided ASSETS..SUBMIT** — `_set_starter_world_visible(false)`; keep them visible at BRIEF/PLAN (the "here's the lab" intro) and in Studio mode (the furnished default world) | The guided scene then *equals* the registered composition exactly: adding assets visibly changes the world, rename/reorder act on what is rendered, and Challenge E stays meaningful. Nodes stay in the tree (tests resolve them by presence, so blast radius is minimal). This is the user's option-A choice from the design review | a guided-flow redesign wants ambient scenery back |
| Starter registration at boot | **Rejected — do not register the starters as layers** | Registering would make the Layers docker non-empty at boot and "fix" reports 1 and 3 directly, but the staging gate would auto-pass at boot — Challenge E, the ASSETS tutorial steps and the whole staging stage become pointless — and it would overturn the approved B2 ruling ("starters never appear in world.layer_order()", asserted by `test_animation_starter_order.gd`) | B2 itself is revisited |
| B2 priority pinning | **Kept unchanged** — starters still render at `STARTER_PRIORITY` (≤ 0), below every player layer (`layer_priority(0) = 16`) | The mask fixes the player-facing mismatch without touching the ordering mechanism that a windowed probe already locked | — |
| Rename UX | **Pre-fill the rename field with the selected layer's current display name on selection** (`layers_panel._prefill_rename_field`), so "customize" means editing the existing name instead of retyping into an empty box | Directly answers report 1's wording; the field is only touched on selection change (never on rebuilds), so a user mid-typing keeps their text while rows re-render | an inline row-rename affordance is wanted |
| Blocked-Continue feedback | No change — the status line "Character placed first, prop nearby" stays, but with the starter world masked the empty scene makes the unmet requirement self-evident | The label was accurate; the confusion was the already-staged but invisible-to-the-gate scenery | richer per-requirement hints are wanted |

## Consequence, stated because it is easy to miss

Guided mode now renders *only* the player's composition from ASSETS onward.
BRIEF/PLAN still show the furnished lab behind the modal panels; Studio mode
shows it too (the default world a project boots into). The layers docker,
rename, reorder and the STAGING gate speak the same set of objects the player
sees — the coherence contract encoded by
`tests/test_animation_starter_scene_mask.gd` (starters hidden ASSETS..SUBMIT,
visible at BRIEF/PLAN and in Studio). `RenderOrder`/B2 mechanics are untouched.

## Open / deferred

- Guides (visual row ghosts, tooltips) teaching the player *to* add objects at
  ASSETS now that the starter world no longer masks the empty scene.
- Studio-mode starter rows: the starters remain unregistered scenery in Studio
  too (B2), so the Studio layers docker lists player layers only — acceptable,
  out of scope here.