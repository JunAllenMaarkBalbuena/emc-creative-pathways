class_name WorldController
extends Node

## Owns every object the player can place in the 2.5D world: characters and
## backgrounds spawn as Sprite3D (billboard for characters, the existing
## player pattern), props as MeshInstance3D primitives with StandardMaterial3D.
##
## The registry Dictionary is the source of truth — the save layer serializes
## it later — and the live nodes are kept in sync. All setters return false
## for an unknown id, mirroring the "never crash on missing input" contract.

signal objects_changed
signal selection_changed(object_id: String)

const CATEGORY_CHARACTER := "character"
const CATEGORY_BACKGROUND := "background"
const CATEGORY_PROP := "prop"

const SPRITE_PIXEL_SIZE := 0.01
const BACKDROP_PIXEL_SIZE := 0.02

@export_node_path("Node3D") var character_root: NodePath
@export_node_path("Node3D") var background_root: NodePath
@export_node_path("Node3D") var prop_root: NodePath

var _registry: Dictionary = {}   # id -> Dictionary
var _nodes: Dictionary = {}      # id -> Node3D
var _next_id := 1
var _selected_id := ""


func add_asset(asset: EMCAssetData, position: Vector3 = Vector3.ZERO) -> String:
	if asset == null or asset.category == "":
		return ""
	if asset.category != CATEGORY_CHARACTER and asset.category != CATEGORY_BACKGROUND and asset.category != CATEGORY_PROP:
		return ""
	var root_node := _root_for(asset.category)
	if root_node == null:
		return ""
	var id := "obj_%d" % _next_id
	_next_id += 1
	var node := _build_node(asset, id)
	root_node.add_child(node)
	node.position = position
	_registry[id] = {
		"id": id,
		"asset_id": asset.asset_id,
		"category": asset.category,
		"type": asset.asset_type,
		"path": asset.path,
		"position": position,
		"rotation_degrees": Vector3.ZERO,
		"scale": Vector3.ONE,
		"depth": 0.0,
		"layer": 0,
		"visible": true,
		"spawn_position": position,
	}
	_nodes[id] = node
	objects_changed.emit()
	return id


func remove_object(object_id: String) -> bool:
	var node := get_object_node(object_id)
	if node == null:
		return false
	_registry.erase(object_id)
	_nodes.erase(object_id)
	node.get_parent().remove_child(node)
	node.free()
	if _selected_id == object_id:
		_selected_id = ""
	objects_changed.emit()
	return true


func duplicate_object(object_id: String) -> String:
	var node := get_object_node(object_id)
	var data: Variant = _registry.get(object_id, null)
	if node == null or data == null:
		return ""
	var dup := node.duplicate() as Node3D
	var new_id := "obj_%d" % _next_id
	_next_id += 1
	dup.name = new_id
	node.get_parent().add_child(dup)
	var pos: Vector3 = data["position"] + Vector3(0.4, 0, 0)
	dup.position = pos
	var ndata: Dictionary = (data as Dictionary).duplicate()
	ndata["id"] = new_id
	ndata["position"] = pos
	ndata["spawn_position"] = pos
	_registry[new_id] = ndata
	_nodes[new_id] = dup
	objects_changed.emit()
	return new_id


func replace_object_asset(object_id: String, asset: EMCAssetData) -> bool:
	var node := get_object_node(object_id)
	if node == null or asset == null:
		return false
	var data: Variant = _registry.get(object_id, null)
	if data == null:
		return false
	var parent := node.get_parent()
	var index := node.get_index()
	var base_position: Vector3 = data["position"]
	var rotation: Vector3 = node.rotation_degrees
	var scale: Vector3 = node.scale
	var visible_flag: bool = node.visible
	var depth_val: float = data["depth"]
	var layer_val: int = data["layer"]
	parent.remove_child(node)
	_nodes.erase(object_id)
	node.free()
	var replacement := _build_node(asset, object_id)
	parent.add_child(replacement)
	parent.move_child(replacement, clampi(index, 0, parent.get_child_count() - 1))
	replacement.position = _apply_depth(base_position, depth_val)
	replacement.rotation_degrees = rotation
	replacement.scale = scale
	replacement.visible = visible_flag
	data["asset_id"] = asset.asset_id
	data["category"] = asset.category
	data["type"] = asset.asset_type
	data["path"] = asset.path
	data["layer"] = layer_val
	_nodes[object_id] = replacement
	objects_changed.emit()
	return true


func get_object_node(object_id: String) -> Node3D:
	return _nodes.get(object_id, null) as Node3D


func get_object(object_id: String) -> Dictionary:
	var data: Variant = _registry.get(object_id, null)
	if data == null:
		return {}
	return data as Dictionary


func select(object_id: String) -> void:
	if not _registry.has(object_id):
		return
	_selected_id = object_id
	selection_changed.emit(object_id)


func selected() -> String:
	return _selected_id


func clear_selection() -> void:
	_selected_id = ""
	selection_changed.emit("")


func set_object_position(object_id: String, pos: Vector3) -> bool:
	return _apply_transform(object_id, func(node: Node3D, data: Dictionary) -> void:
		data["position"] = pos
		node.position = _apply_depth(pos, data["depth"]))


func set_object_rotation(object_id: String, rot_deg: Vector3) -> bool:
	return _apply_transform(object_id, func(node: Node3D, data: Dictionary) -> void:
		data["rotation_degrees"] = rot_deg
		node.rotation_degrees = rot_deg)


func set_object_scale(object_id: String, s: Vector3) -> bool:
	return _apply_transform(object_id, func(node: Node3D, data: Dictionary) -> void:
		data["scale"] = s
		node.scale = s)


func set_object_visible(object_id: String, v: bool) -> bool:
	return _apply_transform(object_id, func(node: Node3D, data: Dictionary) -> void:
		data["visible"] = v
		node.visible = v)


func set_object_depth(object_id: String, depth: float) -> bool:
	return _apply_transform(object_id, func(node: Node3D, data: Dictionary) -> void:
		data["depth"] = depth
		node.position = _apply_depth(data["position"], depth))


func set_object_layer(object_id: String, layer: int) -> bool:
	var node := get_object_node(object_id)
	var data: Variant = _registry.get(object_id, null)
	if node == null or data == null:
		return false
	data = data as Dictionary
	data["layer"] = layer
	node.get_parent().move_child(node, clampi(layer, 0, node.get_parent().get_child_count() - 1))
	objects_changed.emit()
	return true


func reset_object(object_id: String) -> bool:
	var node := get_object_node(object_id)
	var data: Variant = _registry.get(object_id, null)
	if node == null or data == null:
		return false
	data = data as Dictionary
	var spawn: Vector3 = data["spawn_position"]
	data["position"] = spawn
	data["rotation_degrees"] = Vector3.ZERO
	data["scale"] = Vector3.ONE
	data["depth"] = 0.0
	data["layer"] = 0
	data["visible"] = true
	node.position = spawn
	node.rotation_degrees = Vector3.ZERO
	node.scale = Vector3.ONE
	node.visible = true
	node.get_parent().move_child(node, 0)
	objects_changed.emit()
	return true


func all_objects() -> Array[String]:
	var out: Array[String] = []
	for key in _registry.keys():
		out.append(key)
	return out


func _apply_transform(object_id: String, apply: Callable) -> bool:
	var node := get_object_node(object_id)
	var data: Variant = _registry.get(object_id, null)
	if node == null or data == null:
		return false
	apply.call(node, data as Dictionary)
	objects_changed.emit()
	return true


func _apply_depth(pos: Vector3, depth: float) -> Vector3:
	return Vector3(pos.x, pos.y, pos.z + depth)


func _root_for(category: String) -> Node3D:
	var path := character_root
	if category == CATEGORY_BACKGROUND:
		path = background_root
	elif category == CATEGORY_PROP:
		path = prop_root
	if path.is_empty():
		return null
	return get_node_or_null(path) as Node3D


func _build_node(asset: EMCAssetData, id: String) -> Node3D:
	if asset.category == CATEGORY_PROP:
		var mi := MeshInstance3D.new()
		mi.name = id
		mi.mesh = _prop_mesh(asset)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = asset.metadata.get("color", Color(0.6, 0.6, 0.6))
		mi.material_override = mat
		return mi
	var sprite := Sprite3D.new()
	sprite.name = id
	sprite.texture = _load_texture(asset)
	sprite.pixel_size = SPRITE_PIXEL_SIZE if asset.category == CATEGORY_CHARACTER else BACKDROP_PIXEL_SIZE
	if asset.category == CATEGORY_CHARACTER:
		sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	return sprite


func _prop_mesh(asset: EMCAssetData) -> Mesh:
	var shape: String = asset.metadata.get("shape", "box")
	if shape == "cylinder":
		# Godot 4.7 renamed CylinderMesh.radius -> top_radius/bottom_radius.
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.35
		cylinder.bottom_radius = 0.35
		cylinder.height = 0.9
		return cylinder
	var box := BoxMesh.new()
	box.size = Vector3(0.8, 0.9, 0.6)
	return box


func _load_texture(asset: EMCAssetData) -> Texture2D:
	if asset.path.is_empty() or not ResourceLoader.exists(asset.path):
		return null
	return ResourceLoader.load(asset.path, "Texture2D") as Texture2D