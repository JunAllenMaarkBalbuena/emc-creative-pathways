class_name HistoryEntry
## Stores pixel data for a region on one layer before or after a change.

var layer_index: int
var region: Rect2i
var pixels: PackedByteArray  # RGBA8 bytes, region.size.x * region.size.y * 4
var timestamp: int  # unused, for debugging


func _init(layer_idx: int, rect: Rect2i, pixel_data: PackedByteArray):
	layer_index = layer_idx
	region = rect
	pixels = pixel_data
	timestamp = Time.get_ticks_msec()
