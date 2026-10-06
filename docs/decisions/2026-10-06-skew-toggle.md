# Skew switch in the inspector — decisions

Settled 2026-10-06. Origin: "rather than needing to rotate the object to remove
the skew, we have a switch to enable and disable it inside the inspector".
Revised 2026-10-06 (5s) after the user clarified the switch semantics: always
visible, default **off**, and while it is off the object is *flattened in real
time* rather than sheared-and-auto-enabled.

Context that shapes this record: shear is *emergent*, not a parameter — there is
no stored skew angle. It is created by pre-multiplying a rotated basis (the
World scale row, the Global gizmo — see `2026-10-05-gizmo-orientation.md`),
detected by `_is_sheared`, and removed by rebuilding the basis as `R * S` (the
5q flatten). An "enable skew" switch therefore cannot *set* a skew amount; it is
a **mode**: the object's skew is either intentional (preserve it) or not (clean
it).

## Decisions

| Decision | Choice | Why | Revisit when |
|---|---|---|---|
| Control shape | CheckBox "Skew" in the inspector, **always visible** for a selected object; pressed iff the per-object flag is on | The ask is an explicit enable/disable; a one-way button has no "on" state. A switch that is hidden until shear exists cannot be *armed in advance*, and the keep-clean contract makes arming a precondition | a real skew parameter (angle) is ever added |
| Default state | Skew **off** — and OFF is **keep-clean**: while it is off, **no operation leaves a sheared object** | Keeps the shipped clean-object behaviour (5q) as the base; "so that there is no skew when …" is the literal ask | — |
| Shear while the switch is off | **Flattened in real time.** The World scale row and the Global gizmo scale rebuild their result as `R * S` with the same column lengths the moment it would otherwise shear | The user's clarification — "flattened in real time unless I toggle skew on". A fresh object can never become sheared without turning the switch on first | — |
| Creating shear while the switch is off | **Not possible** — no auto-flip. The 5r auto-enable (the switch mirrored shear creation) is removed | Keep-clean is unconditional: if the switch is off there is nothing to flip, because no shear exists to mirror. Shear is produced only while the switch is ON — and the first step is turning it on | — |
| Rotation edit while skew **on** | **Preserve** the skew (the 5p rotation delta) | The point of "enabled": work with a skewed object without it popping on a rotation edit | — |
| Rotation edit while skew **off** | **Flatten** (the 5q `R * S` rebuild) | The restored 5q contract stays for non-skew objects — and under keep-clean, off+sheared can only be a legacy save | — |
| The one sheared-OFF state | Legacy loads only. Its next edit (rotation, or any scale) flattens it with the 5q one-time growth | The flag predates the feature; a save made before it exists loads off. Keep-clean then treats its first edit like any other off-edit: clean | if stale saves ever need migrating |
| Toggling **off** while sheared | Flattens immediately, same `R * S` math as 5q (size grows once to the column-length product, disclosed) | "Remove skew without rotating" is the literal ask; reuses the locked 5q mechanism rather than inventing a second flatten | — |
| Persistence | Per-object `skew_enabled` flag in `PrimitiveSaveData`, mirrored in node meta and carried through modeling-action snapshots | A deliberately skewed object survives save/load with its intent; legacy saves load off (no version bump — same story as `has_basis`) | — |
| Undo of toggle-off | Shape restores fully (it is a transform action); the flag restores with it — undo lands on **sheared+ON** | Transform actions own shape; the flag is written after the commit so the action's snapshots keep the pre-toggle value, and `_apply_transform` re-applies it | if stale flags ever mislead |
| Warning label | Stays **shear-gated** — hidden on a clean object, shown only when there is shear to disclose | A clean object has nothing to warn about; the switch carries the state, the warning carries the disclosure | — |

## Consequence, stated because it is easy to miss

Under 5s keep-clean, **nothing a user does while the switch is OFF can create
shear** — the two shear-producing edits (World scale row, Global gizmo) flatten
their result the instant it would otherwise shear, and the 5r auto-enable is
gone. A sheared object therefore only exists **while the switch is ON**, and the
sequence is always arm-first: *toggle Skew on, then stretch*, not the reverse.
The 5q "rotating flattens" behaviour survives unchanged for the one sheared-OFF
state that remains — legacy saves, whose flag defaults off — and its first edit
carries the same disclosed one-time growth.

The other consequence worth naming: on a **rotated** object, the World Scale row
no longer reads back the exact number typed while the switch is off — after the
real-time flatten the World row honestly reports the cleaned frame's row
lengths, not the typed world-axis length. Keep-clean and exact world-axis
readback are mutually exclusive on rotated bases; the readback guarantee now
lives in the ON state, where shear survives and the row is exactly invertible.

## Open / deferred

- Nothing new. The move-gain decision (audit item 11) remains open.