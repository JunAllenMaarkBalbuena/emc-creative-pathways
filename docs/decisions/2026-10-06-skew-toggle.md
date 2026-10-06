# Skew switch in the inspector — decisions

Settled 2026-10-06. Origin: "rather than needing to rotate the object to remove
the skew, we have a switch to enable and disable it inside the inspector".

Context that shapes this record: shear is *emergent*, not a parameter — there is
no stored skew angle. It is created by pre-multiplying a rotated basis (the
World scale row, the Global gizmo — see `2026-10-05-gizmo-orientation.md`),
detected by `_is_sheared`, and today removed only as a side effect of editing a
rotation field (5q's `R * S` rebuild, which also grows the object once). An
"enable skew" switch therefore cannot *set* a skew amount; it is a **mode**: the
object's skew is either intentional (preserve it) or not (clean it).

## Decisions

| Decision | Choice | Why | Revisit when |
|---|---|---|---|
| Control shape | CheckBox "Skew" in the inspector, visible only while the selected object is sheared (shares the `ShearWarning` row) | The ask is an explicit enable/disable; a one-way button has no "on" state. Shown only when there is something to toggle, like the warning | a real skew parameter (angle) is ever added |
| Default state | Skew **off** | Keeps the shipped clean-object behaviour (5q) as the base; skew-intent is explicit opt-in | — |
| Rotation edit while skew **on** | **Preserve** the skew (the 5p rotation delta, restored) | The point of "enabled": work with a skewed object without it popping on a rotation edit | — |
| Rotation edit while skew **off** | **Flatten** (the 5q `R * S` rebuild) | The restored 5q contract stays for non-skew objects | — |
| Creating shear while skew is off | Allowed; the switch **auto-flips on** | World scale keeps its settled semantics (5m: Global keeps true shear); the switch mirrors reality instead of gating it | a "keep clean" hard mode is wanted |
| Toggling **off** while sheared | Flattens immediately, same `R * S` math as 5q (size grows once to the column-length product, disclosed) | "Remove skew without rotating" is the literal ask; reuses the locked 5q mechanism rather than inventing a second flatten | — |
| Persistence | Per-object `skew_enabled` flag in `PrimitiveSaveData`, mirrored in node meta and carried through modeling-action snapshots | A deliberately skewed object survives save/load with its intent; legacy saves load off (no version bump — same story as `has_basis`) | — |
| Undo of toggle-off | Shape restores fully (it is a transform action); the flag is best-effort — a stale flag is benign by design | Transform actions own shape; flag/shape disagreement is harmless (sheared+off shows the warning; clean+on behaves identically) | if stale flags ever mislead |

## Consequence, stated because it is easy to miss

Because shear creation auto-flips the switch **on**, a freshly sheared object now
**keeps** its skew through rotation edits. The 5q "rotating flattens" behaviour
applies only to sheared objects whose switch is **off** — the legacy/loaded-off
case, and objects whose user has explicitly un-toggled. This is the direct
result of choosing "the switch flips ON to reflect reality" for creation; 5q's
test setup is updated to a switch-off (legacy) object.

## Open / deferred

- Nothing new. The move-gain decision (audit item 11) remains open.