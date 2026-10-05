# Gizmo orientation: Global vs Local — decisions

Settled 2026-10-05. Origin: a play report that stretching an object "in a certain
angle" stretched along the wrong direction, plus a request for a second,
object-relative gizmo the way Blender has one.

## Decisions

| Decision | Choice | Why | Revisit when |
|---|---|---|---|
| Default orientation | **Global** (world) | The handles are *already* drawn world-aligned and move/rotate already act in world space. Making Global the default makes the drawing honest; Local as the default would be the surprising one, since it would mean the drawing lies in the other direction | Users ask for Blender-identical defaults |
| Global scale of a rotated object | **Keep true shear** (`basis = S*R`), written **directly** to `.basis` | Geometrically correct, matches Blender, matches the behaviour the report asked for. Clamping to an un-sheared basis invents a third behaviour nobody requested | The inspector's `(1.58, 1, 1.58)` readout proves harmful in play |
| Inspector readout under shear | Show the **effective axis lengths**, not `node.scale` | `node.scale` cannot express a sheared basis, so it reports a decomposition. Showing it teaches a wrong number | — |
| Multi-select "Local" reference | **First-selected object's** rotation | Blender uses the active object. Averaging rotations across a selection yields an axis matching no object, which feels broken | Selection gains an explicit "active" concept distinct from order |
| Which tools the toggle affects | **All three** — move, rotate, scale | A toggle that works on two of three tools is more confusing than none: set Local, drag move, silently get world behaviour | — |
| Fallback if shear misbehaves | Ship **Local as default**, keep Global behind the toggle | One flag, one branch. The risky path stays reachable but stops being load-bearing, so nothing needs reverting | — |

## The finding that reframed the request

This was **not** "add a second mode". It is a **mismatch between the drawing and
the effect**, which scale alone has:

| Operation | Code | Frame it acts in |
|---|---|---|
| move | `position += world_axis * d` | world |
| rotate | `Basis(world_axis, a) * original_basis` | world |
| **scale** | `node.scale *= component` | **local** (`basis = R*S`) |
| gizmo handles | drawn from `AXES = [RIGHT, UP, BACK]`, `_handle_root` never rotated | world |

So the red X handle *looks* world-aligned and *moves* world-aligned, but the
stretch it produces runs along the object's **own** local X. Rotate the cube 45°
and the handle and the effect point in different directions. That is the
"certain angle" in the report. Move and rotate are already correct and must not
change.

## The constraint that decides the implementation

A world-axis scale of a rotated object requires **shear**: `basis = S*R` is not a
valid TRS decomposition once the object is rotated. Measured on a node yawed 45°,
then stretched 2× on world X:

| Operation | Result |
|---|---|
| write the sheared basis directly to `.basis`, read back | **identical**, shear preserved |
| route the same value through `.scale` / `.rotation_degrees` | **basis delta 0.707**, shear destroyed; node then reads `(1,1,1)` |
| whole-`transform` round trip | **shear preserved** |
| `orthonormalized()` | discards scale *and* shear |

Consequence: **Global scale must write `.basis` directly and must never pass
through `.scale`.** The 5h fix already routes every commit through a stored
basis, so the commit path is already compatible — which is why this is a
contained change rather than a new risk.

## Evidence

- Frame asymmetry: measured directly on `Node3D`, `tests/` probe (deleted after).
- Shear preservation: measured directly, the four rows above.
- The `get_euler()` bug in 5h is the same family — a matrix decomposition losing
  information. Do not reintroduce it here by routing Global scale through `.scale`.

## Open / deferred

- **True `atan2` angular ring tracking** (carried from 5g) — still deferred.
- **Gamepad binding for `switch_character`** and the other carry-overs in
  `docs/audit-2026-10-05.md` are untouched by this record.
- **The toggle's UI placement and keyboard shortcut** — assumed a button in the
  existing gizmo toolbar plus `X`-style double-press if an input action already
  exists; *assumed*, not confirmed. Revisit if the toolbar has no room.
- **Hardware verification of scale feel** — *assumed* the maths suffices. Direction
  and rate of a scale drag cannot be judged headlessly; a human must drag it.

## What is NOT settled by this record

Whether Global-with-shear is *pleasant*. The maths is measured; the feel is not,
and no headless test can decide it. If shear proves to make the inspector or
save/load behave badly, the fallback row above is the intended exit and it is
deliberately cheap.