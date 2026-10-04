class_name HierarchyManager
extends RefCounted

# Godot forbids "." in Node names (the engine replaces it with "_"), so the
# Blender-style "cube.001" form lives in this metadata key; `node.name` keeps
# the engine-sanitized twin ("cube_001").
const BLENDER_DISPLAY := &"blender_display"

static func display_of(node: Node) -> String:
	if node.has_meta(BLENDER_DISPLAY):
		return str(node.get_meta(BLENDER_DISPLAY))
	return node.name

static func set_blender_name(node: Node, display: String) -> void:
	node.name = display
	node.set_meta(BLENDER_DISPLAY, display)

static func assign_blender_name(container: Node, node: Node, base: String) -> String:
	var display := allocate_name(container, base)
	set_blender_name(node, display)
	return display

var _container: Node3D

func _init(container: Node3D):
	_container = container

func get_tree_data() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	_walk(_container, result, 0)
	return result

func _walk(node: Node, output: Array[Dictionary], depth: int):
	for child in node.get_children():
		if child is MeshInstance3D and not child.is_in_group("ghost_guides"):
			output.append({
				node = child,
				name = display_of(child),
				depth = depth,
				visible = child.visible,
				type = "MeshInstance3D"
			})
			_walk(child, output, depth + 1)
		elif child is Node3D and not child is MeshInstance3D and _has_mesh_descendant(child):
			output.append({
				node = child,
				name = display_of(child),
				depth = depth,
				visible = true,
				type = "Node3D"
			})
			_walk(child, output, depth + 1)

func _has_mesh_descendant(node: Node) -> bool:
	for c in node.get_children():
		if c is MeshInstance3D and not c.is_in_group("ghost_guides"):
			return true
		if _has_mesh_descendant(c):
			return true
	return false

# Blender-style name allocation: "cube" -> "cube.001" -> "cube.002" …
# Counters are per-base; a freed slot is reused (smallest free suffix).
# `extra_used` reserves additional display names (already handed out within a
# single multi-allocation transaction) so two members sharing a base receive
# distinct names even though neither is in the tree yet.
static func allocate_name(container: Node, base: String, extra_used: Dictionary = {}) -> String:
	var used := {}
	_collect_names(container, used)
	for name in extra_used:
		used[name] = true
	if not used.has(base):
		return base
	var n := 1
	while used.has(base + ".%03d" % n):
		n += 1
	return base + ".%03d" % n

static func _collect_names(node: Node, used: Dictionary):
	for child in node.get_children():
		used[display_of(child)] = true
		_collect_names(child, used)

# "cube.001" -> "cube"; "cube" -> "cube" (strips a trailing numeric suffix).
static func base_of(display: String) -> String:
	var idx := display.rfind(".")
	if idx > 0:
		var suffix := display.substr(idx + 1)
		if suffix.is_valid_int():
			return display.left(idx)
	return display

func reparent(child_node: Node3D, new_parent: Node3D) -> bool:
	if child_node == new_parent or child_node == _container:
		return false
	var old_parent: Node = child_node.get_parent()
	if old_parent == new_parent:
		return false
	old_parent.remove_child(child_node)
	new_parent.add_child(child_node)
	child_node.owner = _container.owner if _container.owner else _container
	return true

func reparent_preserve(child_node: Node3D, new_parent: Node3D) -> bool:
	if child_node == new_parent or child_node == _container:
		return false
	var old_parent: Node = child_node.get_parent()
	if old_parent == new_parent:
		return false
	var gt: Transform3D = child_node.global_transform
	old_parent.remove_child(child_node)
	new_parent.add_child(child_node)
	child_node.global_transform = gt
	child_node.owner = _container.owner if _container.owner else _container
	return true

func rename(node: Node, new_name: String) -> bool:
	if new_name.is_empty():
		return false
	node.name = new_name
	node.set_meta(BLENDER_DISPLAY, new_name)
	return true

func delete_node(node: Node):
	if node != _container:
		node.queue_free()

func set_visible(node: Node, val: bool):
	node.visible = val

func duplicate_node(node: Node3D) -> Node3D:
	var parent: Node = node.get_parent()
	var copy: Node3D = node.duplicate() as Node3D
	copy.position += Vector3(0.5, 0.5, 0.5)
	parent.add_child(copy)
	copy.owner = parent.owner if parent.owner else parent
	return copy

func get_container() -> Node3D:
	return _container

func find_node_by_name(name: String) -> Node3D:
	for child in _container.get_children():
		if child.name == name and child is MeshInstance3D:
			return child
		var found := _find_recursive(child, name)
		if found:
			return found
	return null

func _find_recursive(parent: Node, name: String) -> MeshInstance3D:
	for child in parent.get_children():
		if child.name == name and child is MeshInstance3D:
			return child
		if child.get_child_count() > 0:
			var found := _find_recursive(child, name)
			if found:
				return found
	return null
