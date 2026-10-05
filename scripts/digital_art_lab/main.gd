class_name DigitalArtLab
extends CanvasLayer

## Main controller for the Digital Art Laboratory (Level 2).
## Wires all subsystems together and handles UI interactions.

signal lab_closed

@export_file("*.tscn") var fallback_scene := "res://scenes/main_menu.tscn"

# ── Subsystems ───────────────────────────────────────────────
var painter := Painter.new()
var layer_manager := LayerManager.new()
var history_manager := HistoryManager.new()
var color_manager := ColorManager.new()
var file_manager := FileManager.new()
var portfolio_manager: PortfolioManager

# ── Tool state ───────────────────────────────────────────────
enum Tool { BRUSH, ERASER, FILL, EYEDROPPER, PAN, ZOOM }
var current_tool := Tool.BRUSH

# Brush settings
var brush_size := 20
var brush_opacity := 1.0
var brush_hardness := 0.8
var brush_spacing := 0.3  # fraction of brush diameter between dabs

# Stroke tracking
var _stroking := false
var _composite_dirty := false  # debounce: rebuild once per frame via _process
var _last_stroke_pos := Vector2.ZERO
var _stroke_sample_dist := 0.0

# UI references (set in _ready via @onready)
var canvas_view: CanvasView
var canvas_container: Control
var _layer_entries_container: VBoxContainer
var tool_buttons: Dictionary[int, Button] = {}
var color_wheel: ColorPickerControl
var size_slider: HSlider
var opacity_slider: HSlider
var hardness_slider: HSlider
var primary_color_rect: ColorRect
var secondary_color_rect: ColorRect
var recent_colors_container: Container
var favorite_colors_container: Container
var zoom_slider: VSlider
var zoom_label: Label
var file_status_label: Label
var coord_label: Label
var tool_label: Label
var layer_label: Label
var artwork_name_label: Label
var save_button: Button
var load_button: Button
var export_button: Button
var new_button: Button
var close_button: Button
var undo_button: Button
var redo_button: Button
var grid_toggle: Button
var completion_panel: Panel
var save_dialog: Panel
var load_dialog: Panel
var portfolio_browser: ItemList
var hint_button: Button

# Current artwork data for saving
var _current_data: DigitalArtData
var _current_file_path := ""

# Canvas size
var _canvas_w := 512
var _canvas_h := 512
var _artwork_name := "Untitled"

# Level state
var _has_saved_at_least_once := false


func _ready():
	# Initialise subsystems
	portfolio_manager = PortfolioManager.new(file_manager)

	# Find UI nodes
	_find_ui_nodes()
	_setup_canvas()
	_connect_ui_signals()
	_setup_default_layers()
	_update_tool_ui()
	_update_color_ui()
	_update_layer_ui()
	_update_brush_ui()
	_update_title()

	# Keyboard shortcuts
	_setup_shortcuts()

	# Re-center canvas after layout is final (first call in _setup_canvas
	# happens before container sizes are known)
	canvas_view.fit_to_view.call_deferred()


# One-shot composite rebuild: coalesces multiple dabs into a single
# rebuild per frame. Flag is set in _continue_stroke then consumed here.
func _process(_delta: float):
	if _composite_dirty:
		_composite_dirty = false
		_refresh_composite()


func _find_ui_nodes():
	# Canvas
	canvas_view = %CanvasView as CanvasView
	canvas_container = %CanvasContainer as Control
	_layer_entries_container = %LayerEntries
	_layer_entries_container.set_script(
		preload("res://scripts/digital_art_lab/layer_drop_container.gd"))
	_layer_entries_container.drop_handler = _on_layer_drop
	color_wheel = %ColorWheel as ColorPickerControl

	# Brush settings
	size_slider = %SizeSlider as HSlider
	opacity_slider = %OpacitySlider as HSlider
	hardness_slider = %HardnessSlider as HSlider

	# Color display
	primary_color_rect = %PrimaryColor as ColorRect
	secondary_color_rect = %SecondaryColor as ColorRect
	recent_colors_container = %RecentColors as Container
	favorite_colors_container = %FavColors as Container

	# Zoom slider
	zoom_slider = %ZoomSlider as VSlider

	# Labels
	zoom_label = %ZoomLabel as Label
	coord_label = %CoordLabel as Label
	tool_label = %ToolLabel as Label
	layer_label = %LayerLabel as Label
	artwork_name_label = %ArtworkName as Label
	file_status_label = %FileStatus as Label

	# Buttons
	tool_buttons[Tool.BRUSH] = %BrushBtn as Button
	tool_buttons[Tool.ERASER] = %EraserBtn as Button
	tool_buttons[Tool.FILL] = %FillBtn as Button
	tool_buttons[Tool.EYEDROPPER] = %EyeBtn as Button
	tool_buttons[Tool.PAN] = %PanBtn as Button
	tool_buttons[Tool.ZOOM] = %ZoomBtn as Button

	save_button = %SaveBtn as Button
	load_button = %LoadBtn as Button
	export_button = %ExportBtn as Button
	new_button = %NewBtn as Button
	close_button = %CloseBtn as Button
	undo_button = %UndoBtn as Button
	redo_button = %RedoBtn as Button
	grid_toggle = %GridBtn as Button

	# Dialogs
	completion_panel = %CompletionPanel as Panel
	save_dialog = %SaveDialog as Panel
	load_dialog = %LoadDialog as Panel
	portfolio_browser = %PortfolioItems as ItemList

	# Layer buttons
	%AddLayerBtn.pressed.connect(_on_add_layer)
	%DeleteLayerBtn.pressed.connect(_on_delete_layer)
	%DuplicateLayerBtn.pressed.connect(_on_duplicate_layer)
	%MergeDownBtn.pressed.connect(_on_merge_down)
	%LayerUpBtn.pressed.connect(_on_layer_up)
	%LayerDownBtn.pressed.connect(_on_layer_down)

	# Color picker
	%SwapColorsBtn.pressed.connect(color_manager.swap)


func _setup_canvas():
	layer_manager.setup(_canvas_w, _canvas_h)
	canvas_view.canvas_width = _canvas_w
	canvas_view.canvas_height = _canvas_h
	canvas_view.fit_to_view()
	_refresh_composite()
	# Clip canvas drawing so zoomed-in content doesn't overflow onto toolbars
	%CanvasContainer.clip_contents = true


func _setup_default_layers():
	# Start with a white background layer like a real art app
	layer_manager.add_background_layer(Color.WHITE)
	layer_manager.add_layer("Sketch")
	layer_manager.active_index = 1
	layer_manager.layers_changed.emit()
	layer_manager.active_layer_changed.emit(1)


func _connect_ui_signals():
	# Tool buttons
	for tool in tool_buttons:
		var btn: Button = tool_buttons[tool] as Button
		if btn:
			btn.pressed.connect(_on_tool_selected.bind(tool))

	# Canvas mouse events — wired directly so painting works even if
	# mouse_entered hasn't fired (avoid lazy connection pattern)
	canvas_container.gui_input.connect(_on_canvas_gui_input)
	canvas_container.mouse_exited.connect(_on_canvas_mouse_exited)

	# Layer manager signals
	layer_manager.layers_changed.connect(_refresh_composite)
	layer_manager.active_layer_changed.connect(_on_active_layer_changed)

	# Color manager
	color_manager.color_changed.connect(_on_color_changed)
	color_manager.swapped.connect(_update_color_ui)

	# Brush settings
	size_slider.value_changed.connect(_on_brush_size_changed)
	opacity_slider.value_changed.connect(_on_brush_opacity_changed)
	hardness_slider.value_changed.connect(_on_brush_hardness_changed)

	# Color wheel
	color_wheel.color_changed.connect(_on_color_wheel_changed)

	# File operations
	save_button.pressed.connect(_on_save)
	load_button.pressed.connect(_on_load)
	export_button.pressed.connect(_on_export_png)
	new_button.pressed.connect(_on_new)
	close_button.pressed.connect(_on_close)
	undo_button.pressed.connect(_on_undo)
	redo_button.pressed.connect(_on_redo)
	grid_toggle.toggled.connect(_on_grid_toggled)

	# Save dialog
	%SaveConfirmBtn.pressed.connect(_on_save_confirm)
	%SaveCancelBtn.pressed.connect(_on_save_cancel)

	# Load dialog
	%LoadOpenBtn.pressed.connect(_on_load_open)
	%LoadCancelBtn.pressed.connect(_on_load_cancel)
	%LoadDeleteBtn.pressed.connect(_on_load_delete)
	%RefreshBtn.pressed.connect(_on_refresh_portfolio)

	# Completion panel
	%ContBtn.pressed.connect(_on_complete_continue)

	# Portfolio manager
	portfolio_manager.portfolio_changed.connect(_on_portfolio_changed)
	portfolio_manager.artwork_opened.connect(_on_artwork_opened)

	# Hint button
	hint_button = %HintBtn as Button
	if hint_button:
		hint_button.pressed.connect(_on_hint_pressed)

	# Canvas view updates
	canvas_view.view_changed.connect(_on_view_changed)
	zoom_slider.value_changed.connect(_on_zoom_slider_changed)


func _setup_shortcuts():
	var shortcuts := {
		KEY_B: Tool.BRUSH,
		KEY_E: Tool.ERASER,
		KEY_G: Tool.FILL,
		KEY_I: Tool.EYEDROPPER,
		KEY_H: Tool.PAN,
		KEY_Z: -1,  # special: undo
		KEY_Y: -2,  # special: redo
	}
	for key in shortcuts:
		var tc := Shortcut.new()
		var ev := InputEventKey.new()
		ev.keycode = key
		tc.events = [ev]
		# We handle shortcuts via _input instead


# ── Canvas painting input ────────────────────────────────────

func _input(event: InputEvent):
	# Keyboard shortcuts
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_B: _select_tool(Tool.BRUSH)
			KEY_E: _select_tool(Tool.ERASER)
			KEY_G: _select_tool(Tool.FILL)
			KEY_I: _select_tool(Tool.EYEDROPPER)
			KEY_H: _select_tool(Tool.PAN)
			KEY_Z:
				if event.ctrl_pressed:
					if event.shift_pressed:
						_on_redo()
					else:
						_on_undo()
			KEY_Y: if event.ctrl_pressed: _on_redo()
			KEY_S: if event.ctrl_pressed: _on_save()
			KEY_N: if event.ctrl_pressed: _on_new()
			KEY_O: if event.ctrl_pressed: _on_load()
			KEY_PLUS: canvas_view.set_zoom(canvas_view.zoom * 1.15)
			KEY_MINUS: canvas_view.set_zoom(canvas_view.zoom / 1.15)
			KEY_0: canvas_view.fit_to_view()

	# If Space is held, temporarily switch to pan tool
	if event is InputEventKey and event.keycode == KEY_SPACE:
		if event.pressed and current_tool != Tool.PAN:
			_forced_pan = true
		elif not event.pressed and _forced_pan:
			_forced_pan = false

var _forced_pan := false

# Canvas mouse events are handled via CanvasView's _gui_input forwarding.
# We connect to CanvasView's input directly.

func _on_canvas_gui_input(event: InputEvent):
	var tool := Tool.PAN if _forced_pan else current_tool
	canvas_view.pan_mode = tool == Tool.PAN
	canvas_view.handle_input(event)
	var mouse_pos := canvas_view.get_local_mouse_position()
	var canvas_pos := canvas_view.screen_to_canvas(mouse_pos)

	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			match tool:
				Tool.BRUSH:
					_start_stroke(canvas_pos)
				Tool.ERASER:
					_start_stroke(canvas_pos)
				Tool.FILL:
					_do_fill(canvas_pos)
				Tool.EYEDROPPER:
					_do_eyedropper(canvas_pos)
				Tool.ZOOM:
					if event.ctrl_pressed:
						canvas_view.set_zoom(canvas_view.zoom / 1.15, mouse_pos)
					else:
						canvas_view.set_zoom(canvas_view.zoom * 1.15, mouse_pos)

		if not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if _stroking:
				_end_stroke()
				canvas_view.cursor_overlay.set_painting(false)

	if event is InputEventMouseMotion:
		var overlay := canvas_view.cursor_overlay
		var is_brush := tool == Tool.BRUSH or tool == Tool.ERASER
		var z := canvas_view.zoom

		if is_brush:
			overlay.show_brush_preview = true
			overlay.brush_preview_pos = mouse_pos
			overlay.brush_preview_size = brush_size * z
			overlay.brush_preview_color = color_manager.primary
			overlay.show_cursor(mouse_pos, _stroking, brush_size * 0.5 * z, 8.0 * z)
		else:
			overlay.show_brush_preview = false
			overlay.show_cursor(mouse_pos, false, 0.0, 8.0 * z)

		if not _stroking or _stroke_sample_dist < 1.0:
			coord_label.text = "%d, %d" % [int(canvas_pos.x), int(canvas_pos.y)]

		if _stroking:
			_continue_stroke(canvas_pos)


func _select_tool(t: Tool):
	current_tool = t
	_update_tool_ui()
	var names := {Tool.BRUSH: "Brush", Tool.ERASER: "Eraser", Tool.FILL: "Fill",
		Tool.EYEDROPPER: "Eyedropper", Tool.PAN: "Pan", Tool.ZOOM: "Zoom"}
	tool_label.text = names.get(t, "")


func _on_tool_selected(t: Tool):
	_select_tool(t)


# ── Stroke handling ──────────────────────────────────────────

func _start_stroke(canvas_pos: Vector2):
	var layer_data := layer_manager.get_active()
	if layer_data == null or layer_data.locked:
		return
	_stroking = true
	var z := canvas_view.zoom
	canvas_view.cursor_overlay.show_cursor(
		canvas_view.cursor_overlay.cursor_screen_pos, true,
		brush_size * 0.5 * z, 8.0 * z)
	_last_stroke_pos = canvas_pos
	_stroke_sample_dist = 0.0

	var brush_radius := int(ceil(brush_size / 2.0))
	var canvas_ij := Vector2i(int(canvas_pos.x), int(canvas_pos.y))
	history_manager.begin_stroke(layer_manager.active_index, canvas_ij, brush_radius, layer_data.image)

	var col := color_manager.primary
	if current_tool == Tool.BRUSH:
		painter.paint_dab(layer_data, canvas_pos.x, canvas_pos.y,
			col, brush_size, brush_hardness, brush_opacity)
	else:
		painter.erase_dab(layer_data, canvas_pos.x, canvas_pos.y,
			brush_size, brush_hardness, brush_opacity)

	var br := int(ceil(brush_size / 2.0))
	var dirty_rect := Rect2i(int(canvas_pos.x) - br, int(canvas_pos.y) - br, br * 2, br * 2)
	layer_manager.mark_dirty_rect(dirty_rect)
	_refresh_composite()


func _continue_stroke(canvas_pos: Vector2):
	var layer_data := layer_manager.get_active()
	if layer_data == null or layer_data.locked:
		return

	var dist := _last_stroke_pos.distance_to(canvas_pos)
	var spacing_px := brush_size * brush_spacing
	_stroke_sample_dist += dist

	# Sample along the line at spacing intervals
	if _stroke_sample_dist >= spacing_px:
		var t := spacing_px / dist if dist > 0 else 1.0
		var sample_pos := _last_stroke_pos.lerp(canvas_pos, t)

		var brush_radius := int(ceil(brush_size / 2.0))
		var sample_ij := Vector2i(int(sample_pos.x), int(sample_pos.y))
		history_manager.extend_stroke(sample_ij, brush_radius, layer_data.image)

		if current_tool == Tool.BRUSH:
			painter.paint_dab(layer_data, sample_pos.x, sample_pos.y,
				color_manager.primary, brush_size, brush_hardness, brush_opacity)
		else:
			painter.erase_dab(layer_data, sample_pos.x, sample_pos.y,
				brush_size, brush_hardness, brush_opacity)

		_stroke_sample_dist = 0.0
		_last_stroke_pos = sample_pos
		var dr := Rect2i(int(sample_pos.x) - brush_radius, int(sample_pos.y) - brush_radius,
			brush_radius * 2, brush_radius * 2)
		layer_manager.mark_dirty_rect(dr)
		_composite_dirty = true


func _end_stroke():
	_stroking = false
	history_manager.end_stroke(layer_manager)
	_update_undo_ui()
	# Only update the active layer's thumbnail — skip full UI rebuild
	var active_layer := layer_manager.get_active()
	if active_layer:
		active_layer.generate_thumbnail(48)
		var idx := layer_manager.active_index
		if idx >= 0 and idx < _layer_entries_container.get_child_count():
			var entry := _layer_entries_container.get_child(idx) as Control
			if entry:
				var thumb := entry.get_child(2) as TextureRect
				if thumb and active_layer.thumbnail:
					thumb.texture = ImageTexture.create_from_image(active_layer.thumbnail)


func _do_fill(canvas_pos: Vector2):
	var layer_data := layer_manager.get_active()
	if layer_data == null or layer_data.locked:
		return
	var pos := Vector2i(int(canvas_pos.x), int(canvas_pos.y))

	# Snapshot the full layer before fill, then push as a FILL action
	var _r := int(ceil(max(layer_manager.canvas_w, layer_manager.canvas_h) / 2.0))
	var full_region := Rect2i(Vector2i.ZERO, Vector2i(layer_manager.canvas_w, layer_manager.canvas_h))
	var before := history_manager.capture_region(layer_data.image, full_region)

	painter.flood_fill(layer_data, pos.x, pos.y, color_manager.primary, 0.1)

	history_manager.push_fill(layer_manager.active_index, layer_data.image, full_region, before)
	layer_data.generate_thumbnail(48)
	_update_layer_ui()
	layer_manager.mark_dirty()
	_refresh_composite()
	_update_undo_ui()


func _do_eyedropper(canvas_pos: Vector2):
	var composite := layer_manager.get_composited()
	var pos := Vector2i(int(canvas_pos.x), int(canvas_pos.y))
	var c := painter.sample_color(composite, pos.x, pos.y)
	if c.a > 0:
		color_manager.set_primary(c)
		_update_color_ui()
	# Automatically switch back to brush after picking
	_select_tool(Tool.BRUSH)


# ── Layer UI ─────────────────────────────────────────────────

func _on_add_layer():
	var data: LayerData = layer_manager.add_layer()
	if data != null:
		var idx := layer_manager.layers.find(data)
		if idx >= 0:
			history_manager.push_add_layer(idx, data)
	_update_layer_ui()
	_update_undo_ui()


func _on_delete_layer():
	var idx := layer_manager.active_index
	if idx < 0 or idx >= layer_manager.layers.size():
		return
	var layer_data: LayerData = layer_manager.layers[idx]
	var copy := layer_data.duplicate_layer(layer_data.layer_name)
	if layer_manager.delete_layer(idx):
		history_manager.push_delete_layer(idx, copy)
		_update_layer_ui()
		_update_undo_ui()


func _on_duplicate_layer():
	var idx := layer_manager.active_index
	if idx < 0 or idx >= layer_manager.layers.size():
		return
	if layer_manager.duplicate_layer(idx):
		if idx + 1 < layer_manager.layers.size():
			var new_data: LayerData = layer_manager.layers[idx + 1]
			history_manager.push_duplicate_layer(idx, new_data)
		_update_layer_ui()
		_update_undo_ui()


func _on_merge_down():
	var idx := layer_manager.active_index
	if idx <= 0 or idx >= layer_manager.layers.size():
		return
	var upper: LayerData = layer_manager.layers[idx]
	var lower: LayerData = layer_manager.layers[idx - 1]
	var upper_pre := upper.duplicate_layer(upper.layer_name)
	var lower_pre := lower.image.duplicate() if lower.image else null
	if layer_manager.merge_down(idx):
		var lower_post := lower.image.duplicate() if lower.image else null
		history_manager.push_merge_down(idx, upper_pre, lower_pre, lower_post)
		_update_layer_ui()
		_update_undo_ui()


func _on_layer_up():
	var idx := layer_manager.active_index
	var to := idx - 1
	if to >= 0 and idx < layer_manager.layers.size():
		history_manager.push_move_layer(idx, to)
		layer_manager.move_up(idx)
		_update_layer_ui()
		_update_undo_ui()


func _on_layer_down():
	var idx := layer_manager.active_index
	var to := idx + 1
	if idx >= 0 and to < layer_manager.layers.size():
		history_manager.push_move_layer(idx, to)
		layer_manager.move_down(idx)
		_update_layer_ui()
		_update_undo_ui()


func _on_layer_entry_gui_input(event: InputEvent, index: int):
	if index < 0 or index >= layer_manager.layers.size():
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		layer_manager.active_index = index
		layer_manager.active_layer_changed.emit(index)


func _on_layer_drop(from_index: int, to_index: int):
	if from_index < 0 or from_index >= layer_manager.layers.size():
		return
	if to_index < 0 or to_index >= layer_manager.layers.size():
		return
	if from_index == to_index:
		return
	history_manager.push_move_layer(from_index, to_index)
	layer_manager.move_layer(from_index, to_index)
	_update_layer_ui()
	_update_undo_ui()


func _on_layer_visibility_toggled(index: int):
	if index < 0 or index >= layer_manager.layers.size():
		return
	var l := layer_manager.layers[index]
	history_manager.push_modify_visibility(index, l.visible)
	l.visible = not l.visible
	# Update the eye button directly (avoids a full UI rebuild)
	if index < _layer_entries_container.get_child_count():
		var entry := _layer_entries_container.get_child(index) as Control
		if entry:
			var panel := entry.get_child(3) as HBoxContainer
			if panel:
				var vis_btn := panel.get_child(2) as Button
				if vis_btn:
					vis_btn.text = "👁" if l.visible else "  "
	layer_manager.composited_dirty = true
	_refresh_composite()
	_update_undo_ui()


func _on_active_layer_changed(index: int):
	if index < layer_manager.layers.size():
		layer_label.text = "Active: " + layer_manager.layers[index].layer_name + \
			" [%d/%d]" % [index + 1, layer_manager.layers.size()]
	else:
		layer_label.text = "No layer"
	var hl := Color(0.25, 0.45, 0.75, 0.35)
	for i in _layer_entries_container.get_child_count():
		var entry := _layer_entries_container.get_child(i) as Control
		if not entry:
			continue
		var bg := entry.get_child(0) as ColorRect
		if bg:
			bg.color = hl if i == index else Color.TRANSPARENT


func _update_layer_ui():
	var old := _layer_entries_container.get_children()
	for child in old:
		_layer_entries_container.remove_child(child)
		child.call_deferred("free")
	var hl := Color(0.25, 0.45, 0.75, 0.35)
	var border := Color(0.15, 0.2, 0.3, 0.6)
	var DragEntry := preload("res://scripts/digital_art_lab/layer_drag_entry.gd")
	for i in range(layer_manager.layers.size()):
		var l: LayerData = layer_manager.layers[i]
		var entry: Control = DragEntry.new()
		entry.layer_index = i
		entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		entry.custom_minimum_size.y = 56
		# Row background
		var bg := ColorRect.new()
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.color = hl if i == layer_manager.active_index else Color.TRANSPARENT
		entry.add_child(bg)
		# Bottom border line
		var line := ColorRect.new()
		line.anchor_left = 0
		line.anchor_right = 1
		line.anchor_top = 1
		line.anchor_bottom = 1
		line.offset_top = -1
		line.color = border
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		entry.add_child(line)
		# Thumbnail (the "shape") — fills the row height
		l.generate_thumbnail(56)
		var thumb := TextureRect.new()
		thumb.custom_minimum_size = Vector2(56, 56)
		thumb.size_flags_horizontal = 0
		thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		if l.thumbnail:
			thumb.texture = ImageTexture.create_from_image(l.thumbnail)
		entry.add_child(thumb)
		# Right-side controls panel
		var right_panel := HBoxContainer.new()
		right_panel.anchor_left = 0
		right_panel.anchor_right = 1
		right_panel.anchor_top = 0
		right_panel.anchor_bottom = 1
		right_panel.offset_left = 60  # after thumbnail + gap
		entry.add_child(right_panel)
		# Layer name label
		var label := Label.new()
		label.text = l.layer_name
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		right_panel.add_child(label)
		# Lock icon
		var lock := Label.new()
		lock.text = " 🔒" if l.locked else "   "
		lock.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lock.custom_minimum_size.x = 24
		right_panel.add_child(lock)
		# Visibility toggle
		var vis := Button.new()
		vis.text = "👁" if l.visible else "  "
		vis.flat = true
		vis.tooltip_text = "Toggle visibility"
		vis.custom_minimum_size = Vector2(24, 24)
		vis.pressed.connect(_on_layer_visibility_toggled.bind(i))
		right_panel.add_child(vis)
		# Click to select layer
		entry.gui_input.connect(_on_layer_entry_gui_input.bind(i))
		_layer_entries_container.add_child(entry)


# ── Color UI ─────────────────────────────────────────────────

func _on_color_changed(c: Color):
	primary_color_rect.color = c
	color_wheel.set_color(c)


func _on_color_wheel_changed(c: Color):
	color_manager.set_primary(c)
	_update_color_ui()


func _on_swap_colors():
	color_manager.swap()


func _update_color_ui():
	primary_color_rect.color = color_manager.primary
	secondary_color_rect.color = color_manager.secondary
	_rebuild_color_swatches(recent_colors_container, color_manager.recent)
	_rebuild_color_swatches(favorite_colors_container, color_manager.favorites)


func _rebuild_color_swatches(container: Container, colors: Array[Color]):
	for child in container.get_children():
		child.queue_free()
	for c in colors:
		var rect := ColorRect.new()
		rect.color = c
		rect.custom_minimum_size = Vector2(20, 20)
		rect.size = Vector2(20, 20)
		rect.mouse_filter = Control.MOUSE_FILTER_STOP
		rect.gui_input.connect(_on_swatch_clicked.bind(c, rect))
		container.add_child(rect)


func _on_swatch_clicked(event: InputEvent, color: Color, _rect: ColorRect):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		color_manager.set_primary(color)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		color_manager.toggle_favorite(color)
		_update_color_ui()


# ── Brush settings UI ────────────────────────────────────────

func _on_brush_size_changed(val: float):
	brush_size = int(val)


func _on_brush_opacity_changed(val: float):
	brush_opacity = val


func _on_brush_hardness_changed(val: float):
	brush_hardness = val


func _update_brush_ui():
	size_slider.value = brush_size
	opacity_slider.value = brush_opacity
	hardness_slider.value = brush_hardness


# ── Tool UI ──────────────────────────────────────────────────

func _update_tool_ui():
	for tool in tool_buttons:
		var btn: Button = tool_buttons[tool] as Button
		if btn:
			btn.button_pressed = (tool == current_tool)


# ── Undo / Redo UI ───────────────────────────────────────────

func _on_undo():
	if history_manager.undo(layer_manager):
		_refresh_composite()
		_update_layer_ui()
		_update_undo_ui()


func _on_redo():
	if history_manager.redo(layer_manager):
		_refresh_composite()
		_update_layer_ui()
		_update_undo_ui()


func _update_undo_ui():
	undo_button.disabled = not history_manager.can_undo()
	redo_button.disabled = not history_manager.can_redo()


# ── View controls ────────────────────────────────────────────

func _on_grid_toggled(toggled: bool):
	canvas_view.show_grid = toggled
	canvas_view.queue_redraw()


func _on_view_changed(z: float, _off: Vector2):
	zoom_label.text = str(int(z * 100)) + "%"
	zoom_slider.set_value_no_signal(z * 100)


func _on_zoom_slider_changed(v: float):
	canvas_view.set_zoom(v / 100.0)


# ── Composite refresh ────────────────────────────────────────

func _refresh_composite():
	canvas_view.composite_image = layer_manager.get_composited()


# ── Canvas mouse tracking ────────────────────────────────────

func _on_canvas_mouse_exited():
	canvas_view.cursor_overlay.show_brush_preview = false
	canvas_view.cursor_overlay.hide_cursor()


# ── File operations ──────────────────────────────────────────

func _on_new():
	_canvas_w = 512
	_canvas_h = 512
	_artwork_name = "Untitled"
	_current_file_path = ""
	_current_data = null
	history_manager.clear()
	layer_manager.setup(_canvas_w, _canvas_h)
	_setup_default_layers()
	canvas_view.canvas_width = _canvas_w
	canvas_view.canvas_height = _canvas_h
	canvas_view.fit_to_view()
	_update_layer_ui()
	_update_title()
	_update_undo_ui()
	_refresh_composite()


func _on_save():
	if _current_file_path.is_empty():
		# Show save dialog
		%SaveNameEdit.text = _artwork_name
		%SaveCategoryOption.selected = 0
		save_dialog.visible = true
	else:
		_save_to_file(_current_file_path)


func _on_save_confirm():
	var artwork_name_val: String = %SaveNameEdit.text.strip_edges()
	if artwork_name_val.is_empty():
		artwork_name_val = "Untitled"
	var category: String = %SaveCategoryOption.get_item_text(%SaveCategoryOption.selected)
	_artwork_name = artwork_name_val
	_current_data = _build_artwork_data()
	_current_data.category = category.to_lower()
	var path := file_manager.save_artwork(_current_data, _artwork_name)
	if not path.is_empty():
		_current_file_path = path
		_has_saved_at_least_once = true
		save_dialog.visible = false
		_update_title()
		portfolio_manager.refresh()
		_show_toast("Saved: " + _artwork_name)
		# Check milestone: saving triggers level completion
		_check_completion()
	else:
		%SaveErrorLabel.visible = true


func _on_save_cancel():
	save_dialog.visible = false


func _on_export_png():
	var composited := layer_manager.get_composited()
	if composited == null:
		zoom_label.text = "Nothing to export!"
		await get_tree().create_timer(2.0).timeout
		_on_view_changed(canvas_view.zoom, canvas_view.offset)
		return
	var img := composited.duplicate()
	var path := file_manager.export_png(img, _artwork_name)
	if not path.is_empty():
		_show_toast("Exported: " + _artwork_name + ".png")
	else:
		zoom_label.text = "Export failed!"
		await get_tree().create_timer(2.0).timeout
		_on_view_changed(canvas_view.zoom, canvas_view.offset)


func _save_to_file(path: String):
	_current_data = _build_artwork_data()
	var err := ResourceSaver.save(_current_data, path)
	if err == OK:
		_current_file_path = path
		_has_saved_at_least_once = true
		portfolio_manager.refresh()
		_show_toast("Saved: " + _artwork_name)
		_check_completion()


func _build_artwork_data() -> DigitalArtData:
	var data := DigitalArtData.new()
	data.artwork_name = _artwork_name
	data.canvas_width = _canvas_w
	data.canvas_height = _canvas_h
	layer_manager.save_to_data(data)
	return data


func _on_load():
	portfolio_manager.refresh()
	_rebuild_portfolio_browser()
	load_dialog.visible = true


func _on_load_open():
	var sel := portfolio_browser.get_selected_items()
	if sel.size() > 0:
		var ok := portfolio_manager.open_artwork(sel[0])
		if ok:
			load_dialog.visible = false
		else:
			zoom_label.text = "Failed to load artwork!"
			await get_tree().create_timer(2.0).timeout
			_on_view_changed(canvas_view.zoom, canvas_view.offset)


func _on_load_cancel():
	load_dialog.visible = false


func _on_load_delete():
	var sel := portfolio_browser.get_selected_items()
	if sel.size() > 0:
		portfolio_manager.delete_artwork(sel[0])
		portfolio_manager.refresh()


func _on_refresh_portfolio():
	portfolio_manager.refresh()


func _on_portfolio_changed():
	_rebuild_portfolio_browser()


func _rebuild_portfolio_browser():
	portfolio_browser.clear()
	for entry in portfolio_manager.get_entries():
		portfolio_browser.add_item(entry.name)


func _on_artwork_opened(data: DigitalArtData, path: String):
	_current_data = data
	_current_file_path = path
	_artwork_name = data.artwork_name
	_canvas_w = data.canvas_width
	_canvas_h = data.canvas_height

	history_manager.clear()
	layer_manager.load_from_data(data)
	canvas_view.canvas_width = _canvas_w
	canvas_view.canvas_height = _canvas_h
	canvas_view.fit_to_view()
	_update_layer_ui()
	_update_title()
	_update_undo_ui()
	_refresh_composite()


func _show_toast(msg: String):
	var toast := %Toast as Panel
	var label := toast.get_child(0) as Label
	label.text = msg
	toast.visible = true
	await get_tree().create_timer(2.0).timeout
	toast.visible = false


func _update_title():
	artwork_name_label.text = _artwork_name
	if _current_file_path.is_empty():
		file_status_label.text = ""
	else:
		var fname := _current_file_path.get_file().trim_suffix(".tres")
		file_status_label.text = "Editing: " + fname


# ── Completion / Level progression ───────────────────────────

func _check_completion():
	# Level 2 is considered "complete" when the player saves their first artwork.
	# This feeds into Level 3 (reference images for 3D modelling).
	if not _has_saved_at_least_once:
		return
	# Show the completion panel
	completion_panel.visible = true


func _on_complete_continue():
	completion_panel.visible = false


func _on_hint_pressed():
	# In Level 2, "hints" show a quick tutorial overlay.
	# For now, just show a simple tip.
	if %HintLabel:
		%HintLabel.visible = not %HintLabel.visible


func _on_close():
	lab_closed.emit()
	if _has_saved_at_least_once:
		var level_def := ResourceLoader.load("res://data/levels/digital_art_lab.tres") as LevelDefinition
		if level_def:
			LevelProgression.complete_level(level_def)
	var return_scene := LevelProgression.get_resume_scene()
	if return_scene.is_empty():
		return_scene = fallback_scene
	else:
		LevelProgression.save_spawn_position(return_scene, LevelProgression.get_resume_spawn().get("player", Vector3.ZERO), LevelProgression.get_resume_spawn().get("camera_offset", Vector3.ZERO))
		LevelProgression.clear_resume_state()
	get_tree().change_scene_to_file(return_scene)
