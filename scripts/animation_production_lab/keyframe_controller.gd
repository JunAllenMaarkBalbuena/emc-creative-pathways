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

## Optional injectables wired by the root (multi-track timeline round):
## non-null `history` makes every editing op below push an undo/redo entry,
## so editor actions are undoable through the same two-stack history as the
## world; non-null `timeline` clamps every time to [0, timeline.duration],
## otherwise times floor at 0 only. Both default to null, so the existing
## bare-controller tests keep working untouched.
var history: EditorHistory = null
var timeline: TimelineController = null


func add_keyframe(time: float, target_id: String, target_type: int, property_path: String, value: Variant, interpolation: int = LINEAR) -> AnimationKeyframeData:
	var kf := AnimationKeyframeData.new()
	kf.time = time
	kf.target_id = target_id
	kf.target_type = target_type
	kf.property_path = property_path
	kf.value = value
	kf.interpolation = interpolation
	var prev := _snapshot()
	keyframes.append(kf)
	_sort()
	keyframes_changed.emit()
	_push_history(prev, "Add Key")
	return kf


func remove_keyframe(index: int) -> bool:
	if index < 0 or index >= keyframes.size():
		return false
	var prev := _snapshot()
	keyframes.remove_at(index)
	keyframes_changed.emit()
	_push_history(prev, "Delete Key")
	return true


## Re-time the key at flat-list `index`. The new time clamps to
## [0, timeline.duration] (or floors at 0 when no timeline is wired), the
## list re-sorts, and keyframes_changed fires. False only for an invalid
## index.
func move_key(index: int, time: float) -> bool:
	if index < 0 or index >= keyframes.size():
		return false
	var prev := _snapshot()
	keyframes[index].time = _clamp_time(time)
	_sort()
	keyframes_changed.emit()
	_push_history(prev, "Move Key")
	return true


## Remove every key at the given flat-list indices (indices are against the
## PRE-CALL list; removed in descending order so they stay valid). False when
## the list is empty or any index is out of range — a failed call removes
## nothing.
func remove_keys(indices: Array[int]) -> bool:
	if indices.is_empty():
		return false
	for i in indices:
		if i < 0 or i >= keyframes.size():
			return false
	var prev := _snapshot()
	for i in _sorted_unique(indices):
		keyframes.remove_at(i)
	keyframes_changed.emit()
	_push_history(prev, "Delete Keys")
	return true


## Shift every key at the given flat-list indices by `delta`, each time
## clamped to [0, timeline.duration] (indices against the pre-call list; the
## elements stay the same through the re-sort). Keys may pack — no collision
## rejection this round. False when the list is empty or any index is out of
## range.
func slide_keys(indices: Array[int], delta: float) -> bool:
	if indices.is_empty():
		return false
	for i in indices:
		if i < 0 or i >= keyframes.size():
			return false
	var prev := _snapshot()
	for i in _sorted_unique(indices):
		keyframes[i].time = _clamp_time(keyframes[i].time + delta)
	_sort()
	keyframes_changed.emit()
	_push_history(prev, "Slide Keys")
	return true


## Copy every key at the given flat-list indices to `time + offset` (clamped
## to [0, timeline.duration], same target_id/target_type/property_path/value/
## interpolation). offset == 0 duplicates in place (stacked). False when the
## list is empty or any index is out of range.
func duplicate_keys(indices: Array[int], offset: float) -> bool:
	if indices.is_empty():
		return false
	for i in indices:
		if i < 0 or i >= keyframes.size():
			return false
	var prev := _snapshot()
	for i in _sorted_unique(indices):
		var copy := keyframes[i].duplicate() as AnimationKeyframeData
		copy.time = _clamp_time(copy.time + offset)
		keyframes.append(copy)
	_sort()
	keyframes_changed.emit()
	_push_history(prev, "Duplicate Keys")
	return true


## Quiet bulk replace — the loader path. Assigns `keys`, sorts, emits
## keyframes_changed ONCE, and pushes no history, so an undo after a project
## load can never un-add the loaded keys.
func set_all(keys: Array[AnimationKeyframeData]) -> void:
	keyframes.assign(keys)
	_sort()
	keyframes_changed.emit()


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


## Deep-ish snapshot of the whole key list before a mutating op, so history
## undo/redo can restore times AND identity order exactly. Per-element
## duplicate() — a single array-level duplicate() would share key objects,
## letting the op's time mutations corrupt the snapshot.
func _snapshot() -> Array[AnimationKeyframeData]:
	var copy: Array[AnimationKeyframeData] = []
	for kf in keyframes:
		copy.append(kf.duplicate() as AnimationKeyframeData)
	return copy


## Every edit clamps its times: to [0, timeline.duration] when a timeline is
## wired, otherwise to [0, inf] so bare-controller tests need no timeline.
func _clamp_time(time: float) -> float:
	if timeline == null:
		return maxf(time, 0.0)
	return clampf(time, 0.0, timeline.duration)


## Dedupe then sort DESCENDING, so callers can remove at each index without
## earlier removals shifting later ones out of range. Re-timing (slide/duplicate)
## is order-agnostic, so one ordering serves every caller.
func _sorted_unique(indices: Array[int]) -> Array[int]:
	var result: Array[int] = indices.duplicate()
	result.sort()
	result.reverse()
	var i := 0
	while i < result.size() - 1:
		if result[i] == result[i + 1]:
			result.remove_at(i)
		else:
			i += 1
	return result


## Whole-list closure history push, mirroring world_controller.gd. No-op when
## no history is wired (the bare-controller path).
func _push_history(prev: Array[AnimationKeyframeData], label: String) -> void:
	if history == null:
		return
	var next := _snapshot()
	history.push(
		func() -> void:
			keyframes.assign(prev)
			keyframes_changed.emit(),
		func() -> void:
			keyframes.assign(next)
			keyframes_changed.emit(),
		label,
	)