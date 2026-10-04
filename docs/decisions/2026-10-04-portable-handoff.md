# Portable handoff — decisions

Settled 2026-10-04. Goal: transferring this project to another developer reproduces the current
state, and the game is not damaged in the process.

## Decisions

| Decision | Choice | Why | Revisit when |
|---|---|---|---|
| Scope of the heal | Commit all real work (133 scripts, 50 tests, 18 scenes, 63 addons, assets, data) | "As is the current state" is unreachable while two thirds of the project is untracked | — |
| Transfer mechanism | Git clone as source of truth, **plus** a generated zip for convenience | A zip cannot prove it matches the last commit; the zip is built *from* the committed tree so it can | A third channel is added |
| Scratch files | Gitignore, do not commit | They are one-off migration/scratch artifacts, not project source | One becomes part of the workflow |
| Engine pin | Document `4.7.2.stable` as the exact version | `config/features` says `4.7`; only an exact build reproduces behaviour | The engine is upgraded |
| Editor reproducibility | Build a verification script (`tools/verify-project.ps1`) | Boot + full test sweep is the only portable proof that a transferred tree is sound | CI replaces it |
| Cross-device input | **Deferred.** Record as a design constraint only | Retrofitting input across 133 uncommitted scripts risks breaking working behaviour for no handoff benefit | Mobile or gamepad support is actually commissioned |
| Export presets | **Deferred.** No `export_presets.cfg` created | Export templates are not installed here and are version-locked; authoring presets blind is the single most likely way to produce something subtly wrong | Someone installs 4.7.2 export templates and asks for a build |

## Evidence these were based on

- Engine present but off PATH: `Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe`
  (`.console.exe` is the one that emits headless output).
- Project boots headless clean: exit 0, zero errors.
- Test suite: 20 runnable `SceneTree` tests, 19–20 clean. `test_full_lab_sweep.gd` is
  **flaky** — it failed once and passed on re-run. Treated as a comparison gate, not an
  absolute pass/fail assertion.
- `.uid` state: 291 distinct uids referenced by scenes; only 6 backed by a tracked `.uid`
  file. No reference is uid-only (all carry a `path=` fallback), so nothing hard-breaks, but
  each developer would otherwise generate different uids and every merge would churn.
- `.godot/` is 526 MB / 16,276 files of machine-specific cache. Must never be transferred.
- Absolute paths in tracked files: 6, all inside the third-party `addons/godot_ai/` addon
  (fallback strings and probes, not locks). No project source hardcodes a machine path.

## Four traps worth remembering

**1. `vendor/` must carry a `.gdignore`, and it is the single most dangerous thing in this
repo.** The vendored skills live *inside* the Godot project. Without `.gdignore`, Godot
compiles their 1,683 example `.gd` files as project code, and two of them collide with real
game classes:

| Vendored example | Shadows |
|---|---|
| `godot-genre-survival/scripts/interactable.gd` | `class_name Interactable` |
| `godot-genre-visual-novel/scripts/dialogue_ui.gd` | `class_name DialogueUI` |

A colliding `class_name` makes the game's own script fail with
`Class "Interactable" hides a global script class`. The base class then will not load, so
`player.gd` sees `interact()` as returning void, and every interactable subclass fails too.
**Seven broken game scripts, caused by an unrelated directory.** `tools/setup-godot-skills.ps1`
recreates the marker on every run, because `vendor/` is a build artifact and gets wiped.

**2. `$ErrorActionPreference = 'SilentlyContinue'` hides Godot failures.** Godot reports parse
errors on **stderr**. Set that preference and PowerShell swallows them, so a broken tree looks
perfectly clean. `tools/verify-project.ps1` uses `Continue` for exactly this reason. If you
check Godot by hand from PowerShell, capture stderr to a file instead:

    Start-Process godot_console.exe -ArgumentList '--headless','--path',$P,'--check-only','--script','res://scripts/x.gd' -Wait -RedirectStandardError err.txt

**3. `--check-only --script` cannot resolve autoloads.** `LevelProgression`, `SettingsManager`
and `SceneTransition` only exist when the project actually runs, so per-file checking reports
spurious `Identifier not found` for any script that touches them. That is a limit of the check,
not a defect in the script.

**4. A fresh clone has no `.godot/`, so it has no class cache, and `--quit` will not build
one.** `.godot/global_script_class_cache.cfg` is what lets GDScript resolve `class_name`
types. It is gitignored, correctly, because it is machine state. Without it every
`class_name` fails to resolve and the suite reports a wall of invented failures:

```
Could not find type "LevelDefinition" in the current scope
Identifier "PrimitiveSpawner" not declared in the current scope
Failed to instantiate an autoload, script 'res://scripts/level_progression.gd' does not inherit from 'Node'
```

None of that indicates broken code. Only `godot --headless --import` builds the cache;
`--headless --quit` boots without scanning for scripts and leaves the file absent.

This was live for one commit: the first version of `verify-project.ps1` warmed with
`--quit`, which passed on the author's machine (where `.godot/` already existed) and
failed **19 of 20 tests** on a clean clone. Author-machine testing cannot see this class
of bug, because the machine already has the cache. Always validate a handoff from a
fresh clone, never from the working tree.

First import of a fresh clone takes ~5 minutes (288 s here) because it imports 5,054
assets. `verify-project.ps1` does it automatically and hard-fails if the cache does not
appear, rather than reporting the cascade as test failures.

**Also note:** exit code 0 does not mean the tests passed. The suite signals through printed
`PASS:`/`FAIL:` markers and several tests exit 0 while printing errors. Never gate CI on the
exit code alone.

## Open / deferred

- Export presets and per-platform builds — deferred, see table.
- Cross-device input (touch, gamepad) — deferred, recorded as a constraint.
- Importing the remaining `.uid` files is done; if a future Godot release changes uid
  handling, re-check.
- The pre-existing tracked-vs-untracked `.uid` split (10 of 24 under `scripts/`) is now
  resolved in favour of tracking all of them.