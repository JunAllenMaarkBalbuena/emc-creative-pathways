class_name CameraController
extends Node3D

@export var orbit_speed: float = 0.005
@export var zoom_speed: float = 1.0
@export var pan_speed: float = 0.02
@export var min_distance: float = 0.5
@export var max_distance: float = 50.0
@export var default_distance: float = 8.0
@export var vertical_focus: float = 0.0

var camera: Camera3D
var _pivot: Vector3
var _orbit_rot: Quaternion = Quaternion.from_euler(Vector3(0.4, 0.0, 0.0))
var _distance: float = 8.0
var _panning: bool = false
var _orbiting: bool = false
var _last_mouse: Vector2

func _ready():
	camera = get_child(0) as Camera3D
	if not camera:
		camera = Camera3D.new()
		add_child(camera)
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
		var delta: Vector2 = event.relative
		if _orbiting:
			orbit_by(delta)
		if _panning:
			var right: Vector3 = camera.global_transform.basis.x * delta.x * pan_speed * (_distance / 10.0)
			var up: Vector3 = camera.global_transform.basis.y * delta.y * pan_speed * (_distance / 10.0)
			_pivot += -right + up
			_update_camera()
		return true
	return false

func _update_camera():
	var rot: Basis = Basis(_orbit_rot)
	var pos: Vector3 = _pivot + rot * Vector3(0, 0, _distance)
	camera.global_transform = Transform3D(rot, pos)

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
			var obb: AABB = obj.mesh.get_aabb()
			var world_obb: AABB = obj.global_transform * obb
			aabb = aabb.merge(world_obb) if aabb != AABB() else world_obb
	if aabb == AABB():
		focus_on(Vector3(0, vertical_focus, 0))
		return
	_pivot = aabb.get_center()
	_distance = max(aabb.size.length(), 3.0) * 1.5
	_distance = clamp(_distance, min_distance, max_distance)
	_update_camera()

func orbit_by(delta: Vector2, sensitivity: float = 1.0):
	# Yaw about the world Y (turntable) and pitch about the camera's local
	# right axis. Post-multiplying the pitch keeps it in the camera frame;
	# premultiplying the yaw keeps it level around the world up axis. The
	# quaternion accumulates freely, so elevation is never clamped and the
	# camera can swing over/under the poles without a gimbal flip.
	var yaw := Quaternion(Vector3.UP, -delta.x * orbit_speed * sensitivity)
	var pitch := Quaternion(Vector3.RIGHT, -delta.y * orbit_speed * sensitivity)
	_orbit_rot = (yaw * _orbit_rot * pitch).normalized()
	_update_camera()

func set_view_axis(axis: Vector3):
	var d := axis.normalized()
	_orbit_rot = Quaternion.from_euler(Vector3(-asin(d.y), atan2(d.x, d.z), 0.0))
	_update_camera()

func reset_view():
	_pivot = Vector3(0, vertical_focus, 0)
	_orbit_rot = Quaternion.from_euler(Vector3(0.4, 0.0, 0.0))
	_distance = default_distance
	_update_camera()

func get_pivot() -> Vector3:
	return _pivot

func get_distance() -> float:
	return _distance
