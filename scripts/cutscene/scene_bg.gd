extends TextureRect

@export var zoom_speed: float = 10.0
@export var zoom_amount: float = 0.03

var _tween: Tween

func _ready():
	_center_pivot()
	_start_zoom()
	resized.connect(_center_pivot)

func _center_pivot():
	pivot_offset = size / 2

func _start_zoom():
	if _tween:
		_tween.kill()
	var half_cycle := zoom_speed / 2.0
	_tween = create_tween().set_loops()
	_tween.tween_property(self, "scale", _base_scale() * (1.0 + zoom_amount), half_cycle).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_tween.tween_property(self, "scale", _base_scale(), half_cycle).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

func _base_scale() -> Vector2:
	return Vector2(1.0, 1.0)

func _exit_tree():
	if _tween:
		_tween.kill()
