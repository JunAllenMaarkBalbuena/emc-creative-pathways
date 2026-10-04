class_name GhostGuideManager
extends RefCounted

@export var ghost_opacity: float = 0.2
@export var ghost_color: Color = Color(0.29, 0.62, 1.0)

var _container: Node3D
var _ghosts: Array[MeshInstance3D] = []

func _init(container: Node3D):
	_container = container

func spawn_for_assignment(data: AssignmentData, spawner: PrimitiveSpawner) -> Array[MeshInstance3D]:
	clear()
	for def in data.primitives:
		var ghost := spawner.spawn(def.type, _container, false)
		ghost.position = def.target_position
		ghost.rotation_degrees = def.target_rotation
		ghost.scale = def.target_scale
		ghost.name = "Ghost_" + PrimitiveDef.Type.keys()[def.type]
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
	var overall: float = accuracy.get("overall", 0.0)
	var color: Color
	var alpha: float = ghost_opacity
	if overall >= 98.0:
		color = Color(0.25, 1.0, 0.45)
		alpha = 0.01
	elif overall >= 90.0:
		color = Color(0.25, 1.0, 0.45)
	elif overall >= 50.0:
		color = Color(1.0, 0.84, 0.0)
	else:
		color = Color(1.0, 0.25, 0.25)
	var mat: StandardMaterial3D = ghost.get_surface_override_material(0) as StandardMaterial3D
	if mat:
		mat.albedo_color = Color(color.r, color.g, color.b, alpha)
		mat.emission = color * 0.5

func is_locked(index: int) -> bool:
	if index < 0 or index >= _ghosts.size():
		return true
	var mat := _ghosts[index].get_surface_override_material(0) as StandardMaterial3D
	return mat != null and mat.albedo_color.a < 0.05

func clear():
	for g in _ghosts:
		if is_instance_valid(g):
			g.queue_free()
	_ghosts.clear()

func get_ghost(index: int) -> MeshInstance3D:
	if index < 0 or index >= _ghosts.size():
		return null
	return _ghosts[index]

func get_ghost_count() -> int:
	return _ghosts.size()
