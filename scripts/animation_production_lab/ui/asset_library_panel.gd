extends Control

## Asset library panel (ASSETS stage): list/assets from the read-only EMC
## adapter, filter by category, pick one, and request adding it to the world.

signal add_requested(asset: EMCAssetData)
signal category_selected(category: String)

var _assets: Array[EMCAssetData] = []
var _category := ""
var _selected: EMCAssetData = null

@onready var asset_list: VBoxContainer = %AssetList
@onready var detail_label: Label = %Detail

func set_assets(assets: Array[EMCAssetData]) -> void:
	_assets = assets
	_rebuild()

func set_category(category: String) -> void:
	_category = category
	_rebuild()

func selected_asset() -> EMCAssetData:
	return _selected

func _rebuild() -> void:
	for child in asset_list.get_children():
		child.queue_free()
	for asset in _assets:
		if _category != "" and asset.category != _category:
			continue
		var b := Button.new()
		b.text = "%s  (%s)" % [asset.asset_id, asset.category]
		b.custom_minimum_size = Vector2(0, 44)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_on_pick.bind(asset))
		asset_list.add_child(b)

func _choose(category: String) -> void:
	set_category(category)
	category_selected.emit(category)

func _on_all_pressed() -> void:
	_choose("")

func _on_character_pressed() -> void:
	_choose("character")

func _on_background_pressed() -> void:
	_choose("background")

func _on_prop_pressed() -> void:
	_choose("prop")

func _on_pick(asset: EMCAssetData) -> void:
	_selected = asset
	detail_label.text = "%s — %s" % [asset.asset_id, asset.category]

func _on_add_pressed() -> void:
	if _selected != null:
		add_requested.emit(_selected)