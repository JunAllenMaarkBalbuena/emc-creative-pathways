class_name LayerManager
extends RefCounted

signal layers_changed
signal active_layer_changed(index: int)

var layers: Array[LayerData] = []
var active_index := 0
var canvas_w := 1024
var canvas_h := 1024

var composited: Image
var composited_dirty := true
var _dirty_rect: Rect2i  # ignored unless composited_dirty is true


func setup(width: int, height: int):
	canvas_w = width
	canvas_h = height
	layers.clear()
	var bg := LayerData.new()
	bg.layer_name = "Background"
	bg.create(canvas_w, canvas_h)
	layers.append(bg)
	active_index = 0
	composited_dirty = true


func add_layer(name: String = "") -> LayerData:
	var l: LayerData = LayerData.new()
	l.layer_name = name if not name.is_empty() else "Layer " + str(layers.size() + 1)
	l.create(canvas_w, canvas_h)
	layers.append(l)
	active_index = layers.size() - 1
	composited_dirty = true
	layers_changed.emit()
	active_layer_changed.emit(active_index)
	return l


func add_background_layer(color: Color) -> LayerData:
	var l: LayerData = LayerData.new()
	l.layer_name = "Background"
	l.layer_type = LayerData.Type.BACKGROUND
	l.create(canvas_w, canvas_h, color)
	layers.insert(0, l)
	active_index = layers.size() - 1
	composited_dirty = true
	layers_changed.emit()
	active_layer_changed.emit(active_index)
	return l


func delete_layer(index: int) -> bool:
	if layers.size() <= 1 or index < 0 or index >= layers.size():
		return false
	layers.remove_at(index)
	if active_index >= layers.size():
		active_index = layers.size() - 1
	composited_dirty = true
	layers_changed.emit()
	active_layer_changed.emit(active_index)
	return true


func duplicate_layer(index: int) -> bool:
	if index < 0 or index >= layers.size():
		return false
	var copy: LayerData = layers[index].duplicate_layer()
	layers.insert(index + 1, copy)
	active_index = index + 1
	composited_dirty = true
	layers_changed.emit()
	active_layer_changed.emit(active_index)
	return true


func merge_down(index: int) -> bool:
	if index <= 0 or index >= layers.size():
		return false
	var upper: LayerData = layers[index] as LayerData
	var lower: LayerData = layers[index - 1] as LayerData
	if lower.image == null:
		return false
	_blend_onto(upper, lower)
	layers.remove_at(index)
	active_index = index - 1
	composited_dirty = true
	layers_changed.emit()
	active_layer_changed.emit(active_index)
	return true


func move_up(index: int) -> bool:
	if index <= 0 or index >= layers.size():
		return false
	var tmp: LayerData = layers[index]
	layers[index] = layers[index - 1]
	layers[index - 1] = tmp
	if active_index == index:
		active_index = index - 1
	elif active_index == index - 1:
		active_index = index
	composited_dirty = true
	layers_changed.emit()
	active_layer_changed.emit(active_index)
	return true


func move_down(index: int) -> bool:
	if index < 0 or index >= layers.size() - 1:
		return false
	var tmp: LayerData = layers[index]
	layers[index] = layers[index + 1]
	layers[index + 1] = tmp
	if active_index == index:
		active_index = index + 1
	elif active_index == index + 1:
		active_index = index
	composited_dirty = true
	layers_changed.emit()
	active_layer_changed.emit(active_index)
	return true


func move_layer(from: int, to: int) -> bool:
	if from < 0 or from >= layers.size() or to < 0 or to >= layers.size():
		return false
	if from == to:
		return true
	var l: LayerData = layers[from]
	layers.remove_at(from)
	layers.insert(to, l)
	if from < to:
		if active_index == from:
			active_index = to
		elif active_index > from and active_index <= to:
			active_index -= 1
	else:
		if active_index == from:
			active_index = to
		elif active_index >= to and active_index < from:
			active_index += 1
	composited_dirty = true
	layers_changed.emit()
	active_layer_changed.emit(active_index)
	return true


func set_visible(index: int, visible: bool):
	if index < 0 or index >= layers.size():
		return
	layers[index].visible = visible
	composited_dirty = true
	layers_changed.emit()


func set_locked(index: int, locked: bool):
	if index < 0 or index >= layers.size():
		return
	layers[index].locked = locked
	layers_changed.emit()


func set_opacity(index: int, opacity: float):
	if index < 0 or index >= layers.size():
		return
	layers[index].opacity = clampf(opacity, 0.0, 1.0)
	composited_dirty = true
	layers_changed.emit()


func rename_layer(index: int, name: String):
	if index < 0 or index >= layers.size():
		return
	layers[index].layer_name = name
	layers_changed.emit()


func get_active() -> LayerData:
	if active_index < 0 or active_index >= layers.size():
		return null
	return layers[active_index]


func get_composited() -> Image:
	if composited_dirty or composited == null:
		_rebuild_composited()
	return composited


func mark_dirty():
	composited_dirty = true
	_dirty_rect = Rect2i(0, 0, canvas_w, canvas_h)


func mark_dirty_rect(rect: Rect2i):
	composited_dirty = true
	if _dirty_rect.size == Vector2i.ZERO:
		_dirty_rect = rect
	else:
		_dirty_rect = _dirty_rect.merge(rect)


func _rebuild_composited():
	if composited == null or composited.get_size() != Vector2i(canvas_w, canvas_h):
		composited = Image.create(canvas_w, canvas_h, false, Image.FORMAT_RGBA8)
		composited.fill(Color.TRANSPARENT)
		_dirty_rect = Rect2i(0, 0, canvas_w, canvas_h)

	if _dirty_rect.size == Vector2i.ZERO:
		_dirty_rect = Rect2i(0, 0, canvas_w, canvas_h)

	# Clamp dirty rect to canvas bounds
	var dr := _dirty_rect.intersection(Rect2i(0, 0, canvas_w, canvas_h))
	if dr.size.x <= 0 or dr.size.y <= 0:
		_dirty_rect = Rect2i()
		composited_dirty = false
		return

	# Clear dirty area in existing composite, then re-composite from bottom
	# Use blit_rect for faster bulk clear vs per-pixel loop
	var clear_img := Image.create(dr.size.x, dr.size.y, false, Image.FORMAT_RGBA8)
	clear_img.fill(Color.TRANSPARENT)
	composited.blit_rect(clear_img, Rect2i(Vector2i.ZERO, dr.size), dr.position)

	for l in layers:
		var layer: LayerData = l
		if not layer.visible or layer.image == null:
			continue
		_composite_onto(layer, composited, dr)

	_dirty_rect = Rect2i()
	composited_dirty = false


func _composite_onto(src_layer: LayerData, dst_img: Image, region: Rect2i = Rect2i()):
	var src: Image = src_layer.image
	var op: float = src_layer.opacity
	if region.size == Vector2i.ZERO:
		region = Rect2i(0, 0, mini(dst_img.get_width(), src.get_width()),
			mini(dst_img.get_height(), src.get_height()))
	var rx := region.position.x
	var ry := region.position.y
	var rw := region.size.x
	var rh := region.size.y
	for y in range(ry, ry + rh):
		for x in range(rx, rx + rw):
			var sp: Color = src.get_pixel(x, y)
			if sp.a <= 0.0:
				continue
			var dp: Color = dst_img.get_pixel(x, y)
			var sa: float = sp.a * op
			var nr: float = sp.r * sa + dp.r * (1.0 - sa)
			var ng: float = sp.g * sa + dp.g * (1.0 - sa)
			var nb: float = sp.b * sa + dp.b * (1.0 - sa)
			var na: float = sa + dp.a * (1.0 - sa)
			dst_img.set_pixel(x, y, Color(nr, ng, nb, na))


func _blend_onto(upper: LayerData, lower: LayerData):
	if lower.image == null:
		return
	_composite_onto(upper, lower.image)


func load_from_data(data: DigitalArtData):
	layers = data.restore_layers()
	canvas_w = data.canvas_width
	canvas_h = data.canvas_height
	if layers.is_empty():
		var bg := LayerData.new()
		bg.layer_name = "Background"
		bg.create(canvas_w, canvas_h)
		layers.append(bg)
	active_index = layers.size() - 1
	composited_dirty = true
	layers_changed.emit()
	active_layer_changed.emit(active_index)


func save_to_data(data: DigitalArtData):
	data.save_layers(layers)
