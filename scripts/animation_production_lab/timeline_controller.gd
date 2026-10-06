class_name TimelineController
extends Node

## The single master clock for a shot. step_time() is a PURE clock: it must
## never depend on engine frames, so the same delta sequence always produces
## the same current_time. The frame channel lives on FrameController;
## frame_index_at() maps clock time to that channel's frames at fps
## boundaries, clamped to the last frame. RF3: set_fps rejects anything
## outside [min_fps, max_fps]; set_duration rejects negatives and anything
## above max_duration, and clamps exactly 0.0 to 0.01 so a zero-length
## timeline never stalls.

signal playback_started
signal playback_stopped
signal time_changed(time: float)

var fps: int = 12
var duration: float = 5.0
var loop: bool = false
var current_time: float = 0.0

var min_fps := 1
var max_fps := 60
var max_duration := 30.0

@export_node_path("Node") var frame_controller_path: NodePath
var frame_controller_ref: FrameController

var _playing := false


func _ready() -> void:
	if not frame_controller_path.is_empty():
		frame_controller_ref = get_node_or_null(frame_controller_path) as FrameController


func set_fps(value: int) -> bool:
	if value < min_fps or value > max_fps:
		return false
	fps = value
	return true


func set_duration(value: float) -> bool:
	if value < 0.0 or value > max_duration:
		return false
	duration = 0.01 if value == 0.0 else value
	return true


func play() -> void:
	_playing = true
	playback_started.emit()


func pause() -> void:
	_playing = false


func stop() -> void:
	_playing = false
	current_time = 0.0


func is_playing() -> bool:
	return _playing


## Pure clock advance. While playing, adds delta, clamps at duration, stops
## (playback_stopped) unless looping (wrap), then reports time_changed.
func step_time(delta: float) -> void:
	if not _playing:
		return
	current_time += delta
	if current_time >= duration:
		if loop:
			current_time = fmod(current_time, duration)
		else:
			current_time = duration
			_playing = false
			playback_stopped.emit()
	time_changed.emit(current_time)


## Manual scrub (Task 17 hotkeys): moves the clock whether or not playback is
## running, clamped to [0, duration]. Like step_time it is a pure function of
## the delta — no engine-frame dependence. Emits time_changed for the cursor.
func scrub(delta: float) -> void:
	current_time = clampf(current_time + delta, 0.0, duration)
	time_changed.emit(current_time)


## Frame index showing at `time` on the frame channel (fps boundaries),
## clamped to the last frame.
func frame_index_at(time: float) -> int:
	var count := _frame_count()
	if count <= 0:
		return 0
	return mini(floori(fps * time), count - 1)


func current_frame_index() -> int:
	return frame_index_at(current_time)


## 0..1 progress within the current frame's boundary.
func current_frame_progress() -> float:
	return fmod(fps * current_time, 1.0)


func _frame_count() -> int:
	if frame_controller_ref != null:
		return frame_controller_ref.frames.size()
	return 1