# Save/Load Scene — Group-Aware (Blender-file style)

**Date:** 2026-09-24

## Goal
Make Save/Load capture the whole scene — objects **and groups** — as one named
asset, with the format future-proofed for nested groups (group-in-group) and no
regressions to existing features.

## Context: current behavior
- Save/Load works via **Ctrl+S / Ctrl+O** → `%SaveDialog` / `%LoadDialog` →
  `SaveManager` + `PortfolioManager3D`. **No toolbar buttons.**
- **Bug:** `SaveManager.capture_model()` (save_manager.gd:73) only iterates
  direct `MeshInstance3D` children of `object_container`. Groups (`Node3D`) and
  their entire contents are **silently dropped** on save.
- `restore_model()` (save_manager.gd:94) spawns everything flat; ignores
  `parent_name`; only clears direct meshes (group nodes would linger).
- `PrimitiveSaveData` has unused `parent_name`; engine names sanitize "." so
  display-name fidelity (`blender_display` meta) must be preserved explicitly.

## Data model — flat + parent pointers (nested-ready)

### 1. `scripts/modeling_lab/primitive_save_data.gd`
Add:
```gdscript
@export var node_type: int = 0     # 0 = MESH, 1 = GROUP
@export var display_name: String = ""   # Blender-style ("cube.001")
```
Existing fields unchanged. `node_type` default 0 = old `.tres` files load as
flat meshes (backward compatible).

### 2. `scripts/modeling_lab/save_manager.gd`
**`capture_model`** — rewrite as DFS from `object_container` (pre-order, so
parents always precede children):
- `MeshInstance3D` not in `ghost_guides` → MESH entry (type via
  `PrimitiveSpawner.type_for_mesh`, local transform, material
  albedo/metallic/roughness, `display_name = HierarchyManager.display_of`).
- `Node3D` with mesh descendant → GROUP entry (local transform, `display_name`),
  set children's `parent_name` to the group's **display** name, recurse.

**`restore_model`** — rewrite:
- Build `display_name → Node3D` map in array order.
- GROUP → new `Node3D`, `HierarchyManager.set_blender_name(node, display_name)`,
  apply local transform, parent = `name_map.get(parent_name, container)`.
- MESH → `spawner.spawn(type, mapped_parent)`, `set_blender_name`, local
  transform, material override.
- Helper `_all_meshes(root)` → recursively collects created meshes for return
  value + `fit_all`.
- Keeps clearing container first (all non-ghost, incl. groups).

## UI

### 3. `scenes/modeling_lab/modeling_lab.tscn`
Add to `TopBar` (near `HintBtn`): `SaveBtn` + `LoadBtn` (Buttons,
`visible = false`, `text = "Save"` / `"Load"`).

### 4. `scripts/modeling_lab/modeling_lab.gd`
- Wire `%SaveBtn.pressed → _on_save`, `%LoadBtn.pressed → _on_load` in `_ready`.
- `_enter_creative_studio` (line ~400): `%SaveBtn.visible = true`,
  `%LoadBtn.visible = true`.
- `_clear_objects` (line ~254): free **all** non-ghost children (Node3D groups
  + members), not just top-level meshes. Ghosts already live in
  `GhostContainer` (line 103) — verified safe.
- `_on_model_opened` (line ~1227): `fit_all(selection_manager.collect_selectable_meshes())`
  so grouped members frame correctly.

## Tests

### 5. `tests/test_full_lab_sweep.gd` — add `_test_save_scene_preserves_groups`
- Container: 1 flat mesh + 1 group (2 meshes) + 1 nested group.
- `capture_model` → GROUP entries exist, `parent_name` chains correct,
  parents-before-children order, materials/transforms recorded.
- `restore_model` → hierarchy recreated (flat mesh top-level; group Node3D with
  2 children; nested depth preserved), display names, transforms, materials
  round-trip.
- `_clear_objects` → everything gone.

Existing `tests/test_modeling_save.gd` remains valid (top-level meshes).

## Verification
1. Sweep: `--script res://tests/test_full_lab_sweep.gd` (baseline 43 passing →
   expect 44).
2. Legacy: `--script res://tests/test_undo_redo_commands.gd`.
3. Compile check: `--quit-after 4 --editor`.

## Explicitly out of scope
- Nested-group **creation** UI (grouping a group). Format + restore already
  support arbitrary depth.

## Files touched
`primitive_save_data.gd`, `save_manager.gd`, `modeling_lab.gd`,
`modeling_lab.tscn`, `test_full_lab_sweep.gd`.