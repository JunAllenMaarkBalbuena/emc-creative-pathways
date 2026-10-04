class_name LayerData
extends Resource

## Represents one layer in the digital art canvas.
## Stores pixel data as an Image with metadata for the layer panel.

enum Type { NORMAL, BACKGROUND, REFERENCE }

@export var layer_name := "Layer"
@export var layer_type := Type.NORMAL
@export var visible := true
@export var locked := false
@export var opacity := 1.0
@export var blend_mode := 0  # 0 = Normal (future: blend mode enums)

# The pixel data for this layer. Created at canvas resolution.
var image: Image

# Cached thumbnail (64x64). Regenerated on save.
var thumbnail: Image


func create(canvas_w: int, canvas_h: int, fill_color: Color = Color.TRANSPARENT):
	image = Image.create(canvas_w, canvas_h, false, Image.FORMAT_RGBA8)
	if fill_color.a > 0:
		image.fill(fill_color)


func duplicate_layer(new_name: String = "") -> LayerData:
	var copy := LayerData.new()
	copy.layer_name = new_name if not new_name.is_empty() else layer_name + " Copy"
	copy.layer_type = layer_type
	copy.visible = visible
	copy.locked = locked
	copy.opacity = opacity
	copy.blend_mode = blend_mode
	if image:
		copy.image = image.duplicate()
	return copy


func generate_thumbnail(size: int = 64):
	if image == null:
		return
	var copy := image.duplicate()
	copy.resize(size, size, Image.INTERPOLATE_LANCZOS)
	thumbnail = Image.create(size, size, false, Image.FORMAT_RGBA8)
	thumbnail.blit_rect(copy, Rect2i(0, 0, size, size), Vector2i.ZERO)
