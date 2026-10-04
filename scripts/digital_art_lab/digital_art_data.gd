class_name DigitalArtData
extends Resource

## Complete artwork file format for the Digital Art Lab.
## Saves all layer data, canvas settings, and metadata as a single .tres / .res file.

@export var artwork_name := "Untitled"
@export var canvas_width := 1024
@export var canvas_height := 1024
@export var creation_date: String = ""
@export var last_modified: String = ""
@export var category: String = ""

# Serialised layer data — each entry stores pixel data as a base64-encoded
# PackedByteArray so the whole artwork fits in one .tres file.
@export var layer_names: PackedStringArray = []
@export var layer_types: Array[int] = []  # cast from LayerData.Type
@export var layer_visibilities: PackedByteArray = []   # bool as byte
@export var layer_locks: PackedByteArray = []
@export var layer_opacities: PackedFloat64Array = []
@export var layer_blend_modes: PackedByteArray = []

# Serialised pixel data: each element is the raw RGBA8 PackedByteArray
# of the layer's image, encoded as a PoolByteArray-exportable string.
# We use PackedStringArray where each string = Marshalls.raw_to_base64(bytes).
@export var layer_pixel_data: PackedStringArray = []
@export var layer_thumbnails: PackedStringArray = []


func save_layers(layers: Array[LayerData]):
	layer_names.clear()
	layer_types.clear()
	layer_visibilities.clear()
	layer_locks.clear()
	layer_opacities.clear()
	layer_blend_modes.clear()
	layer_pixel_data.clear()
	layer_thumbnails.clear()

	for l in layers:
		layer_names.append(l.layer_name)
		layer_types.append(l.layer_type)
		layer_visibilities.append(1 if l.visible else 0)
		layer_locks.append(1 if l.locked else 0)
		layer_opacities.append(l.opacity)
		layer_blend_modes.append(l.blend_mode)

		if l.image:
			var raw := l.image.get_data()
			layer_pixel_data.append(Marshalls.raw_to_base64(raw))

		l.generate_thumbnail(64)
		if l.thumbnail:
			var thumb_raw := l.thumbnail.get_data()
			layer_thumbnails.append(Marshalls.raw_to_base64(thumb_raw))
		else:
			layer_thumbnails.append("")


func restore_layers() -> Array[LayerData]:
	var result: Array[LayerData] = []
	for i in layer_names.size():
		var l := LayerData.new()
		l.layer_name = layer_names[i] if i < layer_names.size() else "Layer " + str(i + 1)
		l.layer_type = layer_types[i] as LayerData.Type if i < layer_types.size() else LayerData.Type.NORMAL
		l.visible = layer_visibilities[i] == 1 if i < layer_visibilities.size() else true
		l.locked = layer_locks[i] == 1 if i < layer_locks.size() else false
		l.opacity = layer_opacities[i] if i < layer_opacities.size() else 1.0
		l.blend_mode = layer_blend_modes[i] if i < layer_blend_modes.size() else 0

		if i < layer_pixel_data.size() and not layer_pixel_data[i].is_empty():
			var raw := Marshalls.base64_to_raw(layer_pixel_data[i])
			if raw:
				l.image = Image.create_from_data(canvas_width, canvas_height, false, Image.FORMAT_RGBA8, raw)

		if l.image == null:
			l.create(canvas_width, canvas_height)

		if i < layer_thumbnails.size() and not layer_thumbnails[i].is_empty():
			var thumb_raw := Marshalls.base64_to_raw(layer_thumbnails[i])
			if thumb_raw:
				l.thumbnail = Image.create_from_data(64, 64, false, Image.FORMAT_RGBA8, thumb_raw)

		result.append(l)
	return result
