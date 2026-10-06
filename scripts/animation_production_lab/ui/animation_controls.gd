extends Control

## Animation controls (FRAMES..PREVIEW): play/rewind, fps and duration.

signal play_toggled
signal rewind_requested
signal fps_changed(fps: int)
signal duration_changed(duration: float)

@onready var fps_spin: SpinBox = %FpsSpin
@onready var duration_spin: SpinBox = %DurSpin

func set_fps(fps: int) -> void:
	fps_spin.set_value_no_signal(float(fps))

func set_duration(duration: float) -> void:
	duration_spin.set_value_no_signal(duration)

func _on_play_pressed() -> void:
	play_toggled.emit()

func _on_rewind_pressed() -> void:
	rewind_requested.emit()

func _on_fps_changed(value: float) -> void:
	fps_changed.emit(int(value))

func _on_duration_changed(value: float) -> void:
	duration_changed.emit(value)