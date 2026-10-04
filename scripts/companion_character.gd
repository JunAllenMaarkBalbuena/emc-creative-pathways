extends TextureRect

enum State { IDLE, MISTAKE, SUCCESS, LOOKING }

const SPRITE_PATH := "res://assets/image/programming_char_reactions/"

var _current_state := State.IDLE
var _idle_timer: Timer
var _revert_timer: Timer
var _look_interval := 6.0

func _ready():
	mouse_filter = MOUSE_FILTER_IGNORE
	stretch_mode = STRETCH_KEEP_ASPECT_CENTERED
	expand_mode = EXPAND_IGNORE_SIZE
	_set_texture("char_Programming")
	_idle_timer = Timer.new()
	_idle_timer.one_shot = false
	_idle_timer.wait_time = _look_interval
	_idle_timer.timeout.connect(_on_idle_timer)
	add_child(_idle_timer)
	_idle_timer.start()
	_revert_timer = Timer.new()
	_revert_timer.one_shot = true
	_revert_timer.timeout.connect(_revert_to_idle)
	add_child(_revert_timer)

func _set_texture(tex_name: String):
	var path := SPRITE_PATH + tex_name + ".png"
	if ResourceLoader.exists(path):
		texture = load(path)

func show_mistake():
	_current_state = State.MISTAKE
	_idle_timer.stop()
	_revert_timer.stop()
	_set_texture("char_Mistake")
	_revert_timer.wait_time = 2.0
	_revert_timer.start()

func show_success():
	_current_state = State.SUCCESS
	_idle_timer.stop()
	_revert_timer.stop()
	_set_texture("char_Success")
	_revert_timer.wait_time = 3.0
	_revert_timer.start()

func show_programming():
	_current_state = State.IDLE
	_set_texture("char_Programming")

func _on_idle_timer():
	if _current_state == State.IDLE:
		_current_state = State.LOOKING
		_set_texture("char_looking_at_you")
		_revert_timer.wait_time = 1.5
		_revert_timer.start()

func _revert_to_idle():
	_current_state = State.IDLE
	_set_texture("char_Programming")
	_idle_timer.start()
