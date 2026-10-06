# Gizmo orientation: Global vs Local — decisions

Settled 2026-10-05. Origin: a play report that stretching an object "in a certain
angle" stretched along the wrong direction, plus a request for a second,
object-relative gizmo the way Blender has one.

## Decisions

| Decision | Choice | Why | Revisit when |
|---|---|---|---|
| Default orientation | **Local** (object-relative) — **changed 2026-10-06, was Global** | Scale must not shear: the object stays a clean box and only its dimensions change. Global skews a rotated object into a parallelogram, and that skew is not wanted. See the reversal note below | A third mode appears that scales to the world-axis size *without* shearing |
| Global scale of a rotated object | **Keep true shear** (`basis = S*R`), written **directly** to `.basis` — implementation unchanged, now behind the toggle | Geometrically correct and matches Blender, so the mode stays available and honest. What changed is that it is no longer the default | — |
| Inspector readout under shear | Show the **effective axis lengths**, not `node.scale` | `node.scale` cannot express a sheared basis, so it reports a decomposition. Showing it teaches a wrong number | — |
| Multi-select "Local" reference | **First-selected object's** rotation | Blender uses the active object. Averaging rotations across a selection yields an axis matching no object, which feels broken | Selection gains an explicit "active" concept distinct from order |
| Which tools the toggle affects | **All three** — move, rotate, scale | A toggle that works on two of three tools is more confusing than none: set Local, drag move, silently get world behaviour | — |
| Fallback if shear misbehaves | Ship **Local as default**, keep Global behind the toggle | One flag, one branch. The risky path stays reachable but stops being load-bearing, so nothing needs reverting | — |

## The default reversal, 2026-10-06

The fallback row was taken up, not merely kept in reserve. Global is still
implemented and still reachable in one click; it is no longer what ships as the
default.

**Why.** Global is mathematically exact and Blender's own default, and that is
not in dispute — measured, dragging the world-X handle by 1.5 on a cube yawed 45°
takes the world-X extent from 1.414 to exactly 2.121. The problem is the price of
that exactness: the same drag turns the front face into a parallelogram tilted
11.3°, and a sheared box is not a modelling-tool behaviour anyone asked for. A
third report, after the maths had been verified against Blender, asked for scale
that changes the object's **dimensions without skewing it**. Local is that.

**What the reversal costs, stated plainly.** Local is not "Global without the
shear". On the same cube and the same 1.5 drag, world-X extent goes 1.414 ->
**1.768**, and world-Z extent goes 1.414 -> **1.768** as well — because the
stretch lands on the object's own axis, which runs diagonally through world space.
So under Local **no world axis is scaled by the factor you typed**.

| | world-X extent | world-Z extent | front face | sheared |
|---|---|---|---|---|
| before | 1.414 | 1.414 | 1x1, square | no |
| Global (toggle off) | **2.121** | 1.414 | 1.275x1, tilted 11.3 deg | **yes** |
| **Local (toggle on, default)** | 1.768 | 1.768 | 1x1, square | **no** |

There is a third possibility that is neither: keep the box rectangular *and* have
the world-X span grow by exactly the factor — world-X 1.414 -> 2.121 with no
skew. It does not exist, it is not one line, and it was not requested, so it is
not built. If the 1.768 above is the wrong number, that mode is what is being
asked for.

**The symmetry of the argument.** The original case for Global was "the drawing
lies; make the drawing honest". A Local default inverts that lie — the handle you
grab is not the one that moves — but it is a far smaller lie than silently
skewing the geometry underneath the user. That trade is what settled it.
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
- **A third scale mode: rectangular and sized to the world axis.** The one thing
  neither Global nor Local does. Not built — not asked for — but it is the only
  remaining candidate if Local's world-axis numbers feel wrong.
- **Hardware verification of scale feel** — *assumed* the maths suffices. Direction
  and rate of a scale drag cannot be judged headlessly; a human must drag it.

## What is NOT settled by this record

Whether Global-with-shear is *pleasant*. The maths is measured; the feel is not,
and no headless test can decide it. If shear proves to make the inspector or
save/load behave badly, the fallback row above is the intended exit and it is
deliberately cheap.

**That exit was taken on 2026-10-06** — Local now ships as the default. See the
reversal note above for what that costs and what it does not answer.

Scale feel is still unmeasured in *either* mode. No headless test can say whether
a 1.5x drag reads as "half again as big" to a human hand. The toolbar toggle
exists precisely so both modes can be compared on one object in two clicks.