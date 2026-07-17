class_name PlayerController
extends CharacterBody3D

## Inspector-facing 2.5D character controller. It accepts keyboard and gamepad
## input through named actions, keeping future mobile controls independent.
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

@onready var avatar: AnimatedSprite3D = $Avatar
@onready var interaction_area: Area3D = $InteractionArea

var _facing := "down"
var _was_moving := false
var _virtual_move := Vector2.ZERO
var _current_interactable: Interactable

signal interaction_target_changed(target: Interactable)
signal interaction_triggered(target: Interactable)
signal interaction_performed(message: String)

func _ready() -> void:
	_ensure_input_actions()
	interaction_area.monitoring = true
	interaction_area.area_entered.connect(_on_interaction_area_entered)
	interaction_area.area_exited.connect(_on_interaction_area_exited)
	_update_animation(false)

## Defines default keyboard/gamepad bindings once. If designers later create
## these actions in Project Settings, their bindings remain untouched.
func _ensure_input_actions() -> void:
	_add_key_action("move_left", [KEY_A, KEY_LEFT])
	_add_key_action("move_right", [KEY_D, KEY_RIGHT])
	_add_key_action("move_forward", [KEY_W, KEY_UP])
	_add_key_action("move_back", [KEY_S, KEY_DOWN])
	_add_key_action("sprint", [KEY_SHIFT])
	_add_key_action("interact", [KEY_E])
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
	if Input.is_action_just_pressed("interact"):
		try_interact()

func _direction_name(direction: Vector3) -> String:
	if abs(direction.x) > abs(direction.z):
		return "right" if direction.x > 0.0 else "left"
	return "down" if direction.z > 0.0 else "up"

func _update_animation(is_moving: bool) -> void:
	var animation := ("walk_" if is_moving else "idle_") + _facing
	if avatar.animation != animation:
		avatar.play(animation)
	_was_moving = is_moving

func get_interaction_area() -> Area3D:
	return interaction_area

func set_virtual_move(value: Vector2) -> void:
	_virtual_move = value.limit_length()

func try_interact() -> void:
	if _current_interactable == null:
		return
	interaction_triggered.emit(_current_interactable)
	interaction_performed.emit(_current_interactable.interact(self))

func _on_interaction_area_entered(area: Area3D) -> void:
	if area is Interactable:
		_current_interactable = area
		interaction_target_changed.emit(_current_interactable)

func _on_interaction_area_exited(area: Area3D) -> void:
	if area == _current_interactable:
		_current_interactable = null
		interaction_target_changed.emit(null)
