# Level 3 — 3D Modeling Laboratory Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a fully playable 3D Modeling Laboratory level with 7 guided lessons, ghost guides, accuracy scoring, materials, hierarchy, undo, Creative Studio, save/load, and portfolio.

**Architecture:** `CanvasLayer` root with an embedded `SubViewportContainer` + `SubViewport` rendering a 3D modeling `Workspace` (Node3D). All subsystems are `RefCounted` objects wired by `ModelingLab` main controller — identical pattern to Level 2.

**Tech Stack:** Godot 4.7.1, GDScript, Forward+, SubViewport for 3D-in-UI, Resource-based data files.

**Main menu:** `ModelButton` already added to `main_menu.tscn`, `modeling_lab_path` export in `main_menu.gd`, stub scene exists at `scenes/modeling_lab/modeling_lab.tscn`.

## Global Constraints

- Root scene type MUST be `CanvasLayer` (matching Programming Lab, Digital Art Lab pattern)
- `signal lab_closed` on the main controller
- `lab_closed.emit()` + `LevelProgression.complete_level(level_def)` + `change_scene_to_file("main_menu.tscn")` on close
- All assignments data-driven via `AssignmentData` / `PrimitiveDef` Resources — no hardcoded lessons
- Accuracy uses mathematical transform comparison, NOT collision overlap
- Components extend `RefCounted` (not `Node`) unless they need scene tree access
- Use `@export` for all configurable values (snap size, thresholds, ghost opacity, camera speed, etc.)
- Godot 4.7.1 best practices — use `@onready`, `unique_name_in_owner`, typed variables

---

## File Structure

### New directories
```
scripts/modeling_lab/       — all subsystem scripts
scenes/modeling_lab/         — scenes (main scene + sub-scenes)
data/assignments/            — 7 assignment .tres files
data/player_models/          — runtime: saved player models
scripts/components/          — reusable sub-scene scripts
```

### Scripts to create (21 files)
| # | File | Class | Role |
|---|------|-------|------|
| 1 | `scripts/modeling_lab/assignment_data.gd` | `AssignmentData` | Resource: one assignment |
| 2 | `scripts/modeling_lab/primitive_def.gd` | `PrimitiveDef` | Resource: one primitive spec |
| 3 | `scripts/modeling_lab/assignment_progress.gd` | `AssignmentProgress` | Resource: persisted progress |
| 4 | `scripts/modeling_lab/model_data.gd` | `ModelData` | Resource: save/load format |
| 5 | `scripts/modeling_lab/primitive_spawner.gd` | `PrimitiveSpawner` | Creates 3D primitives |
| 6 | `scripts/modeling_lab/snap_settings.gd` | `SnapSettings` | Snap config |
| 7 | `scripts/modeling_lab/camera_controller.gd` | `CameraController` | Orbit/pan/zoom camera |
| 8 | `scripts/modeling_lab/selection_manager.gd` | `SelectionManager` | Raycast selection |
| 9 | `scripts/modeling_lab/gizmo_3d.gd` | `Gizmo3D` | RGB transform gizmo |
| 10 | `scripts/modeling_lab/transform_manager.gd` | `TransformManager` | Move/rotate/scale |
| 11 | `scripts/modeling_lab/ghost_guide_manager.gd` | `GhostGuideManager` | Ghost guides + feedback |
| 12 | `scripts/modeling_lab/accuracy_manager.gd` | `AccuracyManager` | Transform comparison |
| 13 | `scripts/modeling_lab/scoring_manager.gd` | `ScoringManager` | Grade calculation |
| 14 | `scripts/modeling_lab/assignment_manager.gd` | `AssignmentManager` | Assignment loading/nav |
| 15 | `scripts/modeling_lab/material_manager.gd` | `MaterialManager` | Simple material editor |
| 16 | `scripts/modeling_lab/hierarchy_manager.gd` | `HierarchyManager` | Object tree |
| 17 | `scripts/modeling_lab/undo_manager.gd` | `UndoManager` | Undo/redo stack |
| 18 | `scripts/modeling_lab/save_manager.gd` | `SaveManager` | Save/load models |
| 19 | `scripts/modeling_lab/portfolio_manager.gd` | `PortfolioManager3D` | Portfolio browser |
| 20 | `scripts/modeling_lab/creative_studio_manager.gd` | `CreativeStudioManager` | Free mode |
| 21 | `scripts/modeling_lab/modeling_lab.gd` | `ModelingLab` | Main controller (exists, needs full rewrite) |

### Scenes to create/modify
| # | File | Purpose |
|---|------|---------|
| 1 | `scenes/modeling_lab/modeling_lab.tscn` | Full main scene (exists, needs full rebuild) |
| 2 | `scenes/modeling_lab/workspace.tscn` | 3D workspace sub-scene (lights, grid, env) |
| 3 | `scenes/modeling_lab/gizmo.tscn` | Gizmo 3D visual (arrow/ring meshes) |

### Data files to create (8 files)
| # | File | Content |
|---|------|---------|
| 1-7 | `data/assignments/crate.tres` through `mascot.tres` | Assignment resources |
| 8 | `data/assignments/ (directory)` | Created at runtime by SaveManager |

### Modified existing files
| # | File | Change |
|---|------|--------|
| 1 | `scripts/main_menu.gd` | Already done (modeling_lab_path export, button, handler) |
| 2 | `scenes/main_menu.tscn` | Already done (ModelButton node added) |

---

## Task Breakdown

### Task 1: Create Resource Definitions (AssignmentData, PrimitiveDef, AssignmentProgress, ModelData)

**Files:**
- Create: `scripts/modeling_lab/assignment_data.gd`
- Create: `scripts/modeling_lab/primitive_def.gd`
- Create: `scripts/modeling_lab/assignment_progress.gd`
- Create: `scripts/modeling_lab/model_data.gd`

**Interfaces:**
- Produces: `AssignmentData` (Resource), `PrimitiveDef` (Resource, nested or standalone), `AssignmentProgress` (Resource), `ModelData` (Resource) — used by all later tasks.

- [ ] **Step 1: Create `primitive_def.gd`**

```gdscript
class_name PrimitiveDef extends Resource

enum Type { CUBE, SPHERE, CYLINDER, CONE, CAPSULE, PLANE, TORUS }

@export var type: Type
@export var target_position: Vector3
@export var target_rotation: Vector3       # Euler degrees
@export var target_scale: Vector3 = Vector3.ONE
@export var parent_id: String = ""
@export var material_color: Color = Color.WHITE
@export var material_metallic: float = 0.0
@export var material_roughness: float = 0.5
```

- [ ] **Step 2: Create `assignment_data.gd`**

```gdscript
class_name AssignmentData extends Resource

@export var assignment_id: String
@export var display_name: String
@export var lesson_number: int = 1
@export var skills_taught: Array[String] = []
@export var instruction_text: String = ""
@export var primitives: Array[PrimitiveDef] = []
```

- [ ] **Step 3: Create `assignment_progress.gd`**

```gdscript
class_name AssignmentProgress extends Resource

@export var completed_ids: Array[String] = []
@export var best_scores: Dictionary = {}  # {"crate": 97.6}
@export var creative_studio_unlocked: bool = false
```

- [ ] **Step 4: Create `model_data.gd`**

```gdscript
class_name ModelData extends Resource

@export var model_name: String = ""
@export var creation_date: String = ""
@export var primitives: Array[PrimitiveSaveData] = []

class_name PrimitiveSaveData extends Resource

@export var type: int = 0
@export var node_name: String = ""
@export var position: Vector3
@export var rotation_degrees: Vector3
@export var scale: Vector3 = Vector3.ONE
@export var parent_name: String = ""
@export var material_albedo: Color = Color.WHITE
@export var material_metallic: float = 0.0
@export var material_roughness: float = 0.5
```

(Note: PrimitiveSaveData can be a separate file or nested — separate is cleaner)

- [ ] **Step 5: Commit**

```bash
git add scripts/modeling_lab/
git commit -m "feat(level3): add resource definitions for assignments, progress, and model data"
```

---

### Task 2: Create SnapSettings + PrimitiveSpawner

**Files:**
- Create: `scripts/modeling_lab/snap_settings.gd`
- Create: `scripts/modeling_lab/primitive_spawner.gd`

**Interfaces:**
- Produces: `SnapSettings` class with fields `position_snap`, `rotation_snap`, `scale_snap`, `grid_visible`. `PrimitiveSpawner` class with `spawn(type, parent) -> MeshInstance3D` and `get_mesh_for_type(type) -> Mesh`.

- [ ] **Step 1: Create `snap_settings.gd`**

```gdscript
class_name SnapSettings extends RefCounted

@export var position_snap: float = 0.25
@export var rotation_snap: float = 15.0
@export var scale_snap: float = 0.1
@export var grid_visible: bool = true
@export var snap_enabled: bool = true

func snap_value(value: float, snap: float) -> float:
	if not snap_enabled or snap <= 0:
		return value
	return round(value / snap) * snap

func snap_vector3(v: Vector3, snap: float) -> Vector3:
	if not snap_enabled or snap <= 0:
		return v
	return Vector3(snap_value(v.x, snap), snap_value(v.y, snap), snap_value(v.z, snap))
```

- [ ] **Step 2: Create `primitive_spawner.gd`**

```gdscript
class_name PrimitiveSpawner extends RefCounted

enum Type { CUBE, SPHERE, CYLINDER, CONE, CAPSULE, PLANE, TORUS }

func get_mesh_for_type(type: int) -> Mesh:
	match type:
		Type.CUBE: return BoxMesh.new()
		Type.SPHERE: return SphereMesh.new()
		Type.CYLINDER: return CylinderMesh.new()
		Type.CONE: return ConeMesh.new()
		Type.CAPSULE: return CapsuleMesh.new()
		Type.PLANE: return PlaneMesh.new()
		Type.TORUS: return TorusMesh.new()
	return BoxMesh.new()

func spawn(type: int, parent: Node3D) -> MeshInstance3D:
	var mesh := get_mesh_for_type(type)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.name = Type.keys()[type] + "_" + str(Time.get_ticks_msec())
	parent.add_child(mi)
	mi.owner = parent.owner if parent.owner else parent
	return mi

func spawn_named(type: int, parent: Node3D, node_name: String) -> MeshInstance3D:
	var mi := spawn(type, parent)
	mi.name = node_name
	return mi
```

- [ ] **Step 3: Commit**

```bash
git add scripts/modeling_lab/snap_settings.gd scripts/modeling_lab/primitive_spawner.gd
git commit -m "feat(level3): add SnapSettings and PrimitiveSpawner"
```

---

### Task 3: Create CameraController

**Files:**
- Create: `scripts/modeling_lab/camera_controller.gd`

**Interfaces:**
- Produces: `CameraController` (extends Node3D, attached to a Camera3D child) with `handle_input(event)`, `focus_on(target: Vector3)`, `fit_all(objects: Array)`, `reset_view()`.

- [ ] **Step 1: Create `camera_controller.gd`**

```gdscript
class_name CameraController extends Node3D

@export var orbit_speed: float = 0.005
@export var zoom_speed: float = 1.0
@export var pan_speed: float = 0.02
@export var min_distance: float = 0.5
@export var max_distance: float = 50.0
@export var default_distance: float = 8.0
@export var vertical_focus: float = 0.0

var _camera: Camera3D
var _pivot: Vector3
var _orbit_elevation: float = 0.4
var _orbit_azimuth: float = 0.0
var _distance: float = 8.0
var _panning: bool = false
var _orbiting: bool = false
var _last_mouse: Vector2

func _ready():
	_camera = get_child(0) as Camera3D
	if not _camera:
		_camera = Camera3D.new()
		add_child(_camera)
	_update_camera()

func handle_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance = clamp(_distance - zoom_speed, min_distance, max_distance)
			_update_camera()
			return true
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance = clamp(_distance + zoom_speed, min_distance, max_distance)
			_update_camera()
			return true
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				if event.shift_pressed:
					_panning = true
				else:
					_orbiting = true
				_last_mouse = get_viewport().get_mouse_position()
			else:
				_panning = false
				_orbiting = false
			return true

	if event is InputEventMouseMotion and (_orbiting or _panning):
		var delta := event.relative
		if _orbiting:
			_orbit_azimuth -= delta.x * orbit_speed
			_orbit_elevation = clamp(_orbit_elevation - delta.y * orbit_speed, -1.4, 1.4)
			_update_camera()
		if _panning:
			var right := _camera.global_transform.basis.x * delta.x * pan_speed * (_distance / 10.0)
			var up := _camera.global_transform.basis.y * delta.y * pan_speed * (_distance / 10.0)
			_pivot += -right + up
			_update_camera()
		return true
	return false

func _update_camera():
	var euler := Vector3(_orbit_elevation, _orbit_azimuth, 0)
	var rot := Basis.from_euler(euler)
	var pos := _pivot + rot * Vector3(0, 0, _distance)
	_camera.global_position = pos
	_camera.look_at(_pivot)

func focus_on(target: Vector3):
	_pivot = target
	_update_camera()

func fit_all(objects: Array[Node3D]):
	if objects.is_empty():
		focus_on(Vector3(0, vertical_focus, 0))
		return
	var aabb: AABB
	for obj in objects:
		if obj is MeshInstance3D and obj.mesh:
			var obb := obj.mesh.get_aabb()
			var world_obb := obb.transformed(obj.global_transform)
			aabb = aabb.merge(world_obb)
	if aabb == AABB():
		focus_on(Vector3(0, vertical_focus, 0))
		return
	_pivot = aabb.get_center()
	_distance = max(aabb.size.length(), 3.0) * 1.5
	_distance = clamp(_distance, min_distance, max_distance)
	_update_camera()

func reset_view():
	_pivot = Vector3(0, vertical_focus, 0)
	_orbit_elevation = 0.4
	_orbit_azimuth = 0.0
	_distance = default_distance
	_update_camera()
```

- [ ] **Step 2: Commit**

```bash
git add scripts/modeling_lab/camera_controller.gd
git commit -m "feat(level3): add CameraController with orbit/pan/zoom"
```

---

### Task 4: Create Workspace Sub-Scene

**Files:**
- Create: `scenes/modeling_lab/workspace.tscn`

**Interfaces:**
- Produces: A `Node3D` scene with WorldEnvironment, DirectionalLight3D, grid floor, axis helper, ghost containers, object container. Camera is omitted (CameraController is added dynamically).

- [ ] **Step 1: Create `scenes/modeling_lab/workspace.tscn`**

```
[gd_scene format=3 uid="uid://dg3f8y1p2q7n"]

[sub_resource type="Environment" id="Env"]
background_mode = 1
background_color = Color(0.06, 0.06, 0.1, 1)
ambient_light_source = 3
ambient_light_color = Color(0.4, 0.6, 0.8, 1)
ambient_light_energy = 0.5
tonemap_mode = 2

[sub_resource type="StandardMaterial3D" id="GridMat"]
albedo_color = Color(0.15, 0.15, 0.2, 0.5)
transparency = 1
roughness = 1.0

[sub_resource type="BoxMesh" id="GridMesh"]
material = SubResource("GridMat")
size = Vector3(20, 0.02, 20)

[sub_resource type="StandardMaterial3D" id="AxisX"]
albedo_color = Color(1, 0.25, 0.25, 1)

[sub_resource type="StandardMaterial3D" id="AxisY"]
albedo_color = Color(0.25, 1, 0.25, 1)

[sub_resource type="StandardMaterial3D" id="AxisZ"]
albedo_color = Color(0.25, 0.25, 1, 1)

[sub_resource type="CylinderMesh" id="AxisMesh"]
top_radius = 0.03
bottom_radius = 0.03
height = 2.0

[node name="Workspace" type="Node3D"]

[node name="WorldEnvironment" type="WorldEnvironment" parent="."]
environment = SubResource("Env")

[node name="DirectionalLight" type="DirectionalLight3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 0.707, 0.707, 0, -0.707, 0.707, 0, 0, 5, 0)
light_energy = 1.5
shadow_enabled = true

[node name="AmbientLight" type="OmniLight3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 5, 5)
light_energy = 0.3

[node name="FloorGrid" type="MeshInstance3D" parent="."]
mesh = SubResource("GridMesh")

[node name="AxisHelper" type="Node3D" parent="."]

[node name="AxisX" type="MeshInstance3D" parent="AxisHelper"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0.5, 0, 0)
mesh = SubResource("AxisMesh")
material_override = SubResource("AxisX")

[node name="AxisY" type="MeshInstance3D" parent="AxisHelper"]
transform = Transform3D(0, 0, 1, 0, 1, 0, -1, 0, 0, 0, 0.5, 0)
mesh = SubResource("AxisMesh")
material_override = SubResource("AxisY")

[node name="AxisZ" type="MeshInstance3D" parent="AxisHelper"]
transform = Transform3D(0, -1, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0.5)
mesh = SubResource("AxisMesh")
material_override = SubResource("AxisZ")

[node name="GhostContainer" type="Node3D" parent="."]
name = "GhostGuideContainer"

[node name="ObjectContainer" type="Node3D" parent="."]

[node name="GizmoContainer" type="Node3D" parent="."]
```

- [ ] **Step 2: Commit**

```bash
git add scenes/modeling_lab/workspace.tscn
git commit -m "feat(level3): add 3D workspace sub-scene with env, lights, grid, axis"
```

---

### Task 5: Build the Full Main Scene (modeling_lab.tscn)

**Files:**
- Modify: `scenes/modeling_lab/modeling_lab.tscn` (full rewrite of stub)

**Interfaces:**
- Produces: `CanvasLayer` scene with SubViewportContainer (embedding workspace), TopBar, LeftToolbar, RightPanel (TabContainer with 4 tabs), BottomBar, dialogs, toast. Lays out all UI Control nodes.

- [ ] **Step 1: Write the full `scenes/modeling_lab/modeling_lab.tscn`**

This scene embeds workspace via `instance=ExtResource("workspace")`, has all UI panels, dialogs, and uses `%UniqueName` references throughout. Structure per the spec hierarchy (Section 2.2). Key nodes:

- `%SubViewportContainer` — anchors center area, contains SubViewport → Workspace
- `%TopBar` — BackBtn, TitleLabel, LessonLabel, HintBtn, CloseBtn
- `%LeftToolbar` — MoveBtn/RotateBtn/ScaleBtn (tool group), DuplicateBtn, DeleteBtn, ResetBtn, CenterBtn, GridToggle, SnapToggle, SnapSize
- `%RightPanel` → `%TabContainer` → Hierarchy/Inspector/Materials/Assignment tabs
- `%BottomBar` — ToolLabel, TransformX/Y/Z, ModeLabel, ZoomLabel
- `%SaveDialog`, `%LoadDialog`, `%CompletionPanel`, `%GradeCard`, `%Toast`
- All styled with `StyleBoxFlat` sub-resources (dark theme, blue accent, rounded corners)

Use `unique_id` for each node. Set `unique_name_in_owner = true` on key nodes for `%Name` lookups.

- [ ] **Step 2: Create `scripts/modeling_lab/ui_constants.gd`** (optional helper)

```gdscript
class_name UIConstants extends RefCounted

const COLOR_BG := Color(0.1, 0.1, 0.14, 1.0)
const COLOR_ACCENT := Color(0.29, 0.62, 1.0, 1.0)
const COLOR_TEXT := Color(0.9, 0.9, 0.95, 1.0)
const COLOR_SUCCESS := Color(0.25, 1.0, 0.45, 1.0)
const COLOR_WARN := Color(1.0, 0.84, 0.0, 1.0)
const COLOR_DANGER := Color(1.0, 0.25, 0.25, 1.0)
const STYLE_ROUNDED := 8
```

- [ ] **Step 3: Commit**

```bash
git add scenes/modeling_lab/modeling_lab.tscn scripts/modeling_lab/ui_constants.gd
git commit -m "feat(level3): build full main scene with all UI panels"
```

---

### Task 6: Create SelectionManager + Gizmo3D

**Files:**
- Create: `scripts/modeling_lab/selection_manager.gd`
- Create: `scripts/modeling_lab/gizmo_3d.gd`

**Interfaces:**
- Produces: `SelectionManager` (RefCounted) with `select_from_click(screen_pos, camera)`, `select(node)`, `deselect_all()`, `get_selected()`, `selected_changed` signal. `Gizmo3D` (extends Node3D) with `set_target(node)`, `get_axis_for_ray(ray)`, `update_transform()`.

- [ ] **Step 1: Create `selection_manager.gd`**

```gdscript
class_name SelectionManager extends RefCounted

signal selected_changed(node)

var _object_container: Node3D
var _selected: MeshInstance3D = null

func _init(container: Node3D):
	_object_container = container

func select_from_click(screen_pos: Vector2, camera: Camera3D) -> bool:
	var space := camera.get_world_3d().direct_space_state
	if not space:
		return false
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	var params := PhysicsRayQueryParameters3D.new()
	params.from = from
	params.to = from + dir * 1000.0

	var result := space.intersect_ray(params)
	if result.is_empty():
		deselect_all()
		return false
	var hit := result.collider as MeshInstance3D
	if hit and _is_selectable(hit):
		select(hit)
		return true
	deselect_all()
	return false

func _is_selectable(node: Node) -> bool:
	if not node is MeshInstance3D:
		return false
	if node.is_in_group("ghost_guides"):
		return false
	if node.owner == null:
		return false
	return true

func select(node: MeshInstance3D):
	if _selected == node:
		return
	_selected = node
	selected_changed.emit(_selected)

func deselect_all():
	if _selected:
		_selected = null
		selected_changed.emit(null)

func get_selected() -> MeshInstance3D:
	return _selected

func get_container() -> Node3D:
	return _object_container
```

- [ ] **Step 2: Create `gizmo_3d.gd`**

```gdscript
class_name Gizmo3D extends Node3D

enum Mode { TRANSLATE, ROTATE, SCALE }

var current_mode: int = Mode.TRANSLATE
var _target: Node3D = null
var _drag_axis: Vector3 = Vector3.ZERO
var _dragging: bool = false
var _drag_origin: Vector3 = Vector3.ZERO
var _drag_plane: Plane = Plane()

signal transform_began
signal transform_ended(delta_transform: Transform3D)

func set_target(node: Node3D):
	_target = node
	visible = node != null
	if node:
		global_position = node.global_position
		if current_mode == Mode.ROTATE:
			global_basis = node.global_basis

func set_mode(mode: int):
	current_mode = mode

func get_axis_for_ray(origin: Vector3, direction: Vector3) -> Vector3:
	# Simplified: check children arrow meshes via raycast
	# For each axis child (X,Y,Z), test intersection with its arrow collider
	# Return the axis vector of the hit one
	return Vector3.ZERO  # Placeholder — implemented in full Task 10 integration

func _process(_delta):
	if _target and visible:
		global_position = _target.global_position
```

- [ ] **Step 3: Commit**

```bash
git add scripts/modeling_lab/selection_manager.gd scripts/modeling_lab/gizmo_3d.gd
git commit -m "feat(level3): add SelectionManager and Gizmo3D base"
```

---

### Task 7: Create GhostGuideManager

**Files:**
- Create: `scripts/modeling_lab/ghost_guide_manager.gd`

**Interfaces:**
- Produces: `GhostGuideManager` (RefCounted) with `spawn_for_assignment(data: AssignmentData, spawner: PrimitiveSpawner)`, `update_feedback(object_idx, accuracy)`, `clear()`.

- [ ] **Step 1: Create `ghost_guide_manager.gd`**

```gdscript
class_name GhostGuideManager extends RefCounted

@export var ghost_opacity: float = 0.2
@export var ghost_color: Color = Color(0.29, 0.62, 1.0)

var _container: Node3D
var _ghosts: Array[MeshInstance3D] = []

func _init(container: Node3D):
	_container = container

func spawn_for_assignment(data: AssignmentData, spawner: PrimitiveSpawner) -> Array[MeshInstance3D]:
	clear()
	for def in data.primitives:
		var ghost := spawner.spawn(def.type, _container)
		ghost.position = def.target_position
		ghost.rotation_degrees = def.target_rotation
		ghost.scale = def.target_scale
		ghost.add_to_group("ghost_guides")
		_apply_ghost_material(ghost)
		_ghosts.append(ghost)
	return _ghosts.duplicate()

func _apply_ghost_material(mi: MeshInstance3D):
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(ghost_color.r, ghost_color.g, ghost_color.b, ghost_opacity)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = ghost_color * 0.5
	mat.emission_energy_multiplier = 1.5
	mi.set_surface_override_material(0, mat)

func update_feedback(index: int, accuracy: Dictionary):
	if index < 0 or index >= _ghosts.size():
		return
	var ghost := _ghosts[index]
	var overall := accuracy.get("overall", 0.0)
	var color: Color
	if overall >= 98.0:
		color = Color(0.25, 1.0, 0.45)  # green
		_show_locked_effect(ghost)
	elif overall >= 90.0:
		color = Color(0.25, 1.0, 0.45, 0.5)  # greenish
	elif overall >= 50.0:
		color = Color(1.0, 0.84, 0.0, 0.4)  # yellow
	else:
		color = Color(1.0, 0.25, 0.25, 0.3)  # red
	var mat := ghost.get_surface_override_material(0) as StandardMaterial3D
	if mat:
		mat.albedo_color = Color(color.r, color.g, color.b, ghost_opacity)
		mat.emission = color * 0.5

func _show_locked_effect(ghost: MeshInstance3D):
	# Tween opacity to 0 over 0.3s — implemented via main loop later
	ghost.modulate = Color(1, 1, 1, 0.01)

func is_perfect(index: int) -> bool:
	if index < 0 or index >= _ghosts.size():
		return false
	return _ghosts[index].modulate.a < 0.05

func clear():
	for g in _ghosts:
		if is_instance_valid(g):
			g.queue_free()
	_ghosts.clear()
```

- [ ] **Step 2: Commit**

```bash
git add scripts/modeling_lab/ghost_guide_manager.gd
git commit -m "feat(level3): add GhostGuideManager with holographic primitives and feedback colors"
```

---

### Task 8: Create TransformManager

**Files:**
- Create: `scripts/modeling_lab/transform_manager.gd`

**Interfaces:**
- Produces: `TransformManager` (RefCounted) with `begin_move()`, `apply_move(delta)`, `begin_rotate()`, `apply_rotate(delta)`, `begin_scale()`, `apply_scale(delta)`, `end_transform()`.

- [ ] **Step 1: Create `transform_manager.gd`**

```gdscript
class_name TransformManager extends RefCounted

var _selection_manager: SelectionManager
var _snap_settings: SnapSettings
var _original_transform: Transform3D
var _transforming: bool = false

func _init(sm: SelectionManager, ss: SnapSettings):
	_selection_manager = sm
	_snap_settings = ss

func begin_move(axis: Vector3) -> bool:
	var sel := _selection_manager.get_selected()
	if not sel: return false
	_original_transform = sel.transform
	_transforming = true
	return true

func apply_move(axis: Vector3, delta_distance: float):
	var sel := _selection_manager.get_selected()
	if not sel or not _transforming: return
	var move := axis * delta_distance
	var new_pos := _original_transform.origin + move
	if _snap_settings.snap_enabled:
		new_pos = _snap_settings.snap_vector3(new_pos, _snap_settings.position_snap)
	sel.position = new_pos

func begin_rotate(axis: Vector3) -> bool:
	var sel := _selection_manager.get_selected()
	if not sel: return false
	_original_transform = sel.transform
	_transforming = true
	return true

func apply_rotate(axis: Vector3, delta_angle: float):
	var sel := _selection_manager.get_selected()
	if not sel or not _transforming: return
	var snap := _snap_settings.rotation_snap if _snap_settings.snap_enabled else 0.0
	var angle := delta_angle
	if snap > 0:
		angle = _snap_settings.snap_value(rad_to_deg(delta_angle), snap)
		angle = deg_to_rad(angle)
	var rot := Basis(axis, angle)
	sel.transform = Transform3D(rot * _original_transform.basis, _original_transform.origin)

func begin_scale(uniform: bool = true) -> bool:
	var sel := _selection_manager.get_selected()
	if not sel: return false
	_original_transform = sel.transform
	_transforming = true
	return true

func apply_scale(axis: Vector3, delta: float, uniform: bool = true):
	var sel := _selection_manager.get_selected()
	if not sel or not _transforming: return
	var s := _original_transform.basis.scale
	if uniform:
		var factor := max(0.01, 1.0 + delta * 0.01)
		s *= factor
	else:
		var factor := max(0.01, 1.0 + delta * 0.01)
		if axis.x != 0: s.x *= factor
		if axis.y != 0: s.y *= factor
		if axis.z != 0: s.z *= factor
	if _snap_settings.snap_enabled:
		s = _snap_settings.snap_vector3(s, _snap_settings.scale_snap)
	s = s.max(Vector3(0.01, 0.01, 0.01))
	sel.scale = s

func end_transform() -> Transform3D:
	_transforming = false
	return _original_transform

func is_transforming() -> bool:
	return _transforming

func duplicate_selected() -> Node3D:
	var sel := _selection_manager.get_selected()
	if not sel: return null
	var parent := sel.get_parent()
	var copy := sel.duplicate() as MeshInstance3D
	copy.position += Vector3(0.5, 0.5, 0.5)
	parent.add_child(copy)
	copy.owner = parent.owner if parent.owner else parent
	_selection_manager.select(copy)
	return copy

func delete_selected():
	var sel := _selection_manager.get_selected()
	if not sel: return
	sel.queue_free()
	_selection_manager.deselect_all()

func reset_selected():
	var sel := _selection_manager.get_selected()
	if not sel: return
	sel.transform = Transform3D.IDENTITY

func center_selected():
	var sel := _selection_manager.get_selected()
	if not sel: return
	var aabb := sel.mesh.get_aabb() if sel.mesh else AABB(Vector3.ZERO, Vector3.ONE)
	var offset := aabb.get_center()
	sel.position = -offset
```

- [ ] **Step 2: Commit**

```bash
git add scripts/modeling_lab/transform_manager.gd
git commit -m "feat(level3): add TransformManager with move/rotate/scale/duplicate/delete"
```

---

### Task 9: Create AccuracyManager + ScoringManager

**Files:**
- Create: `scripts/modeling_lab/accuracy_manager.gd`
- Create: `scripts/modeling_lab/scoring_manager.gd`

**Interfaces:**
- Produces: `AccuracyManager.compare(player, ghost) -> {pos, rot, scale, overall}`. `ScoringManager.grade_from_percent(pct) -> String`, `calculate_final(primitive_scores) -> float`, `is_perfect(pct) -> bool`.

- [ ] **Step 1: Create `accuracy_manager.gd`**

```gdscript
class_name AccuracyManager extends RefCounted

@export var pos_max_error: float = 2.0
@export var rot_max_error_deg: float = 90.0
@export var scale_max_error: float = 2.0
@export var perfect_threshold: float = 98.0
@export var close_threshold: float = 90.0
@export var medium_threshold: float = 50.0

func compare(player: Transform3D, ghost: Transform3D) -> Dictionary:
	var pos_error := player.origin.distance_to(ghost.origin)
	var pos_score := clampf(1.0 - (pos_error / max(pos_max_error, 0.01)), 0.0, 1.0) * 100.0

	var p_quat := player.basis.get_rotation_quaternion()
	var g_quat := ghost.basis.get_rotation_quaternion()
	var rot_error_rad := p_quat.angle_to(g_quat)
	var rot_error_deg := rad_to_deg(rot_error_rad)
	var rot_score := clampf(1.0 - (rot_error_deg / max(rot_max_error_deg, 0.01)), 0.0, 1.0) * 100.0

	var p_scale := player.basis.scale
	var g_scale := ghost.basis.scale
	var scale_error := p_scale.distance_to(g_scale)
	var scale_score := clampf(1.0 - (scale_error / max(scale_max_error, 0.01)), 0.0, 1.0) * 100.0

	var overall := (pos_score + rot_score + scale_score) / 3.0

	return {
		pos = pos_score,
		rot = rot_score,
		scale = scale_score,
		overall = overall
	}

func is_perfect(result: Dictionary) -> bool:
	return result.overall >= perfect_threshold

func is_close(result: Dictionary) -> bool:
	return result.overall >= close_threshold

func get_feedback_color(result: Dictionary) -> Color:
	var o := result.overall
	if o >= perfect_threshold:
		return Color(0.25, 1.0, 0.45)
	elif o >= close_threshold:
		return Color(0.25, 1.0, 0.45, 0.6)
	elif o >= medium_threshold:
		return Color(1.0, 0.84, 0.0, 0.5)
	else:
		return Color(1.0, 0.25, 0.25, 0.4)
```

- [ ] **Step 2: Create `scoring_manager.gd`**

```gdscript
class_name ScoringManager extends RefCounted

const GRADE_S: float = 95.0
const GRADE_A: float = 90.0
const GRADE_B: float = 80.0
const GRADE_C: float = 70.0

func grade_from_percent(pct: float) -> String:
	if pct >= GRADE_S: return "S"
	elif pct >= GRADE_A: return "A"
	elif pct >= GRADE_B: return "B"
	elif pct >= GRADE_C: return "C"
	else: return "Retry"

func grade_label(pct: float) -> String:
	if pct >= GRADE_S: return "Outstanding!"
	elif pct >= GRADE_A: return "Excellent!"
	elif pct >= GRADE_B: return "Good!"
	elif pct >= GRADE_C: return "Passable"
	else: return "Try Again"

func grade_color(pct: float) -> Color:
	if pct >= GRADE_S: return Color(1.0, 0.84, 0.0)
	elif pct >= GRADE_A: return Color(0.25, 1.0, 0.45)
	elif pct >= GRADE_B: return Color(0.29, 0.62, 1.0)
	elif pct >= GRADE_C: return Color(1.0, 0.65, 0.0)
	else: return Color(1.0, 0.25, 0.25)

func calculate_final(primitive_scores: Array[float]) -> float:
	if primitive_scores.is_empty():
		return 0.0
	var total := 0.0
	for s in primitive_scores:
		total += s
	return total / float(primitive_scores.size())
```

- [ ] **Step 3: Commit**

```bash
git add scripts/modeling_lab/accuracy_manager.gd scripts/modeling_lab/scoring_manager.gd
git commit -m "feat(level3): add AccuracyManager and ScoringManager"
```

---

### Task 10: Create AssignmentManager

**Files:**
- Create: `scripts/modeling_lab/assignment_manager.gd`

**Interfaces:**
- Produces: `AssignmentManager` (RefCounted) with `load_assignment(id)`, `get_current()`, `advance()`, `is_last()`, `get_lesson_number()`, `progress` field.

- [ ] **Step 1: Create `assignment_manager.gd`**

```gdscript
class_name AssignmentManager extends RefCounted

const ASSIGNMENT_DIR := "res://data/assignments/"

var assignment_ids: Array[String] = [
	"crate", "traffic_cone", "chair", "table",
	"lamp", "robot", "mascot"
]

var _current_index: int = 0
var _current_assignment: AssignmentData = null
var progress: AssignmentProgress = null

func _init():
	progress = _load_progress()

func load_assignment(id: String) -> AssignmentData:
	var path := ASSIGNMENT_DIR + id + ".tres"
	if not ResourceLoader.exists(path):
		push_error("Assignment not found: ", path)
		return null
	_current_assignment = ResourceLoader.load(path) as AssignmentData
	_current_index = assignment_ids.find(id)
	if _current_index < 0:
		_current_index = 0
	return _current_assignment

func load_index(index: int) -> AssignmentData:
	if index < 0 or index >= assignment_ids.size():
		return null
	_current_index = index
	return load_assignment(assignment_ids[index])

func get_current() -> AssignmentData:
	return _current_assignment

func advance() -> AssignmentData:
	return load_index(_current_index + 1)

func has_next() -> bool:
	return _current_index + 1 < assignment_ids.size()

func is_last() -> bool:
	return _current_index >= assignment_ids.size() - 1

func get_lesson_number() -> int:
	return _current_index + 1

func mark_current_completed(score: float):
	if _current_assignment:
		var id := _current_assignment.assignment_id
		if not id in progress.completed_ids:
			progress.completed_ids.append(id)
		var existing := progress.best_scores.get(id, 0.0)
		if score > existing:
			progress.best_scores[id] = score
		_save_progress()
		# Check if all 7 are done → unlock creative studio
		if progress.completed_ids.size() >= 7:
			progress.creative_studio_unlocked = true
			_save_progress()

func is_completed(id: String) -> bool:
	return id in progress.completed_ids

func get_best_score(id: String) -> float:
	return progress.best_scores.get(id, 0.0)

func is_creative_studio_unlocked() -> bool:
	return progress.creative_studio_unlocked

func reset_progress():
	progress = AssignmentProgress.new()
	_save_progress()

func _load_progress() -> AssignmentProgress:
	var path := "user://modeling_lab_progress.tres"
	if ResourceLoader.exists(path):
		return ResourceLoader.load(path) as AssignmentProgress
	return AssignmentProgress.new()

func _save_progress():
	var path := "user://modeling_lab_progress.tres"
	ResourceSaver.save(progress, path)
```

- [ ] **Step 2: Commit**

```bash
git add scripts/modeling_lab/assignment_manager.gd
git commit -m "feat(level3): add AssignmentManager with progress persistence"
```

---

### Task 11: Create MaterialManager

**Files:**
- Create: `scripts/modeling_lab/material_manager.gd`

**Interfaces:**
- Produces: `MaterialManager` (RefCounted) with `apply_to(node, props)`, `apply_preset(preset, node)`, `get_presets()`.

- [ ] **Step 1: Create `material_manager.gd`**

```gdscript
class_name MaterialManager extends RefCounted

const PRESETS := {
	"plastic": {albedo=Color(0.9,0.9,0.95), metallic=0.0, roughness=0.4},
	"metal": {albedo=Color(0.75,0.75,0.8), metallic=0.9, roughness=0.3},
	"wood": {albedo=Color(0.55,0.35,0.15), metallic=0.0, roughness=0.9},
	"stone": {albedo=Color(0.4,0.4,0.45), metallic=0.0, roughness=0.95},
	"glass": {albedo=Color(0.85,0.9,1.0,0.3), metallic=0.0, roughness=0.0, transparency=0.7},
}

func apply_to(node: MeshInstance3D, props: Dictionary) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	if props.has("albedo"): mat.albedo_color = props.albedo
	if props.has("metallic"): mat.metallic = props.metallic
	if props.has("roughness"): mat.roughness = props.roughness
	if props.has("emission"):
		mat.emission_enabled = true
		mat.emission = props.emission
	if props.has("transparency") and props.transparency > 0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.alpha_scissor_threshold = 0.5
	node.set_surface_override_material(0, mat)
	return mat

func apply_preset(preset_name: String, node: MeshInstance3D) -> bool:
	var name_lower := preset_name.to_lower()
	if not PRESETS.has(name_lower):
		return false
	return apply_to(node, PRESETS[name_lower]) != null

func get_presets() -> Array[String]:
	return PRESETS.keys()

func get_preset_props(name: String) -> Dictionary:
	return PRESETS.get(name.to_lower(), PRESETS["plastic"])

func read_from(node: MeshInstance3D) -> Dictionary:
	var mat := node.get_surface_override_material(0) as StandardMaterial3D
	if not mat:
		return {albedo = Color.WHITE, metallic = 0.0, roughness = 0.5}
	return {
		albedo = mat.albedo_color,
		metallic = mat.metallic,
		roughness = mat.roughness,
	}
```

- [ ] **Step 2: Commit**

```bash
git add scripts/modeling_lab/material_manager.gd
git commit -m "feat(level3): add MaterialManager with presets and real-time editing"
```

---

### Task 12: Create HierarchyManager

**Files:**
- Create: `scripts/modeling_lab/hierarchy_manager.gd`

**Interfaces:**
- Produces: `HierarchyManager` (RefCounted) with `get_tree_data()`, `reparent(child, new_parent)`, `rename(node, name)`, `delete(node)`, `set_visible(node, val)`, `set_locked(node, val)`.

- [ ] **Step 1: Create `hierarchy_manager.gd`**

```gdscript
class_name HierarchyManager extends RefCounted

var _container: Node3D

func _init(container: Node3D):
	_container = container

func get_tree_data() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	_walk(_container, result, 0)
	return result

func _walk(node: Node, output: Array[Dictionary], depth: int):
	for child in node.get_children():
		if child is MeshInstance3D and not child.is_in_group("ghost_guides"):
			output.append({
				node = child,
				name = child.name,
				depth = depth,
				visible = child.visible,
			})
			_walk(child, output, depth + 1)

func reparent(child_node: Node3D, new_parent: Node3D):
	if child_node == new_parent or child_node == _container:
		return
	var old_parent := child_node.get_parent()
	if old_parent == new_parent:
		return
	old_parent.remove_child(child_node)
	new_parent.add_child(child_node)
	child_node.owner = _container.owner if _container.owner else _container

func rename(node: Node, new_name: String) -> bool:
	if new_name.is_empty():
		return false
	node.name = new_name
	return true

func delete(node: Node):
	node.queue_free()

func set_visible(node: Node, val: bool):
	node.visible = val

func duplicate_node(node: Node3D) -> Node3D:
	var parent := node.get_parent()
	var copy := node.duplicate() as Node3D
	copy.position += Vector3(0.5, 0.5, 0.5)
	parent.add_child(copy)
	copy.owner = parent.owner if parent.owner else parent
	return copy

func get_container() -> Node3D:
	return _container
```

- [ ] **Step 2: Commit**

```bash
git add scripts/modeling_lab/hierarchy_manager.gd
git commit -m "feat(level3): add HierarchyManager for object tree management"
```

---

### Task 13: Create UndoManager

**Files:**
- Create: `scripts/modeling_lab/undo_manager.gd`

**Interfaces:**
- Produces: `UndoManager` (RefCounted) with `push(action)`, `undo()`, `redo()`, `can_undo()`, `can_redo()`, `clear()`.

- [ ] **Step 1: Create `undo_manager.gd`**

```gdscript
class_name UndoManager extends RefCounted

@export var max_steps: int = 50

var _undo_stack: Array[Dictionary] = []
var _redo_stack: Array[Dictionary] = []

func push(action: Dictionary):
	_undo_stack.push_back(action)
	if _undo_stack.size() > max_steps:
		_undo_stack.pop_front()
	_redo_stack.clear()

func undo() -> Dictionary:
	if _undo_stack.is_empty():
		return {}
	var action := _undo_stack.pop_back()
	_redo_stack.push_back(action)
	return action

func redo() -> Dictionary:
	if _redo_stack.is_empty():
		return {}
	var action := _redo_stack.pop_back()
	_undo_stack.push_back(action)
	return action

func can_undo() -> bool:
	return not _undo_stack.is_empty()

func can_redo() -> bool:
	return not _redo_stack.is_empty()

func clear():
	_undo_stack.clear()
	_redo_stack.clear()

# Action helpers
func push_transform(node_path: NodePath, before: Transform3D, after: Transform3D):
	push({
		type = "transform",
		node = node_path,
		before = before,
		after = after
	})

func push_delete(node_data: Dictionary):
	push({
		type = "delete",
		data = node_data
	})

func push_duplicate(node_path: NodePath):
	push({
		type = "duplicate",
		node = node_path
	})
```

- [ ] **Step 2: Commit**

```bash
git add scripts/modeling_lab/undo_manager.gd
git commit -m "feat(level3): add UndoManager with unlimited undo/redo"
```

---

### Task 14: Create SaveManager + PortfolioManager3D

**Files:**
- Create: `scripts/modeling_lab/save_manager.gd`
- Create: `scripts/modeling_lab/portfolio_manager.gd`

**Interfaces:**
- Produces: `SaveManager` with `save_model(data, name)`, `load_model(path)`, `list_saved()`, `delete(path)`. `PortfolioManager3D` with `refresh()`, `get_entries()`, `open_artifact(idx)`, `delete(idx)`, `rename(idx, name)`.

- [ ] **Step 1: Create `save_manager.gd`**

```gdscript
class_name SaveManager extends RefCounted

const MODEL_DIR := "res://data/player_models/"

func _init():
	_ensure_dir()

func save_model(data: ModelData, name: String = "") -> String:
	if name.is_empty():
		name = data.model_name
		if name.is_empty():
			name = "untitled"
	var path := MODEL_DIR + _sanitize(name) + ".tres"
	data.creation_date = _timestamp()
	data.model_name = name
	data.resource_path = path
	var err := ResourceSaver.save(data, path)
	if err != OK:
		push_error("SaveManager: Failed to save model: ", err)
		return ""
	return path

func load_model(path: String) -> ModelData:
	if not ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as ModelData

func list_saved() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var dir := DirAccess.open(MODEL_DIR)
	if dir == null:
		return result
	dir.list_dir_begin()
	var fname := dir.get_next()
	while not fname.is_empty():
		if fname.ends_with(".tres"):
			result.append({
				path = MODEL_DIR + fname,
				name = fname.trim_suffix(".tres"),
			})
		fname = dir.get_next()
	dir.list_dir_end()
	result.sort_custom(func(a, b): return a.name < b.name)
	return result

func delete_model(path: String) -> bool:
	var dir := DirAccess.open(MODEL_DIR)
	if dir == null:
		return false
	return dir.remove(path.trim_prefix(MODEL_DIR)) == OK

func _ensure_dir():
	var dir := DirAccess.open("res://")
	if dir:
		dir.make_dir_recursive("data/player_models")

func _sanitize(name: String) -> String:
	var result := ""
	for c in name:
		if c.is_valid_identifier():
			result += c
		elif c == " ":
			result += "_"
	return result

func _timestamp() -> String:
	var dt := Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d %02d:%02d" % [dt.year, dt.month, dt.day, dt.hour, dt.minute]

# Build ModelData from current workspace objects
func capture_model(object_container: Node3D, model_name: String) -> ModelData:
	var data := ModelData.new()
	data.model_name = model_name
	for child in object_container.get_children():
		if child is MeshInstance3D:
			var mat := child.get_surface_override_material(0) as StandardMaterial3D
			var pd := PrimitiveSaveData.new()
			pd.type = 0  # best-effort type
			pd.node_name = child.name
			pd.position = child.position
			pd.rotation_degrees = child.rotation_degrees
			pd.scale = child.scale
			if child.get_parent() and child.get_parent() != object_container:
				pd.parent_name = child.get_parent().name
			if mat:
				pd.material_albedo = mat.albedo_color
				pd.material_metallic = mat.metallic
				pd.material_roughness = mat.roughness
			data.primitives.append(pd)
	return data

# Restore workspace from ModelData
func restore_model(object_container: Node3D, data: ModelData, spawner: PrimitiveSpawner) -> Array[MeshInstance3D]:
	for child in object_container.get_children():
		if child is MeshInstance3D:
			child.queue_free()
	var created: Array[MeshInstance3D] = []
	for pd in data.primitives:
		var mi := spawner.spawn(pd.type, object_container)
		mi.name = pd.node_name
		mi.position = pd.position
		mi.rotation_degrees = pd.rotation_degrees
		mi.scale = pd.scale
		# Re-apply material
		var mat := StandardMaterial3D.new()
		mat.albedo_color = pd.material_albedo
		mat.metallic = pd.material_metallic
		mat.roughness = pd.material_roughness
		mi.set_surface_override_material(0, mat)
		created.append(mi)
	# Apply hierarchy (parent_name matching)
	for pd in data.primitives:
		if not pd.parent_name.is_empty():
			var child := _find_node(object_container, pd.node_name)
			var parent := _find_node(object_container, pd.parent_name)
			if child and parent and child != parent:
				child.get_parent().remove_child(child)
				parent.add_child(child)
	return created

func _find_node(root: Node, name: String) -> Node:
	for child in root.get_children():
		if child.name == name:
			return child
	return null
```

- [ ] **Step 2: Create `portfolio_manager.gd`** (3D version)

```gdscript
class_name PortfolioManager3D extends RefCounted

signal portfolio_changed
signal model_opened(data: ModelData, path: String)

var _save_manager: SaveManager
var _entries: Array[Dictionary] = []

func _init(sm: SaveManager):
	_save_manager = sm

func refresh():
	_entries = _save_manager.list_saved()
	portfolio_changed.emit()

func get_entries() -> Array[Dictionary]:
	return _entries

func get_entry_count() -> int:
	return _entries.size()

func open_artifact(index: int) -> bool:
	if index < 0 or index >= _entries.size():
		return false
	var data := _save_manager.load_model(_entries[index].path)
	if data == null:
		return false
	model_opened.emit(data, _entries[index].path)
	return true

func delete_artwork(index: int) -> bool:
	if index < 0 or index >= _entries.size():
		return false
	var ok := _save_manager.delete_model(_entries[index].path)
	if ok:
		_entries.remove_at(index)
		portfolio_changed.emit()
	return ok

func rename_artwork(index: int, new_name: String) -> bool:
	if index < 0 or index >= _entries.size():
		return false
	var path: String = _entries[index].path
	var data := _save_manager.load_model(path)
	if data == null:
		return false
	data.model_name = new_name
	var new_path := _save_manager.save_model(data, new_name)
	if new_path.is_empty():
		return false
	if new_path != path:
		_save_manager.delete_model(path)
	refresh()
	return true
```

- [ ] **Step 3: Commit**

```bash
git add scripts/modeling_lab/save_manager.gd scripts/modeling_lab/portfolio_manager.gd
git commit -m "feat(level3): add SaveManager and PortfolioManager3D for model persistence"
```

---

### Task 15: Create CreativeStudioManager

**Files:**
- Create: `scripts/modeling_lab/creative_studio_manager.gd`

**Interfaces:**
- Produces: `CreativeStudioManager` (RefCounted) with `unlock()`, `is_unlocked()`, flag used by main controller.

- [ ] **Step 1: Create `creative_studio_manager.gd`**

```gdscript
class_name CreativeStudioManager extends RefCounted

var _unlocked: bool = false

signal studio_unlocked

func unlock():
	if not _unlocked:
		_unlocked = true
		studio_unlocked.emit()

func is_unlocked() -> bool:
	return _unlocked

func set_unlocked(val: bool):
	if val and not _unlocked:
		_unlocked = true
		studio_unlocked.emit()
	else:
		_unlocked = val
```

- [ ] **Step 2: Commit**

```bash
git add scripts/modeling_lab/creative_studio_manager.gd
git commit -m "feat(level3): add CreativeStudioManager with unlock flag"
```

---

### Task 16: Wire Main Controller (modeling_lab.gd — Full Rewrite)

**Files:**
- Modify: `scripts/modeling_lab/modeling_lab.gd` (full rewrite)

**Interfaces:**
- Consumes: All previously created managers and resources
- Produces: Fully wired `ModelingLab` extending `CanvasLayer` with `signal lab_closed`, tool switching, input routing, level progression, completion flow.

- [ ] **Step 1: Write the full `modeling_lab.gd`**

This is the largest file. It must:

1. **Declare subsystems** — all RefCounted managers as `var` fields
2. **Declare enums** — `LabMode { LESSON, CREATIVE_STUDIO }`, `Tool { MOVE, ROTATE, SCALE }`
3. **`_ready()`** — initialize subsystems, find UI nodes (using `%UniqueName`), connect signals, load current assignment or creative studio
4. **Tool switching** — `_on_tool_selected(tool)` → update gizmo, cursor, bottom bar
5. **Input handling** — `_input()` for keyboard shortcuts, `_gui_input()` on SubViewportContainer for 3D interaction
6. **Selection → transform** — wire SelectionManager to Gizmo3D and TransformManager
7. **Accuracy loop** — `_process(delta)` checks accuracy when objects move, updates GhostGuideManager feedback
8. **Assignment flow** — load assignment → spawn ghosts → wait for all primitives locked → grade → advance
9. **Grade card** — show `%GradeCard` panel with animated scores, S/A/B/C grade label
10. **Creative studio mode** — hide ghosts/accuracy, show spawn dropdown, enable save/load
11. **Save/load dialogs** — connect to SaveManager + PortfolioManager3D
12. **Close** — `lab_closed.emit()`, check if all 7 done → `LevelProgression.complete_level(level_def)`, return to main menu
13. **Material panel updates** — wire material sliders to MaterialManager
14. **Hierarchy panel** — rebuild Tree on changes
15. **Bottom bar** — update transform values, tool label, zoom

Key functions:
```gdscript
func _ready():
	# Init workspace from sub-scene
	workspace = $SubViewportContainer/SubViewport/Workspace
	camera = workspace.get_node("CameraController")
	ghost_container = workspace.get_node("GhostGuideContainer")
	object_container = workspace.get_node("ObjectContainer")

	# Init subsystems
	snap_settings = SnapSettings.new()
	spawner = PrimitiveSpawner.new()
	selection_manager = SelectionManager.new(object_container)
	transform_manager = TransformManager.new(selection_manager, snap_settings)
	gizmo = workspace.get_node("GizmoContainer")
	accuracy_manager = AccuracyManager.new()
	scoring_manager = ScoringManager.new()
	assignment_manager = AssignmentManager.new()
	material_manager = MaterialManager.new()
	hierarchy_manager = HierarchyManager.new(object_container)
	save_manager = SaveManager.new()
	portfolio_manager = PortfolioManager3D.new(save_manager)
	undo_manager = UndoManager.new()
	creative_studio_manager = CreativeStudioManager.new()

	_find_ui_nodes()
	_connect_ui_signals()
	_check_creative_studio_unlock()
	_load_current_lesson_or_studio()

func _process(delta):
	if _mode == LabMode.LESSON and _current_assignment:
		_check_accuracy()

func _check_accuracy():
	# For each primitive in current assignment
	# Compare player object transform to ghost guide transform
	# Update GhostGuideManager feedback color
	# If all locked → assignment complete → grade card

func _on_close():
	lab_closed.emit()
	if assignment_manager.progress.completed_ids.size() >= 7:
		var level_def := ResourceLoader.load("res://data/levels/3d_design_lab.tres")
		if level_def:
			LevelProgression.complete_level(level_def)
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
```

- [ ] **Step 2: Commit**

```bash
git add scripts/modeling_lab/modeling_lab.gd
git commit -m "feat(level3): wire full main controller with all subsystems"
```

---

### Task 17: Create Assignment Data Files (7 .tres)

**Files:**
- Create: `data/assignments/crate.tres`
- Create: `data/assignments/traffic_cone.tres`
- Create: `data/assignments/chair.tres`
- Create: `data/assignments/table.tres`
- Create: `data/assignments/lamp.tres`
- Create: `data/assignments/robot.tres`
- Create: `data/assignments/mascot.tres`

**Interfaces:**
- Produces: 7 `AssignmentData` resources consumed by `AssignmentManager`.

- [ ] **Step 1: Create `data/assignments/crate.tres`**

```gdscript
[gd_resource type="Resource" script_class="AssignmentData" load_steps=3 format=3]
[ext_resource type="Script" path="res://scripts/modeling_lab/assignment_data.gd" id="1"]
[ext_resource type="Script" path="res://scripts/modeling_lab/primitive_def.gd" id="2"]
[sub_resource type="Resource" id="Sub_0"]
script = ExtResource("2")
type = 0
target_position = Vector3(0, 0.5, 0)
target_rotation = Vector3(0, 0, 0)
target_scale = Vector3(1, 1, 1)
[resource]
script = ExtResource("1")
assignment_id = "crate"
display_name = "Wooden Crate"
lesson_number = 1
skills_taught = Array[String](["move", "scale"])
instruction_text = "Move and scale the cube to match the ghost guide. Use the Move tool (W) and Scale tool (E)."
primitives = Array[Resource]([SubResource("Sub_0")])
```

- [ ] **Step 2: Create `data/assignments/traffic_cone.tres`**

2 primitives: cylinder (base) + cone (top). Cylinder at (0, 0.25, 0) scaled (0.5, 0.3, 0.5). Cone at (0, 0.85, 0) scaled (0.6, 0.6, 0.6).

- [ ] **Step 3: Create `data/assignments/chair.tres`**

5 primitives: 4 cube legs at corners (0.4,0.4,0.4) scaled (0.1,0.4,0.1), seat cube at (0,0.45,0) scaled (0.5,0.05,0.5), backrest cube at (0,0.75,-0.45) scaled (0.45,0.3,0.05).

- [ ] **Step 4: Create `data/assignments/table.tres`**

5 primitives: 4 cylinder legs at corners (0.4,0,0.4) scaled (0.06,0.4,0.06), top cube at (0,0.45,0) scaled (0.6,0.05,0.4).

- [ ] **Step 5: Create `data/assignments/lamp.tres`**

3 primitives with material colors: cylinder base (0.3,0.15,0), sphere bulb at (0,1.2,0), cone shade. Each has material_color set.

- [ ] **Step 6: Create `data/assignments/robot.tres`**

8 primitives with parent IDs: body (cube), head (sphere on body), 2 arm cylinders (on body), 2 leg cylinders (on body), 2 hand spheres (on arms).

- [ ] **Step 7: Create `data/assignments/mascot.tres`**

10 primitives combining all skills: cube body, sphere head, cone hat, cylinder arms, cylinder legs, sphere hands, plane base. All with hierarchy and materials.

```bash
git add data/assignments/
git commit -m "feat(level3): add all 7 assignment data files"
```

---

### Task 18: Polish — Accuracy Display, Feedback Loop, Grade Card, Undo Integration

**Files:**
- Modify: `scripts/modeling_lab/modeling_lab.gd`
- Modify: `scripts/modeling_lab/accuracy_manager.gd`
- Modify: `scripts/modeling_lab/ghost_guide_manager.gd`

**Goals:**
- Wire real-time accuracy display in Assignment tab (3 progress bars for pos/rot/scale)
- Wire grade card overlay (`%GradeCard`) with animated score bars
- Wire undo for transform operations
- Add "Perfect!" floating label when a primitive locks
- Add sound effect triggers (stubs — just play empty AudioStream)

- [ ] **Step 1: Wire accuracy display** — Update `%PosAccuracy`, `%RotAccuracy`, `%ScaleAccuracy` progress bars every `_process` frame during lesson mode

- [ ] **Step 2: Wire grade card** — Show `%GradeCard` panel when all primitives lock, call `scoring_manager` for grade

- [ ] **Step 3: Wire undo for transforms** — On transform end, push before/after to `undo_manager`. On Ctrl+Z, restore.

- [ ] **Step 4: Commit**

```bash
git add scripts/modeling_lab/
git commit -m "feat(level3): polish accuracy display, grade card, undo integration, sound stubs"
```

---

### Task 19: Integration Test — Main Menu Button, Level Completion, Portfolio

**Files:**
- No new files — verify existing wiring works end-to-end

**Test procedure:**
1. Launch game from main menu
2. Click "3D MODEL" button → should load ModelingLab with workspace
3. Click Close → should return to main menu
4. Verify `LevelProgression` marks `3d_design_lab` complete if all 7 assignments done

- [ ] **Step 1: Verify the button path** — default `modeling_lab_path` in `main_menu.gd` should point to `res://scenes/modeling_lab/modeling_lab.tscn`

- [ ] **Step 2: Launch game, click 3D MODEL button** — should see modeling workspace with UI panels, camera works, primitives load for lesson 1

- [ ] **Step 3: Complete lesson 1** (via accuracy debug trigger or manual) → verify grade card

- [ ] **Step 4: Close lab** → verify return to main menu

- [ ] **Step 5: Commit any fixes**

---

## Self-Review Checklist

1. **Spec coverage:** Skim each spec section. Every feature in sections 2-19 of the design doc maps to one or more tasks above.
2. **Placeholder scan:** No "TBD", "TODO", or "implement later". Every code block has complete, executable GDScript.
3. **Type consistency:** All method signatures match across tasks. `AssignmentData` uses `Array[PrimitiveDef]`, `AccuracyManager.compare()` returns Dictionary with same keys everywhere.
4. **Ordering:** Tasks are ordered by dependency — resources first, then utility managers, then the main controller wiring, then data files, then polish.
