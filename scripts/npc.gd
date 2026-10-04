@tool
class_name NPC
extends DialogueInteractable

@export var portrait: Texture2D:
	set(value):
		portrait = value
		if is_inside_tree():
			_update_avatar()

@export_category("Sprite")
@export var sprite_scale := Vector3(1, 1, 1):
	set(value):
		if value == null:
			return
		sprite_scale = Vector3(maxf(value.x, 0.01), maxf(value.y, 0.01), maxf(value.z, 0.01))
		_apply_sprite_scale()

@export var lock_sprite_ratio := true

@export_range(0.01, 10.0, 0.01) var uniform_scale := 1.0:
	set(value):
		if value == null:
			return
		uniform_scale = maxf(value, 0.01)
		if lock_sprite_ratio:
			sprite_scale = Vector3(uniform_scale, uniform_scale, uniform_scale)
		_apply_sprite_scale()

@export_category("Collider")
@export var collider_position := Vector3(0, 1, 0):
	set(value):
		if value == null:
			return
		collider_position = value
		_apply_collider()

@export var collider_radius := 0.6:
	set(value):
		if value == null:
			return
		collider_radius = maxf(value, 0.01)
		_apply_collider()

@export var collider_height := 1.5:
	set(value):
		if value == null:
			return
		collider_height = maxf(value, 0.01)
		_apply_collider()

@export_category("Blocker")
@export var block_player := false:
	set(value):
		block_player = value
		_apply_blocker()

@export var blocker_position := Vector3(0, 1, 0):
	set(value):
		if value == null:
			return
		blocker_position = value
		_apply_blocker()

@export var blocker_radius := 0.6:
	set(value):
		if value == null:
			return
		blocker_radius = maxf(value, 0.01)
		_apply_blocker()

@export var blocker_height := 1.5:
	set(value):
		if value == null:
			return
		blocker_height = maxf(value, 0.01)
		_apply_blocker()

func _ready() -> void:
	_update_avatar()
	_apply_sprite_scale()
	_apply_collider()
	_apply_blocker()

func _update_avatar() -> void:
	var avatar: AnimatedSprite3D = get_node_or_null("Avatar")
	if avatar == null or portrait == null:
		return
	var frames := SpriteFrames.new()
	if not frames.has_animation(&"idle"):
		frames.add_animation(&"idle")
	frames.add_frame(&"idle", portrait)
	avatar.sprite_frames = frames
	avatar.play(&"idle")

func _apply_sprite_scale() -> void:
	var avatar: AnimatedSprite3D = get_node_or_null("Avatar")
	if avatar:
		avatar.scale = sprite_scale

func _apply_collider() -> void:
	var col: CollisionShape3D = get_node_or_null("InteractionBounds")
	if col:
		col.position = collider_position
		if not col.shape is CapsuleShape3D:
			col.shape = CapsuleShape3D.new()
		(col.shape as CapsuleShape3D).radius = collider_radius
		(col.shape as CapsuleShape3D).height = collider_height

func _apply_blocker() -> void:
	var blocker: StaticBody3D = get_node_or_null("Blocker")
	if blocker:
		var col: CollisionShape3D = blocker.get_node_or_null("CollisionShape3D")
		if col:
			col.disabled = not block_player
			col.position = blocker_position
			if not col.shape is CapsuleShape3D:
				col.shape = CapsuleShape3D.new()
			(col.shape as CapsuleShape3D).radius = blocker_radius
			(col.shape as CapsuleShape3D).height = blocker_height
