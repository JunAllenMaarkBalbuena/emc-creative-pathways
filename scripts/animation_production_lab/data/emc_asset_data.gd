class_name EMCAssetData
extends Resource

## One addressable asset in the animation lab's EMC Asset Library. An asset
## is a descriptor, not a scene: the WorldController decides how to spawn a
## node from (category, asset_type, path, metadata). Primitive props carry no
## path; their geometry comes from metadata.shape.

@export var asset_id := ""
@export var display_name := ""
@export var category := ""          # "character" | "background" | "prop" | "user_art" | ...
@export var asset_type := ""        # "sprite" | "primitive" | "drawing"
@export var source_lab := ""        # "starter" | "illustration" | ...
@export var path := ""              # res:// or user:// path; "" for primitive props
@export var preview_texture: Texture2D
@export var metadata: Dictionary = {}