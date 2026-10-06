class_name LightingController
extends Node

## Manages the lights in the 2.5D scene under lighting_root. The GL
## Compatibility renderer keeps a small shadow budget, so the spec's cap is
## enforced here: at most 1 directional + 1 omni light. Adding a second of
## either kind returns "" and creates nothing. Intensity clamps to
## [0.0, MAX_ENERGY]; shadows are off by default and opt-in via set_shadows.
## key_light_exists() and min_intensity() are the measurable lighting
## properties the scoring layer reads.

signal lights_changed

const LIGHT_DIRECTIONAL := 0
const LIGHT_OMNI := 1
const MAX_ENERGY := 5.0

@export_node_path("Node3D") var lighting_root: NodePath

var _lights: Dictionary = {}   # id -> Light3D
var _selected_id := ""
var _dir_count := 0
var _omni_count := 0
var _next_id := 1


func add_light(type: int, position: Vector3) -> String:
	if type != LIGHT_DIRECTIONAL and type != LIGHT_OMNI:
		return ""
	var root_node := _root()
	if root_node == null:
		return ""
	if type == LIGHT_DIRECTIONAL and _dir_count >= 1:
		return ""
	if type == LIGHT_OMNI and _omni_count >= 1:
		return ""
	var light: Light3D = DirectionalLight3D.new() if type == LIGHT_DIRECTIONAL else OmniLight3D.new()
	var id := "light_%d" % _next_id
	_next_id += 1
	light.name = id
	light.light_energy = 1.0
	light.shadow_enabled = false
	light.position = position
	root_node.add_child(light)
	_lights[id] = light
	if type == LIGHT_DIRECTIONAL:
		_dir_count += 1
	else:
		_omni_count += 1
	lights_changed.emit()
	return id


## Adopt a light that already exists in the scene (the lab's starter key/fill
## lights live under LightingRoot from the .tscn, not from add_light). Enforces
## the same per-kind cap as add_light so the spec's 1+1 budget still holds.
func register_existing(id: String, light: Light3D) -> bool:
	if id == "" or light == null or _lights.has(id):
		return false
	if light is DirectionalLight3D:
		if _dir_count >= 1:
			return false
	elif light is OmniLight3D:
		if _omni_count >= 1:
			return false
	else:
		return false
	_lights[id] = light
	if light is DirectionalLight3D:
		_dir_count += 1
	else:
		_omni_count += 1
	lights_changed.emit()
	return true


func remove_light(id: String) -> bool:
	var light := _lights.get(id, null) as Light3D
	if light == null:
		return false
	# Capture class BEFORE free: `is` on a freed instance raises and aborts.
	var was_directional := light is DirectionalLight3D
	_lights.erase(id)
	light.get_parent().remove_child(light)
	light.free()
	if was_directional:
		_dir_count -= 1
	else:
		_omni_count -= 1
	if _selected_id == id:
		_selected_id = ""
	lights_changed.emit()
	return true


func select(id: String) -> void:
	if not _lights.has(id):
		return
	_selected_id = id


func selected() -> String:
	return _selected_id


func set_intensity(id: String, energy: float) -> bool:
	var light := _lights.get(id, null) as Light3D
	if light == null:
		return false
	light.light_energy = clampf(energy, 0.0, MAX_ENERGY)
	lights_changed.emit()
	return true


func set_color(id: String, color: Color) -> bool:
	var light := _lights.get(id, null) as Light3D
	if light == null:
		return false
	light.light_color = color
	lights_changed.emit()
	return true


func set_shadows(id: String, enabled: bool) -> bool:
	var light := _lights.get(id, null) as Light3D
	if light == null:
		return false
	light.shadow_enabled = enabled
	lights_changed.emit()
	return true


func key_light_exists() -> bool:
	for id in _lights:
		var light := _lights[id] as Light3D
		if light is DirectionalLight3D and light.light_energy > 0.0:
			return true
	return false


## Snapshot of every managed light, for SaveController lighting_data (Task 15).
func all_lights() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in _lights:
		var light := _lights[id] as Light3D
		out.append({
			"id": id,
			"kind": LIGHT_DIRECTIONAL if light is DirectionalLight3D else LIGHT_OMNI,
			"energy": light.light_energy,
			"color": light.light_color,
			"shadows": light.shadow_enabled,
		})
	return out


func min_intensity() -> float:
	var min_val := INF
	for id in _lights:
		var light := _lights[id] as Light3D
		if light.light_energy < min_val:
			min_val = light.light_energy
	return 0.0 if min_val == INF else min_val


func light_count() -> int:
	return _lights.size()


func _root() -> Node3D:
	if lighting_root.is_empty():
		return null
	return get_node_or_null(lighting_root) as Node3D