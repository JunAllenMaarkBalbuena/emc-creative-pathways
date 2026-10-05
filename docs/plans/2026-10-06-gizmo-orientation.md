# Gizmo orientation: Global / Local — implementation plan

Design settled 2026-10-06. Decisions: `docs/decisions/2026-10-05-gizmo-orientation.md`.
Approach **A** — rotate the gizmo, convert the axis to world at press time.

## Why approach A

The bug is a **mismatch**, not a missing mode. Move and rotate already act in
world space; scale alone acts in local space (`node.scale *= component`) while
every handle is drawn world-aligned. Approach B fixes the behaviour while leaving
the user-facing lie in place. Approach C duplicates ~200 lines of handle building
for one `Basis` multiply.

## Facts about the code

- `selection_manager.gd:100` — `select_multi` sets `_selected = fresh[0]`, so the
  "first-selected object's rotation" reference needs **no new state**. Verified.
- `modeling_lab.gd:517` — `_compute_drag_screen_basis` derives its screen axis
  from `gizmo.global_position + _drag_axis`. An earlier draft of this plan
  claimed that stays correct unchanged under Local. **That was wrong.** The Area
  meta stores the LOCAL axis (read straight out of `AXES`), so adding it to a
  world position projects the wrong tip. This function **does** need the world
  axis — via the new `Gizmo3D.axis_to_world()`.

## Correction: the predicted `_process` clobber does not exist

The draft predicted that the constant-on-screen sizing, which writes the handle
frame every frame, would decompose the basis and snap the handles back to world
axes. Tested by reverting the implementation to a plain `.scale` assignment: the
rotation survived, delta 0.0000. `Basis.set_scale` preserves the rotation part.
The prediction was written down before it was measured.

`Gizmo3D._apply_orientation()` is kept anyway — one write path instead of two —
but it is **not** load-bearing, and the test that covers it is labelled a smoke
check rather than a regression test, because it cannot tell the two
implementations apart.

## Two axes, not one

The subtle part of the whole feature, and it applies twice:

| Consumer | Which axis | Why |
|---|---|---|
| `apply_scale` component pick | **local** | picks *which* of X/Y/Z was grabbed |
| `apply_scale` frame | orientation basis | decides world vs local |
| `_compute_drag_screen_basis` | **world** | projects a real world direction |
| move / rotate | **world** | already world-space |

Passing a world axis to `apply_scale` would be a real bug, not a cosmetic one:
a local X handle on a 45°-yawed object has a world direction with *both* x and z
components non-zero, so the `axis.x != 0` / `axis.z != 0` component test would
scale two axes at once.

## Data flow

```
LocalToggle / KEY_X  ->  _orientation: int  (GLOBAL | LOCAL)
                          |-> gizmo.set_orientation(_orientation_basis())   # rotates handles
                          v
   press: _drag_axis (local) -> gizmo_basis * _drag_axis  (world)
                          v
   apply_move / apply_rotate / apply_scale(world_axis, ...)
```

| Concern | Owner | Change |
|---|---|---|
| Orientation enum + flag | `modeling_lab.gd` | new, single source of truth |
| Handle rotation | `Gizmo3D.set_orientation()` | new method, sets `_handle_root.basis` |
| Local-axis -> world conversion | `modeling_lab.gd` press handler | one line beside the existing pick read |
| Local reference rotation | `selection_manager.get_selected()` | none needed |
| Effective scale readout | `modeling_lab.gd::_update_inspector` | show axis lengths, not `node.scale` |

No new signals, no new nodes, no new scene file.

## Fallback

One flag, one branch. If shear misbehaves in play, flip the default to LOCAL and
keep Global behind the toggle. The risky path stays reachable but stops being
load-bearing, so nothing needs reverting.

## Tasks

- [ ] **Task 1 — regression test first.** `tests/test_gizmo_orientation.tscn`.
      Assert (a) Global scale of a 45°-yawed node produces a basis equal to
      `S*R` within 1e-4 — the shear case; (b) Local scale produces `R*S`; (c) the
      sheared basis survives an undo round trip; (d) Global is the default.
      Skills: `godot-testing`, `gdscript-patterns`.
      **Verify it fails before Task 2-4 touch production code.**

- [ ] **Task 2 — `Gizmo3D.set_orientation(basis)`.** Set `_handle_root.basis`;
      guard the `scale` write in `_process` so the constant-on-screen sizing
      cannot clobber orientation. Skills: `scene-organization`, `3d-essentials`.

- [ ] **Task 3 — orientation flag + world-axis conversion.**
      `enum Orientation { GLOBAL, LOCAL }`, default GLOBAL. At press, convert
      `_drag_axis` through the gizmo basis. `KEY_X` toggles (verified free — the
      only `KEY_G` is the digital-art fill tool, and no InputMap action claims
      `X`). Skills: `input-handling`, `gdscript-patterns`, `player-controller`.

- [ ] **Task 4 — Global scale writes `basis` directly.**
      Must never route through `.scale` (measured: destroys shear, delta 0.707).
      **This is the same bug class as 5h** — do not reintroduce it.
      Skills: `gdscript-patterns`, `godot-testing`.

- [ ] **Task 5 — Local rotation reference.** Use the first-selected node's
      orthonormalised rotation. Skills: `scene-organization`.

- [ ] **Task 6 — UI.** `LocalToggle` `CheckButton` in `LeftToolbar` beside
      `GridToggle`/`SnapToggle`, reusing that pattern. Skills: `godot-ui`,
      `responsive-ui`.

- [ ] **Task 7 — inspector effective-length readout.** Skills: `godot-ui`.

- [ ] **Task 8 — gate.** `tools/verify-project.ps1`. Baseline is **37 pass, 1 warn
      (known-flaky `test_full_lab_sweep.gd`), 0 fail of 38**.

- [ ] **Task 9 — audit doc.** New section in `docs/audit-2026-10-05.md`.

## Skills before implementing

Per `AGENTS.md`, each task lists the domain skills to invoke **before** writing
its Godot code.

## Not decided by this plan

- **Scale feel.** The maths is measurable; direction and rate need a human
  dragging it. No headless test can settle this.
- **Shear interaction with save/load.** `save_manager` stores
  `rotation_degrees` + `scale`, which cannot express a sheared basis. A sheared
  object will round-trip through save as its decomposition. Flagged, not solved.