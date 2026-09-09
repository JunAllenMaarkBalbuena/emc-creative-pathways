class_name PlayerController
extends CharacterBody3D

@export_category("Movement")
@export_range(0.1, 20.0, 0.1, "suffix:m/s") var movement_speed := 4.5
@export_range(0.1, 30.0, 0.1, "suffix:m/s") var sprint_speed := 7.0
@export_range(0.1, 50.0, 0.1) var acceleration := 20.0
@export_range(0.1, 50.0, 0.1) var deceleration := 28.0
@export_range(0.1, 20.0, 0.1) var rotation_speed := 12.0

@export_category("Optional Jump")
@export var jump_enabled := false
@export_range(0.1, 10.0, 0.1, "suffix:m") var jump_height := 1.25
@export_range(0.1, 40.0, 0.1, "suffix:m/s²") var gravity := 24.0

@export_category("Character Skins")
@export var skins: Array[CharacterSkin] = []

@onready var avatar: AnimatedSprite3D = $Avatar
@onready var interaction_area: Area3D = $InteractionArea

signal interaction_target_changed(target: Interactable)
signal interaction_triggered(target: Interactable)
signal interaction_performed(message: String)
signal skin_changed(skin_name: String)

var _facing := "down"
var _was_moving := false
var _virtual_move := Vector2.ZERO
var _current_interactable: Interactable
var _nearby_interactables: Array = []
var _current_skin: CharacterSkin
var _skin_index := 0

func _ready() -> void:
	_ensure_input_actions()
	interaction_area.monitoring = true
	interaction_area.area_entered.connect(_on_interaction_area_entered)
	interaction_area.area_exited.connect(_on_interaction_area_exited)
	var progression := get_node_or_null("/root/LevelProgression")
	if progression != null:
		var start_index: int = progression.get_skin_index(0)
		_apply_skin(start_index)
		# Restore spawn position if returning via Continue
		var scene_path := get_tree().current_scene.scene_file_path
		var spawn = progression.get_spawn_position(scene_path)
		push_warning("PLAYER _ready: scene=%s spawn=%s" % [scene_path, spawn])
		if spawn != null and spawn.has("player"):
			var pos: Vector3 = spawn["player"]
			var cam_offset: Vector3 = spawn.get("camera_offset", Vector3.ZERO)
			progression.clear_spawn_position(scene_path)
			push_warning("PLAYER _ready: restoring position to %s cam_offset=%s" % [pos, cam_offset])
			call_deferred("_apply_spawn_position", pos, cam_offset)
	else:
		_apply_skin(0)
	_update_animation(false)

func _apply_spawn_position(pos: Vector3, cam_offset: Vector3 = Vector3.ZERO) -> void:
	global_position = pos
	if cam_offset != Vector3.ZERO:
		var cam = get_tree().current_scene.get_node_or_null("PlayerFollowCamera")
		if cam is PlayerFollowCamera:
			cam._scene_offset = cam_offset
			cam.global_position = pos + cam_offset

func _ensure_input_actions() -> void:
	_add_key_action("move_left", [KEY_A, KEY_LEFT])
	_add_key_action("move_right", [KEY_D, KEY_RIGHT])
	_add_key_action("move_forward", [KEY_W, KEY_UP])
	_add_key_action("move_back", [KEY_S, KEY_DOWN])
	_add_key_action("sprint", [KEY_SHIFT])
	_add_key_action("interact", [KEY_E])
	_add_key_action("switch_character", [KEY_TAB])
	_add_joy_axis("move_left", JOY_AXIS_LEFT_X, -1.0)
	_add_joy_axis("move_right", JOY_AXIS_LEFT_X, 1.0)
	_add_joy_axis("move_forward", JOY_AXIS_LEFT_Y, -1.0)
	_add_joy_axis("move_back", JOY_AXIS_LEFT_Y, 1.0)
	_add_joy_button("sprint", JOY_BUTTON_LEFT_STICK)
	_add_joy_button("interact", JOY_BUTTON_A)

func _add_key_action(action: StringName, keycodes: Array[Key]) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for keycode in keycodes:
		var event := InputEventKey.new()
		event.physical_keycode = keycode
		InputMap.action_add_event(action, event)

func _add_joy_axis(action: StringName, axis: JoyAxis, value: float) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	InputMap.action_add_event(action, event)

func _add_joy_button(action: StringName, button: JoyButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var event := InputEventJoypadButton.new()
	event.button_index = button
	InputMap.action_add_event(action, event)

func _physics_process(delta: float) -> void:
	var input_2d := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if _virtual_move.length() > input_2d.length():
		input_2d = _virtual_move
	var move_direction := Vector3(input_2d.x, 0.0, input_2d.y)
	var target_speed := sprint_speed if Input.is_action_pressed("sprint") else movement_speed
	var target_velocity := move_direction * target_speed
	var rate := acceleration if not move_direction.is_zero_approx() else deceleration
	velocity.x = move_toward(velocity.x, target_velocity.x, rate * delta)
	velocity.z = move_toward(velocity.z, target_velocity.z, rate * delta)

	if not is_on_floor():
		velocity.y -= gravity * delta
	elif jump_enabled and Input.is_action_just_pressed("ui_accept"):
		velocity.y = sqrt(2.0 * gravity * jump_height)
	else:
		velocity.y = -0.1

	if not move_direction.is_zero_approx():
		rotation.y = lerp_angle(rotation.y, atan2(move_direction.x, move_direction.z), rotation_speed * delta)
		_facing = _direction_name(move_direction)

	move_and_slide()
	_update_animation(not move_direction.is_zero_approx())
	if Input.is_action_just_pressed("switch_character"):
		_cycle_skin()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		try_interact()

func _direction_name(direction: Vector3) -> String:
	var has_diagonals := _current_skin != null and _current_skin.has_diagonals
	if not has_diagonals:
		if abs(direction.x) > abs(direction.z):
			return "right" if direction.x > 0.0 else "left"
		return "down" if direction.z > 0.0 else "up"
	var vertical := "down" if direction.z >= 0.0 else "up"
	var horizontal := ""
	if direction.x > 0.0:
		horizontal = "right"
	elif direction.x < 0.0:
		horizontal = "left"
	if horizontal.is_empty():
		return vertical
	return vertical + "_" + horizontal

func _update_animation(is_moving: bool) -> void:
	if _current_skin == null:
		return
	var animation := ""
	if is_moving:
		animation = _current_skin.get_walk_animation(_facing)
	else:
		animation = _current_skin.get_idle_animation(_facing)
	avatar.speed_scale = 1.0
	if animation.is_empty() or not avatar.sprite_frames.has_animation(animation):
		return
	if avatar.animation != animation:
		avatar.play(animation)
	_was_moving = is_moving

func _apply_skin(index: int) -> void:
	if skins.is_empty():
		return
	_skin_index = posmod(index, skins.size())
	_current_skin = skins[_skin_index]
	if _current_skin == null:
		return
	avatar.sprite_frames = _current_skin.sprite_frames
	avatar.scale = _current_skin.avatar_scale
	avatar.position = _current_skin.avatar_offset
	avatar.speed_scale = 1.0
	_update_animation(false)
	skin_changed.emit(_current_skin.skin_name)

func _cycle_skin() -> void:
	if skins.size() <= 1:
		return
	_apply_skin(_skin_index + 1)
	var progression := get_node_or_null("/root/LevelProgression")
	if progression != null:
		progression.save_skin_index(_skin_index)

func get_skin_name() -> String:
	return _current_skin.skin_name if _current_skin != null else ""

func get_skin_index() -> int:
	return _skin_index

func get_interaction_area() -> Area3D:
	return interaction_area

func set_virtual_move(value: Vector2) -> void:
	_virtual_move = value.limit_length()

func try_interact() -> void:
	if _current_interactable == null:
		return
	interaction_triggered.emit(_current_interactable)
	interaction_performed.emit(_current_interactable.interact(self))
	if not is_instance_valid(_current_interactable) or not _current_interactable.monitoring:
		_current_interactable = null
		interaction_target_changed.emit(null)

func _on_interaction_area_entered(area: Area3D) -> void:
	if area is Interactable:
		_nearby_interactables.append(area)
		_update_closest_target()

func _on_interaction_area_exited(area: Area3D) -> void:
	_nearby_interactables.erase(area)
	_update_closest_target()

func _update_closest_target() -> void:
	var closest: Interactable = null
	var closest_dist := INF
	for inter in _nearby_interactables:
		if not is_instance_valid(inter) or not inter.monitoring:
			continue
		var dist = global_position.distance_to(inter.global_position)
		if dist < closest_dist:
			closest_dist = dist
			closest = inter
	if closest != _current_interactable:
		_current_interactable = closest
		interaction_target_changed.emit(_current_interactable)
