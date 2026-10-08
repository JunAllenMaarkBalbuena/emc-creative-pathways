extends Control

## Timeline panel (FRAMES/KEYFRAME/TIMING): the multi-track timeline editor +
## toolbar (snap/zoom/delete) above the existing frame-list controls. The panel
## forwards the editor's eight signals upward under the same names (house
## convention: the panel is the docker boundary).

signal frame_selected(index: int)
signal frame_added
signal frame_removed(index: int)
signal frame_texture_requested(index: int)

signal lane_pressed(lane_id: String, lane_kind: int)
signal playhead_requested(time: float)
signal key_add_requested(lane_id: String, lane_kind: int, time: float)
signal key_move_requested(index: int, from_time: float, to_time: float)
signal keys_remove_requested(indices: Array[int])
signal span_slide_requested(indices: Array[int], delta: float)
signal span_duplicate_requested(indices: Array[int], offset: float)
signal snap_toggled(on: bool)

const TimelineEditorScript := preload("res://scripts/animation_production_lab/ui/timeline_editor.gd")

var editor: Control

var _count := 0
var _selected := -1

@onready var frame_list: VBoxContainer = %FrameList
@onready var remove_button: Button = %RemoveFrame
@onready var use_button: Button = %UseAsset
@onready var snap_toggle: CheckButton = %SnapToggle
@onready var zoom_in_button: Button = %ZoomIn
@onready var zoom_out_button: Button = %ZoomOut
@onready var delete_button: Button = %DeleteSelection

func _ready() -> void:
	editor = %TimelineEditor
	var ed := editor as TimelineEditorScript
	if ed == null:
		return
	ed.lane_pressed.connect(func(id: String, kind: int) -> void: lane_pressed.emit(id, kind))
	ed.playhead_requested.connect(func(t: float) -> void: playhead_requested.emit(t))
	ed.key_add_requested.connect(func(id: String, kind: int, t: float) -> void: key_add_requested.emit(id, kind, t))
	ed.key_move_requested.connect(func(idx: int, f: float, t: float) -> void: key_move_requested.emit(idx, f, t))
	ed.keys_remove_requested.connect(func(idxs: Array[int]) -> void: keys_remove_requested.emit(idxs))
	ed.span_slide_requested.connect(func(idxs: Array[int], d: float) -> void: span_slide_requested.emit(idxs, d))
	ed.span_duplicate_requested.connect(func(idxs: Array[int], o: float) -> void: span_duplicate_requested.emit(idxs, o))
	ed.snap_toggled.connect(func(on: bool) -> void: snap_toggled.emit(on))
	snap_toggle.toggled.connect(_on_snap_toggled)
	zoom_in_button.pressed.connect(_on_zoom_in)
	zoom_out_button.pressed.connect(_on_zoom_out)
	delete_button.pressed.connect(_on_delete_selection)

## Forwards the sources to the editor (short-hand for the editor's set_sources).
func bind(world, keyframes, frames, timeline, lighting) -> void:
	var ed := editor as TimelineEditorScript
	if ed != null:
		ed.set_sources(world, keyframes, frames, timeline, lighting)

func _on_snap_toggled(on: bool) -> void:
	var ed := editor as TimelineEditorScript
	if ed != null:
		ed.set_snap(on)

func _on_zoom_in() -> void:
	var ed := editor as TimelineEditorScript
	if ed != null:
		ed.zoom_in()

func _on_zoom_out() -> void:
	var ed := editor as TimelineEditorScript
	if ed != null:
		ed.zoom_out()

func _on_delete_selection() -> void:
	var ed := editor as TimelineEditorScript
	if ed != null:
		ed.delete_selection()

func set_frame_count(count: int) -> void:
	_count = count
	if _selected >= _count:
		_selected = _count - 1
	_rebuild()

func _rebuild() -> void:
	for child in frame_list.get_children():
		child.queue_free()
	for i in _count:
		var b := Button.new()
		b.text = "Frame %d" % (i + 1)
		b.custom_minimum_size = Vector2(0, 44)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_on_frame_pressed.bind(i))
		frame_list.add_child(b)
	remove_button.disabled = _selected < 0
	use_button.disabled = _selected < 0

func _on_frame_pressed(index: int) -> void:
	_selected = index
	frame_selected.emit(index)
	_rebuild()

func _on_add_pressed() -> void:
	frame_added.emit()

func _on_remove_pressed() -> void:
	if _selected >= 0:
		frame_removed.emit(_selected)
		_selected = -1

func _on_use_asset_pressed() -> void:
	if _selected >= 0:
		frame_texture_requested.emit(_selected)