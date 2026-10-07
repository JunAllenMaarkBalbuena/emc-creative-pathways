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
## Fired whenever the composition stack (layer order) changes — the Layers
## docker and the save layer listen for it. Order is back-to-front: index 0
## is drawn behind everything, the last index in front.
signal layer_order_changed

const CATEGORY_CHARACTER := "character"
const CATEGORY_BACKGROUND := "background"
const CATEGORY_PROP := "prop"

## Challenge E: a prop counts as "near the action" inside this distance (in
## world units) of the character. The starter layout puts the workstation
## 1.2 units away, which satisfies it.
const NEAR_PROP_DISTANCE := 2.0

const SPRITE_PIXEL_SIZE := 0.01
const BACKDROP_PIXEL_SIZE := 0.02

@export_node_path("Node3D") var character_root: NodePath
@export_node_path("Node3D") var background_root: NodePath
@export_node_path("Node3D") var prop_root: NodePath

var _registry: Dictionary = {}   # id -> Dictionary
var _nodes: Dictionary = {}      # id -> Node3D
var _next_id := 1
var _selected_id := ""
## Composition stack: ids back-to-front (index 0 = behind). This is the
## painter's order — render priority follows it, independent of spatial z
## (B2, see RenderOrder). Insertion appends, so the newest object sits on top.
var _layer_order: Array[String] = []


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
		"display_name": asset.display_name,
		"element_type": "3d" if asset.category == CATEGORY_PROP else "2d",
		"locked": false,
	}
	_nodes[id] = node
	_layer_order.append(id)
	_apply_layer_priorities()
	objects_changed.emit()
	return id


func remove_object(object_id: String) -> bool:
	var node := get_object_node(object_id)
	if node == null:
		return false
	_registry.erase(object_id)
	_nodes.erase(object_id)
	_layer_order.erase(object_id)
	node.get_parent().remove_child(node)
	node.free()
	if _selected_id == object_id:
		_selected_id = ""
	_apply_layer_priorities()
	objects_changed.emit()
	layer_order_changed.emit()
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
	ndata["locked"] = false  # a clean copy is immediately reorderable
	_registry[new_id] = ndata
	_nodes[new_id] = dup
	_layer_order.append(new_id)
	_apply_layer_priorities()
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
	data["element_type"] = "3d" if asset.category == CATEGORY_PROP else "2d"
	_nodes[object_id] = replacement
	_apply_layer_priorities()
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


## --- Composition layer stack -------------------------------------------------
## Back-to-front ids (index 0 = behind). The layer stack is the painter's
## order: every registered object renders through the transparent pass with a
## priority derived from its index (RenderOrder.layer_priority), so ordering
## is z- and camera-independent.

## Copy of the stack, back-to-front, so callers cannot mutate the source.
func layer_order() -> Array[String]:
	return _layer_order.duplicate()


## Index of `object_id` in the stack, or -1 if unknown.
func layer_index(object_id: String) -> int:
	return _layer_order.find(object_id)


## Move `object_id` to `to_index` (clamped). Returns false when the id is
## unknown, its layer is locked, or the move would be a no-op. Other layers
## may be reordered around a locked one; only the moved layer's own lock
## blocks the move.
func reorder_layer(object_id: String, to_index: int) -> bool:
	var index := _layer_order.find(object_id)
	if index == -1:
		return false
	var data: Variant = _registry.get(object_id, null)
	if data == null or data.get("locked", false):
		return false
	var target := clampi(to_index, 0, _layer_order.size() - 1)
	if target == index:
		return false
	_layer_order.remove_at(index)
	_layer_order.insert(target, object_id)
	_commit_order()
	return true


## Move toward the front (+1 step).
func move_layer_up(object_id: String) -> bool:
	var index := _layer_order.find(object_id)
	if index == -1:
		return false
	return reorder_layer(object_id, index + 1)


## Move toward the back (-1 step).
func move_layer_down(object_id: String) -> bool:
	var index := _layer_order.find(object_id)
	if index == -1:
		return false
	return reorder_layer(object_id, index - 1)


## Jump to the very front (top of the stack).
func layer_to_front(object_id: String) -> bool:
	var index := _layer_order.find(object_id)
	if index == -1:
		return false
	return reorder_layer(object_id, _layer_order.size() - 1)


## Jump to the very back (bottom of the stack).
func layer_to_back(object_id: String) -> bool:
	var index := _layer_order.find(object_id)
	if index == -1:
		return false
	return reorder_layer(object_id, 0)


## Alias of move_layer_up (+1 step, explicitly named for the panel row).
func layer_forward(object_id: String) -> bool:
	return move_layer_up(object_id)


## Alias of move_layer_down (-1 step, explicitly named for the panel row).
func layer_backward(object_id: String) -> bool:
	return move_layer_down(object_id)


## Rename the layer's display label. Returns false for an unknown id; the
## empty string is allowed (the panel falls back to the id). Note: the null
## guard happens BEFORE the `as Dictionary` cast — casting a null Variant to
## a built-in type throws an invalid-cast error in Godot 4.7.
func rename_layer(object_id: String, name: String) -> bool:
	var data: Variant = _registry.get(object_id, null)
	if data == null:
		return false
	(data as Dictionary)["display_name"] = name
	objects_changed.emit()
	return true


## Lock/unlock a layer. A locked layer refuses every reorder op (nothing
## crashes; the op just returns false).
func set_layer_locked(object_id: String, locked: bool) -> bool:
	var data: Variant = _registry.get(object_id, null)
	if data == null:
		return false
	(data as Dictionary)["locked"] = locked
	objects_changed.emit()
	return true


## The Layers docker's data source: one summary per stack entry, in stack
## order, carrying everything the panel's rows need to render.
func layer_summaries() -> Array:
	var out: Array = []
	for object_id in _layer_order:
		var data := _registry.get(object_id, {}) as Dictionary
		var node := get_object_node(object_id)
		var label := str(data.get("display_name", ""))
		if label.is_empty():
			label = object_id
		out.append({
			"id": object_id,
			"display_name": label,
			"element_type": str(data.get("element_type", "2d")),
			"visible": node.visible if node != null else true,
			"locked": bool(data.get("locked", false)),
			"selected": _selected_id == object_id,
		})
	return out


## Re-apply render priorities so they match the current stack exactly:
## index i -> RenderOrder.layer_priority(i). Called after every add/remove/
## duplicate/replace/order change. Skips ids whose node is missing (never
## crashes).
func _apply_layer_priorities() -> void:
	for i in _layer_order.size():
		var node := get_object_node(_layer_order[i])
		if node != null:
			RenderOrder.set_layer_priority(node, RenderOrder.layer_priority(i))


## After an order change: priorities first, then notify the panels and the
## save layer with both signals (order consumers need layer_order_changed;
## everything else refreshes on objects_changed).
func _commit_order() -> void:
	_apply_layer_priorities()
	objects_changed.emit()
	layer_order_changed.emit()


## Challenge E live source: measure the registered scene (not the authored
## starter nodes). "Character before background" means the character's z sits
## closer to the camera than the background's (the camera looks down -z, so
## z is "in front"). "Near prop" means the nearest registered prop is within
## NEAR_PROP_DISTANCE of the character. Returns a plain Dictionary so the
## caller can hand the two booleans to AssignmentManager.stage_scene_ok.
func staging_state() -> Dictionary:
	var ids := all_objects()
	var char_pos := Vector3.ZERO
	var has_char := false
	var bg_z := 0.0
	var has_bg := false
	for object_id in ids:
		var data := get_object(object_id)
		var category := str(data.get("category", ""))
		match category:
			CATEGORY_CHARACTER:
				if not has_char:
					char_pos = data.get("position", Vector3.ZERO) as Vector3
					has_char = true
			CATEGORY_BACKGROUND:
				if not has_bg:
					bg_z = (data.get("position", Vector3.ZERO) as Vector3).z
					has_bg = true
	var prop_near := false
	if has_char:
		var nearest := INF
		for object_id in ids:
			var data := get_object(object_id)
			if str(data.get("category", "")) == CATEGORY_PROP:
				var prop_pos := data.get("position", Vector3.ZERO) as Vector3
				nearest = minf(nearest, prop_pos.distance_to(char_pos))
		prop_near = nearest <= NEAR_PROP_DISTANCE
	return {
		"character_before_background": has_char and has_bg and char_pos.z > bg_z,
		"near_prop": prop_near,
	}


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