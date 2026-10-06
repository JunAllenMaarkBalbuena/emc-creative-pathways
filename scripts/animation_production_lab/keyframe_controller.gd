class_name KeyframeController
extends Node

## Global keyframe list, kept sorted by time. Tracks are grouped per
## (target_id, property_path); evaluate() is RF4-safe: an unknown target or a
## property with no track returns null instead of erroring, so a keyframe
## whose target was deleted from the world is harmless during playback.

signal keyframes_changed

const TARGET_OBJECT := 0
const TARGET_CAMERA := 1
const TARGET_LIGHT := 2
const LINEAR := 0
const STEP := 1

var keyframes: Array[AnimationKeyframeData] = []


func add_keyframe(time: float, target_id: String, target_type: int, property_path: String, value: Variant, interpolation: int = LINEAR) -> AnimationKeyframeData:
	var kf := AnimationKeyframeData.new()
	kf.time = time
	kf.target_id = target_id
	kf.target_type = target_type
	kf.property_path = property_path
	kf.value = value
	kf.interpolation = interpolation
	keyframes.append(kf)
	_sort()
	keyframes_changed.emit()
	return kf


func remove_keyframe(index: int) -> bool:
	if index < 0 or index >= keyframes.size():
		return false
	keyframes.remove_at(index)
	keyframes_changed.emit()
	return true


## All keys for a target across every property, sorted by time.
func keyframes_for(target_id: String) -> Array[AnimationKeyframeData]:
	var result: Array[AnimationKeyframeData] = []
	for kf in keyframes:
		if kf.target_id == target_id:
			result.append(kf)
	return result


func keyframe_times(target_id: String) -> Array[float]:
	var times: Array[float] = []
	for kf in keyframes:
		if kf.target_id == target_id:
			times.append(kf.time)
	return times


## Value of the (target_id, property_path) track at `time`. null when the
## track does not exist. Before the first key -> first value; after the last
## -> last value. Between keys: LINEAR lerps Vector3/float/Color by `t`;
## STEP holds the value of the key just before `time`.
func evaluate(target_id: String, property_path: String, time: float) -> Variant:
	var track := _track_for(target_id, property_path)
	if track.is_empty():
		return null
	if time <= track[0].time:
		return track[0].value
	var last := track[track.size() - 1]
	if time >= last.time:
		return last.value
	for i in track.size() - 1:
		var a := track[i]
		var b := track[i + 1]
		if time >= a.time and time <= b.time:
			if a.interpolation == STEP:
				return a.value
			var t := 0.0
			var span := b.time - a.time
			if span > 0.0:
				t = (time - a.time) / span
			return _lerp_value(a.value, b.value, t)
	return last.value


func _track_for(target_id: String, property_path: String) -> Array[AnimationKeyframeData]:
	var result: Array[AnimationKeyframeData] = []
	for kf in keyframes:
		if kf.target_id == target_id and kf.property_path == property_path:
			result.append(kf)
	return result


func _lerp_value(from: Variant, to: Variant, t: float) -> Variant:
	if from is Vector3 and to is Vector3:
		return (from as Vector3).lerp(to as Vector3, t)
	if from is Color and to is Color:
		return (from as Color).lerp(to as Color, t)
	if from is float and to is float:
		return lerpf(from, to, t)
	if from is int and to is int:
		return lerpf(float(from), float(to), t)
	return to


func _sort() -> void:
	keyframes.sort_custom(_before)


func _before(a: AnimationKeyframeData, b: AnimationKeyframeData) -> bool:
	return a.time < b.time