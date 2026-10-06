class_name FrameController
extends Node

## Owns the timeline's frame channel: an ordered list of AnimationFrameData
## (Sprite3D texture swaps at a per-frame duration). The timeline always has
## at least one frame — removing the last remaining frame is refused. Every
## mutation keeps frame_index contiguous (reindex) and emits frames_changed.

signal frames_changed

var frames: Array[AnimationFrameData] = []


func add_frame(texture: Texture2D = null, duration: float = 0.1) -> AnimationFrameData:
	var frame := AnimationFrameData.new()
	frame.texture = texture
	frame.duration = maxf(duration, 0.01)
	frames.append(frame)
	reindex()
	frames_changed.emit()
	return frame


func remove_frame(index: int) -> bool:
	if frames.size() <= 1 or index < 0 or index >= frames.size():
		return false
	frames.remove_at(index)
	reindex()
	frames_changed.emit()
	return true


func duplicate_frame(index: int) -> bool:
	if index < 0 or index >= frames.size():
		return false
	var source := frames[index]
	var copy := AnimationFrameData.new()
	copy.texture = source.texture
	copy.duration = source.duration
	copy.pose_name = source.pose_name
	copy.notes = source.notes
	frames.insert(index + 1, copy)
	reindex()
	frames_changed.emit()
	return true


func insert_frame(index: int, frame: AnimationFrameData) -> bool:
	if frame == null or index < 0 or index > frames.size():
		return false
	frames.insert(index, frame)
	reindex()
	frames_changed.emit()
	return true


func move_frame(from: int, to: int) -> bool:
	if from < 0 or from >= frames.size() or to < 0 or to >= frames.size() or from == to:
		return false
	var frame := frames[from]
	frames.remove_at(from)
	frames.insert(to, frame)
	reindex()
	frames_changed.emit()
	return true


func set_frame_texture(index: int, texture: Texture2D) -> bool:
	if index < 0 or index >= frames.size():
		return false
	frames[index].texture = texture
	frames_changed.emit()
	return true


func set_frame_duration(index: int, duration: float) -> bool:
	if index < 0 or index >= frames.size():
		return false
	frames[index].duration = maxf(duration, 0.01)
	frames_changed.emit()
	return true


func reindex() -> void:
	for i in frames.size():
		frames[i].frame_index = i