# Level 3 – 3D Modeling Laboratory: Design Document

**Date:** 2026-07-28
**Project:** EMC Simulator
**Engine:** Godot 4.7.1 — Forward+, GDScript

---

## 1. Overview

Level 3 is a beginner-friendly 3D modeling training simulator for the EMC program. Players progress through 7 guided lessons, learning fundamental 3D concepts (position, rotation, scale, primitives, materials, hierarchy), then unlock a Creative Studio for free-form modeling.

### Learning Outcomes

- 3D space navigation (orbit, pan, zoom)
- Object manipulation (move, rotate, scale)
- Primitive modeling (cube, sphere, cylinder, cone, capsule, plane, torus)
- Object hierarchy and scene organization
- Materials (color, metallic, roughness, emission, transparency)
- Accuracy-based construction challenges

---

## 2. Architecture

### 2.1 Scene Pattern

**Root:** `CanvasLayer` — consistent with Programming Lab (Level 1) and Digital Art Lab (Level 2).

**3D Rendering:** A `SubViewportContainer` + `SubViewport` embedded in the CanvasLayer renders the 3D modeling workspace. All UI elements (toolbars, panels, dialogs) are standard Control nodes.

### 2.2 Scene Hierarchy

```
ModelingLab (CanvasLayer) — modeling_lab.gd
├── TopBar (HBoxContainer)
│   ├── BackBtn (Button)
│   ├── TitleLabel (Label) — "3D Modeling Laboratory"
│   ├── Spacer
│   ├── LessonLabel (Label) — "Lesson 1: Move Object"
│   ├── Spacer
│   ├── HintBtn (Button)
│   └── CloseBtn (Button)
│
├── LeftToolbar (VBoxContainer)
│   ├── MoveBtn (Button) — toggle tool
│   ├── RotateBtn (Button)
│   ├── ScaleBtn (Button)
│   ├── HSeparator
│   ├── DuplicateBtn (Button)
│   ├── DeleteBtn (Button)
│   ├── ResetBtn (Button)
│   ├── CenterBtn (Button)
│   ├── HSeparator
│   ├── GridToggle (CheckButton)
│   ├── SnapToggle (CheckButton)
│   └── SnapSize (SpinBox)
│
├── SubViewportContainer — anchors full center area
│   └── SubViewport (transparent_bg = true)
│       └── Workspace (Node3D) — class_name ModelingWorkspace
│           ├── WorldEnvironment — dark university lab ambience
│           ├── DirectionalLight3D — shadows enabled
│           ├── FloorGrid (MeshInstance3D + Grid)
│           ├── WorldAxis (MeshInstance3D — RGB XYZ arrows)
│           ├── CameraController (Camera3D) — orbit/pan/zoom
│           ├── GizmoContainer (Node3D) — transform gizmo overlay
│           ├── GhostGuideContainer (Node3D) — all ghost primitives
│           └── ObjectContainer (Node3D) — all player-created objects
│
├── RightPanel (VBoxContainer)
│   ├── TabContainer
│   │   ├── Tab: Hierarchy — HierarchyPanel (VBoxContainer)
│   │   │   ├── Tree (Tree control)
│   │   │   └── BtnRow: [Rename, Delete, Duplicate, Parent, Unparent]
│   │   ├── Tab: Inspector — InspectorPanel (VBoxContainer)
│   │   │   ├── PositionX/Y/Z (SpinBox * 3)
│   │   │   ├── RotationX/Y/Z (SpinBox * 3)
│   │   │   ├── ScaleX/Y/Z (SpinBox * 3)
│   │   │   └── NameEdit (LineEdit)
│   │   ├── Tab: Materials — MaterialPanel (VBoxContainer)
│   │   │   ├── BaseColorSwatch (ColorRect)
│   │   │   ├── MetallicSlider (HSlider)
│   │   │   ├── RoughnessSlider (HSlider)
│   │   │   ├── EmissionToggle (CheckButton) + EmissionColor (ColorRect)
│   │   │   ├── TransparencySlider (HSlider)
│   │   │   └── Presets: [Plastic, Metal, Wood, Stone, Glass]
│   │   └── Tab: Assignment — AssignmentPanel (VBoxContainer)
│   │       ├── LessonTitle (Label)
│   │       ├── Instructions (RichTextLabel — word-wrapped)
│   │       ├── StepList (VBoxContainer — step checkmarks)
│   │       ├── AccuracyGroup (VBoxContainer)
│   │       │   ├── PosAccuracy (ProgressBar + Label)
│   │       │   ├── RotAccuracy (ProgressBar + Label)
│   │       │   └── ScaleAccuracy (ProgressBar + Label)
│   │       └── PrevBtn / NextBtn (Button — lesson navigation)
│   └── (Tabs)
│
├── BottomBar (HBoxContainer)
│   ├── ToolLabel (Label) — "Tool: Move"
│   ├── TransformLabels (Label) — "X: 1.00  Y: 0.50  Z: 2.00"
│   ├── VSeparator
│   ├── ModeLabel (Label) — "World" / "Local"
│   ├── VSeparator
│   └── ZoomLabel (Label) — "Zoom: 100%"
│
├── SaveDialog (Panel) — overlay
├── LoadDialog (Panel) — overlay with ItemList
├── CompletionPanel (Panel) — "Assignment Complete!" + score
├── GradeCard (Panel) — full-screen grade reveal (S/A/B/C/Retry)
├── CreativeStudioUnlockPanel (Panel) — congratulations notification
├── Toast (Panel) — floating 2-second notification
└── HintOverlay (Panel) — tutorial overlay text
```

### 2.3 Mode System

The lab operates in two modes, controlled by a flag on `ModelingLab`:

```gdscript
enum LabMode { LESSON, CREATIVE_STUDIO }
```

- **LESSON** — 7 guided assignments with ghost guides, accuracy checks, grading
- **CREATIVE_STUDIO** — unlocked after lesson 7; free modeling with all tools, save/load

---

## 3. Subsystem Components

All subsystems are `RefCounted` objects created and wired by the main `ModelingLab` controller (following the Level 2 pattern).

### 3.1 Script Inventory

| File | Class | Role | Key Methods |
|------|-------|------|-------------|
| `modeling_lab.gd` | `ModelingLab` | Main controller | `_ready()`, `_on_close()`, `_load_assignment()`, `_check_completion()` |
| `assignment_manager.gd` | `AssignmentManager` | Loads/advances assignments | `load_assignment(id)`, `get_next()`, `advance()`, `is_last_assignment()` |
| `ghost_guide_manager.gd` | `GhostGuideManager` | Spawns/updates ghost guides | `spawn_for_assignment(data)`, `update_feedback(object_idx, accuracy)`, `clear()` |
| `primitive_spawner.gd` | `PrimitiveSpawner` | Creates 3D primitives | `spawn(type, parent_node)`, `get_mesh_for_type(type)` |
| `selection_manager.gd` | `SelectionManager` | Raycast click selection | `select_from_click(screen_pos)`, `select(node)`, `deselect_all()`, `get_selected()` |
| `transform_manager.gd` | `TransformManager` | Applies transforms + gizmo | `begin_transform()`, `apply_transform(delta)`, `end_transform()`, `snap_value(value, snap)` |
| `gizmo_3d.gd` | `Gizmo3D` | RGB arrow/ring gizmo | `set_target(node)`, `get_axis_from_ray(ray)`, `update()` |
| `accuracy_manager.gd` | `AccuracyManager` | Transform comparison math | `compare(player_xform, ghost_xform) -> {pos, rot, scale, overall}` |
| `scoring_manager.gd` | `ScoringManager` | Grade calculation | `grade_from_percent(pct)`, `calculate_final(primitive_scores)`, `is_perfect(pct)` |
| `material_manager.gd` | `MaterialManager` | Simple material editing | `apply_to(node, props)`, `apply_preset(preset_name, node)` |
| `hierarchy_manager.gd` | `HierarchyManager` | Object tree tracking | `get_tree_data()`, `reparent(child, new_parent)`, `rename(node, name)`, `delete(node)` |
| `camera_controller.gd` | `CameraController` | Orbit camera | `handle_input(event)`, `focus_on(node)`, `fit_all()`, `reset_view()` |
| `save_manager.gd` | `SaveManager` | Persist 3D models | `save_model(data, name)`, `load_model(path)`, `list_saved()`, `delete(path)` |
| `model_data.gd` | `ModelData` | Resource: serializable model | fields: `model_name`, `primitives[]`, `creation_date`, `thumbnail` |
| `creative_studio_manager.gd` | `CreativeStudioManager` | Free mode controller | `spawn_primitive(type)`, `is_unlocked()`, `unlock()` |
| `portfolio_manager.gd` | `PortfolioManager3D` | Portfolio browser | `refresh()`, `get_entries()`, `open_artifact(idx)`, `delete(idx)` |
| `undo_manager.gd` | `UndoManager` | Undo/redo stack | `push(action)`, `undo()`, `redo()`, `can_undo()`, `can_redo()` |
| `snap_settings.gd` | `SnapSettings` | Snap config | `position_snap = 0.25`, `rotation_snap = 15.0`, `scale_snap = 0.1`, `grid_visible = true` |
| `assignment_data.gd` | `AssignmentData` | Resource: assignment definition | fields: `assignment_id`, `display_name`, `lesson_number`, `primitives[]` |
| `primitive_def.gd` | `PrimitiveDef` | Resource: one primitive spec | fields: `type`, `target_position`, `target_rotation`, `target_scale`, `material_*` |
| `assignment_progress.gd` | `AssignmentProgress` | Resource: persisted progress | fields: `completed_ids[]`, `best_scores{}` |

### 3.2 Wiring Pattern (in `modeling_lab.gd`)

```gdscript
func _ready():
    workspace = $SubViewportContainer/SubViewport/Workspace
    camera_controller = CameraController.new(workspace.get_node("CameraController"))
    assignment_manager = AssignmentManager.new()
    ghost_guide_manager = GhostGuideManager.new(workspace)
    primitive_spawner = PrimitiveSpawner.new(workspace.get_node("ObjectContainer"))
    selection_manager = SelectionManager.new(workspace, camera_controller)
    transform_manager = TransformManager.new(selection_manager, snap_settings)
    gizmo = Gizmo3D.new(workspace.get_node("GizmoContainer"))
    accuracy_manager = AccuracyManager.new()
    scoring_manager = ScoringManager.new()
    material_manager = MaterialManager.new()
    hierarchy_manager = HierarchyManager.new(workspace)
    save_manager = SaveManager.new()
    portfolio_manager = PortfolioManager3D.new(save_manager)
    undo_manager = UndoManager.new()
    creative_studio_manager = CreativeStudioManager.new()
    snap_settings = SnapSettings.new()

    _find_ui_nodes()
    _connect_ui_signals()
    _load_or_resume_progress()
    _load_current_assignment()
    camera_controller.fit_all()
```

---

## 4. Data-Driven Assignment System

### 4.1 Resource Definitions

**`assignment_data.gd`** — one file per assignment:

```gdscript
class_name AssignmentData extends Resource
@export var assignment_id: String
@export var display_name: String
@export var lesson_number: int
@export var skills_taught: Array[String]  # ["move", "scale", "rotate", "duplicate", "material", "hierarchy"]
@export var instruction_text: String
@export var primitives: Array[PrimitiveDef]
```

**`primitive_def.gd`** — defines one reference primitive:

```gdscript
class_name PrimitiveDef extends Resource
enum Type { CUBE, SPHERE, CYLINDER, CONE, CAPSULE, PLANE, TORUS }
@export var type: Type
@export var target_position: Vector3
@export var target_rotation: Vector3      # Euler degrees
@export var target_scale: Vector3
@export var parent_id: String = ""         # hierarchy reference
@export var material_color: Color = Color.WHITE
@export var material_metallic: float = 0.0
@export var material_roughness: float = 0.5
```

### 4.2 Assignment Files (under `data/assignments/`)

| File | ID | Lesson | Primitives | Skills |
|------|-----|-------|------------|--------|
| `crate.tres` | `crate` | 1 | 1 cube (0,0.5,0) | move, scale |
| `traffic_cone.tres` | `traffic_cone` | 2 | 1 cylinder (0,0.25,0, 0.5,0.5,1 cone) + 1 cone (0,1,0) | move, scale |
| `chair.tres` | `chair` | 3 | 4 cubes (legs) + 1 cube (seat) + 1 cube (backrest) | duplicate, move, rotate |
| `table.tres` | `table` | 4 | 4 cylinders (legs) + 1 cube (top) | multiple objects, scale |
| `lamp.tres` | `lamp` | 5 | 1 cylinder (base) + 1 sphere (bulb) + 1 cone (shade) + colors | materials |
| `robot.tres` | `robot` | 6 | ~8 primitives with hierarchy (body, head, arms, legs) | hierarchy, precision |
| `mascot.tres` | `mascot` | 7 | ~10 primitives, all skills combined | all skills |

### 4.3 Progress Persistence

`assignment_progress.gd` — saved to `user://modeling_lab_progress.tres`:

```gdscript
class_name AssignmentProgress extends Resource
@export var completed_ids: Array[String] = []
@export var best_scores: Dictionary = {}   # {"crate": 97.6, "traffic_cone": 88.0}
@export var creative_studio_unlocked: bool = false
```

---

## 5. Ghost Guide System

### 5.1 Spawning

When `AssignmentManager` loads a new assignment:

1. Clear all existing ghost guides from `GhostGuideContainer`
2. For each `PrimitiveDef` in the assignment:
   - Spawn the matching primitive type
   - Set its transform to the target values
   - Apply ghost material: blue (#4A9EFF), 20% opacity, glow emission
   - Set groups, disable collision/lock/selection
   - Add to `GhostGuideContainer`

### 5.2 Real-Time Visual Feedback

The accuracy system runs a comparison every time a player object's transform changes:

| Distance from Perfect | Ghost Color | Threshold |
|----------------------|-------------|-----------|
| Far | Red (#FF4444) | overall < 50% |
| Close | Yellow (#FFD700) | 50% <= overall < 90% |
| Very Close | Green (#44FF44) | 90% <= overall < 98% |
| Perfect | Fade to transparent | overall >= 98% |

The ghost material's `albedo_color` and `emission` are smoothly tweened between these colors based on real-time accuracy score.

### 5.3 Locking

When a primitive reaches 98%+ on position, rotation, AND scale simultaneously:
1. Ghost fades out over 0.3 seconds (tween opacity 0.2 → 0.0)
2. Player object gets a subtle green border glow
3. Object is locked (transforms no longer apply)
4. `undo_manager.push` records the lock state
5. Audio: `PerfectMatch` sound plays
6. Floating label "Perfect!" appears briefly
7. `AccuracyDisplay` shows the final score for that primitive

### 5.4 UI Feedback Changes

The left-side tool buttons are color-coded per the spec:
- Tool icons use the dark theme with blue accent
- Active tool is highlighted
- Grid/Snap toggles have indicator lights

---

## 6. Accuracy and Scoring System

### 6.1 Transform Comparison

All accuracy is calculated by **mathematical transform comparison** — no collision overlap. The `AccuracyManager` is stateless and purely functional:

```gdscript
class AccuracyManager extends RefCounted:
    func compare(player: Transform3D, ghost: Transform3D, thresholds: Dictionary = {}):
        var t = _default_thresholds.duplicate()
        if thresholds: t.merge(thresholds)
        
        var pos_error = player.origin.distance_to(ghost.origin)
        var pos_score = clampf(1.0 - (pos_error / t.pos_max), 0.0, 1.0) * 100.0
        
        var p_quat = player.basis.get_rotation_quaternion()
        var g_quat = ghost.basis.get_rotation_quaternion()
        var angle = p_quat.angle_to(g_quat)  # radians
        var rot_score = clampf(1.0 - (angle / deg_to_rad(t.rot_max_deg)), 0.0, 1.0) * 100.0
        
        var p_scale = player.basis.scale
        var g_scale = ghost.basis.scale
        var scale_error = p_scale.distance_to(g_scale)
        var scale_score = clampf(1.0 - (scale_error / t.scale_max), 0.0, 1.0) * 100.0
        
        var overall = (pos_score + rot_score + scale_score) / 3.0
        return {pos=pos_score, rot=rot_score, scale=scale_score, overall=overall}
```

### 6.2 Configurable Thresholds (in Inspector)

```
@export var accuracy_thresholds := {
    pos_max = 2.0,      # units — max error for 0% score
    rot_max_deg = 90.0,  # degrees — max error for 0%
    scale_max = 2.0,     # ratio — max error for 0%
    perfect_threshold = 98.0,  # % — auto-lock
    close_threshold = 90.0,    # % — green feedback
    medium_threshold = 50.0,   # % — yellow feedback
}
```

### 6.3 Grading

```
S = 95-100 → "Outstanding!"
A = 90-94  → "Excellent!"
B = 80-89  → "Good!"
C = 70-79  → "Passable"
Retry < 70 → "Try Again"
```

Final score = average of all primitives' `overall` scores. Grade card displays as a full-screen overlay with animated progress bars for each primitive and the composite grade.

---

## 7. Transform Gizmo

### 7.1 Gizmo3D Visual

The gizmo is rendered as 3D arrow meshes (for Move) and ring meshes (for Rotate) floating at the selected object's position:

- **X axis:** Red (#FF4444) — arrow/ring
- **Y axis:** Green (#44FF44) — arrow/ring
- **Z axis:** Blue (#4444FF) — arrow/ring

### 7.2 Interaction

1. Player clicks on an axis arrow/ring via raycast
2. Axis is selected (highlighted)
3. Mouse drag moves/rotates along that axis
4. Release ends the transform
5. Undo records the transform before/after

### 7.3 World/Local Space Toggle

Bottom bar toggle switches the gizmo orientation:
- **World:** Gizmo aligned to global XYZ axes
- **Local:** Gizmo aligned to the selected object's local rotation

Visual difference: local mode gizmo rotates with the object, world stays fixed.

---

## 8. Material System

### 8.1 MaterialEditor Panel

The Material tab in the right panel shows:

| Control | Property | Range |
|---------|----------|-------|
| ColorRect (clickable) | Base Color | Full color picker dialog |
| HSlider | Metallic | 0.0–1.0 |
| HSlider | Roughness | 0.0–1.0 |
| CheckButton + ColorRect | Emission Toggle + Color | On/Off + color picker |
| HSlider | Transparency | 0.0–1.0 (transparency enabled when > 0) |
| 5 Buttons (row) | Presets | Plastic, Metal, Wood, Stone, Glass |

### 8.2 Preset Values

| Preset | Metallic | Roughness | Notes |
|--------|----------|-----------|-------|
| Plastic | 0.0 | 0.4 | Bright base color |
| Metal | 0.9 | 0.3 | Silver/grey base |
| Wood | 0.0 | 0.9 | Brown base |
| Stone | 0.0 | 0.95 | Grey base |
| Glass | 0.0 | 0.0 | Full transparency, high emission |

### 8.3 Application

Changes apply to the currently selected object in real-time:

```gdscript
func apply_to(node: MeshInstance3D, props: Dictionary):
    var mat := StandardMaterial3D.new()
    if props.has("albedo"): mat.albedo_color = props.albedo
    if props.has("metallic"): mat.metallic = props.metallic
    if props.has("roughness"): mat.roughness = props.roughness
    if props.has("emission_enabled"):
        mat.emission_enabled = props.emission_enabled
        mat.emission = props.emission_color
    if props.has("transparency"):
        mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if props.transparency > 0 else 0
        mat.alpha = props.transparency
    node.set_surface_override_material(0, mat)
```

---

## 9. Creative Studio

### 9.1 Unlock Condition

Automatically unlocked when `AssignmentProgress.completed_ids` contains all 7 assignment IDs. The `CreativeStudioUnlockPanel` is shown with congratulations text.

### 9.2 Features

| Feature | Implementation |
|---------|---------------|
| Unlimited primitives | Dropdown menu in top bar: "Spawn → Cube/Sphere/..." |
| Free transform | All tools available (move, rotate, scale) |
| Full material editing | Material panel applied to any selected object |
| Hierarchy management | Parent/unparent/rename/delete in Hierarchy panel |
| Save model | `SaveManager.save_model(ModelData, name)` → `data/player_models/` |
| Load model | `PortfolioManager3D` browser in Load dialog |
| Model gallery | List of saved models with names and dates |

### 9.3 UI Differences from Lesson Mode

- Ghost guides hidden
- Accuracy panel hidden
- "Spawn" dropdown visible in top bar
- Assignment tab says "Creative Studio — Free Modeling"
- Save/Load buttons always active

---

## 10. Save/Load and Portfolio

### 10.1 Model Data Format

```gdscript
class_name ModelData extends Resource

@export var model_name: String
@export var creation_date: String
@export var primitives: Array[PrimitiveSaveData]

class_name PrimitiveSaveData extends Resource
@export var type: int                    # PrimitiveDef.Type enum
@export var position: Vector3
@export var rotation_degrees: Vector3
@export var scale: Vector3
@export var material: MaterialSaveData
@export var parent_name: String
@export var node_name: String
```

### 10.2 Save/Load Flow

**Save:**
1. `SaveManager` walks all objects in `ObjectContainer`
2. For each, creates `PrimitiveSaveData` with current transform + material
3. Captures a thumbnail (render SubViewport to Image)
4. Packs into `ModelData` Resource
5. Writes to `res://data/player_models/{name}.tres`

**Load:**
1. Loads `.tres` file
2. `SaveManager.load_model()` reconstructs all primitives
3. Restores transforms, materials, hierarchy
4. Sets `workspace` state to loaded model

### 10.3 Portfolio Manager

Follows the same pattern as Level 2's `PortfolioManager`:
- Scans `res://data/player_models/` for `.tres` files
- Returns `[{path, name, date}]`
- `open_artifact(index)` → loads + emits `model_opened` signal
- `delete(index)` / `rename(index, new_name)`

---

## 11. Camera Controller

### 11.1 Controls

| Action | Input | Implementation |
|--------|-------|---------------|
| Orbit | Middle-mouse drag | Rotate camera around origin pivot point |
| Pan | Shift + middle-mouse drag | Move pivot point |
| Zoom | Mouse wheel | Move camera closer/further from pivot |
| Focus Selected | F key | Smooth tween to center on selected object |
| Frame All | Shift+F | Zoom out to fit all objects in view |
| Reset View | Home key | Return to default camera position |

### 11.2 Implementation

```gdscript
class CameraController extends Node3D:
    @export var orbit_speed := 0.005
    @export var zoom_speed := 1.0
    @export var pan_speed := 0.02
    @export var min_distance := 0.5
    @export var max_distance := 50.0
    @export var default_distance := 8.0
    @export var default_rotation := Vector2(0.4, 0.0)  # elevation, azimuth radians

    func handle_input(event: InputEvent):
        # orbit, pan, zoom logic
    
    func focus_on(target: Vector3):
        # tween camera to center on target
    
    func fit_all():
        # calculate BBox of all objects, adjust distance
```

---

## 12. Hierarchy Panel

A `Tree` control listing all objects in `ObjectContainer`:

- Drag-and-drop to reparent
- Right-click context menu: Rename, Delete, Duplicate
- Checkbox for visibility (eye icon)
- Lock icon toggle
- Nested indentation for parent/child relationships
- Click to select object

---

## 13. Transform Tools

### 13.1 Move Tool

- Active tool: arrows on gizmo
- Mouse drag along arrow: object moves along that axis
- Status bar shows real-time X/Y/Z position

### 13.2 Rotate Tool

- Active tool: colored rings on gizmo
- Click ring → rotation around that axis
- Rotation snap: configurable degrees (default 15°)

### 13.3 Scale Tool

- Active tool: small cubes at arrow tips
- Drag arrow → uniform scale
- Shift+drag → non-uniform scale on axis
- Scale snap: configurable (default 0.1)

### 13.4 Undo/Redo

Every transform start records the state. On release, a `TransformAction` is pushed to the undo stack. Ctrl+Z / Ctrl+Y for undo/redo.

---

## 14. Level Progression Integration

### 14.1 Entry Points

The lab is accessible from:
1. **Main menu** — `ModelButton` labelled "3D MODEL" positioned between ART and LAB buttons. `main_menu.gd` has `@export_file("*.tscn") var modeling_lab_path` pointed at `res://scenes/modeling_lab/modeling_lab.tscn`. Handler `_on_model_pressed()` calls `SceneTransition.change_scene(modeling_lab_path)`.
2. **World hub** — the existing `3d_design_lab.tscn` door in `world_demo.tscn` (or a new door)

### 14.2 Completion Flow

Level 3 is considered "complete" when the player has completed all 7 assignments (not creative studio). On close:

```gdscript
func _on_close():
    lab_closed.emit()
    if _progress.completed_ids.size() >= 7:
        var level_def := ResourceLoader.load("res://data/levels/3d_design_lab.tres")
        if level_def:
            LevelProgression.complete_level(level_def)
    get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
```

The existing `3d_design_lab.tres` level definition is reused — no changes needed to the sequence or level definitions.

### 14.3 Portfolio Integration

Completed models from the 3D lab are accessible from the main menu's portfolio view in future levels (same pattern as Level 2's artwork portfolio).

---

## 15. UI and Visual Style

### 15.1 Theme

- Dark background (#1A1A2E)
- Blue accent (#4A9EFF)
- Rounded panels (border-radius 8px, via `StyleBoxFlat`)
- Smooth tween animations (0.2s ease-out)
- Consistent with existing lab levels

### 15.2 Bottom Bar Info

Bottom bar shows real-time data:
- `Tool: Move` — current active tool
- `X: 1.25  Y: 0.50  Z: 2.00` — selected object position
- `World` / `Local` — transform space toggle
- `Snap: 0.25` — current snap increment

---

## 16. Audio

| Event | Sound | Notes |
|-------|-------|-------|
| Tool select | Soft UI click | Same as Level 2 |
| Object snap | Subtle tick | When snap aligns |
| Object lock | Mechanical click | When primitive locks |
| Perfect match | Bright chime | "Perfect!" notification |
| Assignment complete | Fanfare | Full assignment done |
| Grade reveal | Drum roll → reveal | Grade card animation |
| Button hover | Subtle hover | UI feedback |

Audio resources are loaded from `assets/sound/` (to be added when sound design assets are ready — stubbed with `AudioStream` references).

---

## 17. Inspector-Configurable Exports

All key parameters are `@export` on their respective managers:

```gdscript
# snap_settings.gd
@export var position_snap: float = 0.25
@export var rotation_snap: float = 15.0
@export var scale_snap: float = 0.1

# accuracy_manager.gd
@export var pos_max_error: float = 2.0
@export var rot_max_error_deg: float = 90.0
@export var scale_max_error: float = 2.0
@export var perfect_threshold: float = 98.0

# ghost_guide_manager.gd
@export var ghost_opacity: float = 0.2
@export var ghost_color: Color = Color(0.29, 0.62, 1.0)

# camera_controller.gd
@export var orbit_speed: float = 0.005
@export var zoom_speed: float = 1.0
@export var min_distance: float = 0.5

# modeling_lab.gd (main scene)
@export var max_undo_steps: int = 50
@export var auto_save_interval: float = 120.0
```

---

## 18. Future Expansion Points

The architecture supports these future additions without redesign:

1. **Vertex/Edge/Face editing** — add `EditMode { OBJECT, VERTEX, EDGE, FACE }` to the model, edit operations operate on vertex arrays
2. **Extrude** — add to transform_manager or new `mesh_editor.gd`
3. **Bevel** — mesh operation on selected edges
4. **Mirror Modifier** — `modifier_manager.gd` applies post-process to mesh
5. **Subdivision** — add to mesh data pipeline
6. **Boolean Operations** — CSG node integration
7. **Rigging** — add skeleton/bone system to `ModelData`
8. **Animation** — keyframe recording on transforms
9. **Texture Painting** — UV layer in material system
10. **GLTF Export** — `SaveManager.gltf_export()` using Godot's GLTFDocument

---

## 19. File Layout Summary

```
scenes/modeling_lab/
├── modeling_lab.tscn
└── components/
    ├── workspace.tscn          # Workspace Node3D with lights/grid/environment
    ├── gizmo.tscn              # Gizmo3D scene with arrow/ring meshes
    └── assignment_card.tscn    # Grade card scene

scripts/modeling_lab/
├── modeling_lab.gd
├── assignment_manager.gd
├── assignment_data.gd
├── primitive_def.gd
├── ghost_guide_manager.gd
├── primitive_spawner.gd
├── selection_manager.gd
├── transform_manager.gd
├── gizmo_3d.gd
├── accuracy_manager.gd
├── scoring_manager.gd
├── material_manager.gd
├── hierarchy_manager.gd
├── camera_controller.gd
├── save_manager.gd
├── model_data.gd
├── portfolio_manager.gd
├── creative_studio_manager.gd
├── undo_manager.gd
├── snap_settings.gd
└── assignment_progress.gd

data/assignments/
├── crate.tres
├── traffic_cone.tres
├── chair.tres
├── table.tres
├── lamp.tres
├── robot.tres
└── mascot.tres

data/models/                    # Created at runtime
└── (player saves appear here)
```
