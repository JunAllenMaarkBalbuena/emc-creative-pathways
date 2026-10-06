class_name SaveManager
extends RefCounted

const MODEL_DIR := "user://models/"

func _init():
	_ensure_dir()

func save_model(data: ModelData, name: String = "") -> String:
	_ensure_dir()
	if name.is_empty():
		name = data.model_name
		if name.is_empty():
			name = "untitled"
	var path := MODEL_DIR + _sanitize(name) + ".tres"
	data.creation_date = _timestamp()
	data.model_name = name
	data.resource_path = path
	var err := ResourceSaver.save(data, path)
	if err != OK:
		push_error("SaveManager: Failed to save model: ", err)
		return ""
	return path

func load_model(path: String) -> ModelData:
	if not ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as ModelData

func list_saved() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var dir: DirAccess = DirAccess.open(MODEL_DIR)
	if dir == null:
		return result
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while not fname.is_empty():
		if fname.ends_with(".tres"):
			result.append({
				path = MODEL_DIR + fname,
				name = fname.trim_suffix(".tres"),
			})
		fname = dir.get_next()
	dir.list_dir_end()
	result.sort_custom(func(a, b): return a.name < b.name)
	return result

func delete_model(path: String) -> bool:
	var dir: DirAccess = DirAccess.open(MODEL_DIR)
	if dir == null:
		return false
	return dir.remove(path.trim_prefix(MODEL_DIR)) == OK

func _ensure_dir():
	var dir: DirAccess = DirAccess.open("user://")
	if dir:
		var _discarded: Error = dir.make_dir_recursive("models")

func _sanitize(name: String) -> String:
	const KEEP := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"
	var result := ""
	for c in name:
		if c in KEEP:
			result += c
		elif c == " ":
			result += "_"
	return result

func _timestamp() -> String:
	var dt := Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d %02d:%02d" % [dt.year, dt.month, dt.day, dt.hour, dt.minute]

func capture_model(object_container: Node3D, model_name: String) -> ModelData:
	var data := ModelData.new()
	data.model_name = model_name
	_walk_capture(object_container, data.primitives, "")
	return data


## Depth-first pre-order serialization: parents always precede children, so
## rebuild can create the parent group before parenting members under it.
## `parent_display` is the display name of the group we are walking inside;
## it is stored on each entry's `parent_name` so hierarchy is preserved.
func _walk_capture(node: Node3D, output: Array, parent_display: String) -> void:
	for child in node.get_children():
		if child is MeshInstance3D and not child.is_in_group("ghost_guides"):
			output.append(_capture_mesh(child, parent_display))
		elif child is Node3D and not child is MeshInstance3D and _has_mesh_descendant(child):
			var group_display := HierarchyManager.display_of(child)
			output.append(_capture_group(child, parent_display))
			_walk_capture(child, output, group_display)


func _capture_mesh(mi: MeshInstance3D, parent_display: String) -> PrimitiveSaveData:
	var mat: StandardMaterial3D = mi.get_surface_override_material(0) as StandardMaterial3D
	var pd := PrimitiveSaveData.new()
	pd.node_type = PrimitiveSaveData.TYPE_MESH
	pd.type = PrimitiveSpawner.type_for_mesh(mi.mesh)
	pd.node_name = mi.name
	pd.display_name = HierarchyManager.display_of(mi)
	pd.position = mi.position
	# `rotation_degrees` and `scale` are denormalised copies kept for readability
	# and for the pre-`has_basis` path. On a sheared basis the `rotation_degrees`
	# getter is meaningless (it runs get_euler() on a non-orthonormal matrix, the
	# same 5h bug the commit path had) - which is exactly why `basis_rows` is the
	# authority and these two are not.
	pd.rotation_degrees = mi.rotation_degrees
	pd.scale = mi.scale
	pd.basis_rows = basis_to_rows(mi.basis)
	pd.has_basis = true
	pd.skew_enabled = mi.get_meta(&"skew_enabled", false)
	pd.parent_name = parent_display
	if mat:
		pd.material_albedo = mat.albedo_color
		pd.material_metallic = mat.metallic
		pd.material_roughness = mat.roughness
	return pd


func _capture_group(group: Node3D, parent_display: String) -> PrimitiveSaveData:
	var pd := PrimitiveSaveData.new()
	pd.node_type = PrimitiveSaveData.TYPE_GROUP
	pd.node_name = group.name
	pd.display_name = HierarchyManager.display_of(group)
	pd.position = group.position
	pd.rotation_degrees = group.rotation_degrees
	pd.scale = group.scale
	pd.basis_rows = basis_to_rows(group.basis)
	pd.has_basis = true
	pd.skew_enabled = group.get_meta(&"skew_enabled", false)
	pd.parent_name = parent_display
	return pd


## Serialize a basis as 9 floats, row-major, matching Godot's own text format so
## a hand-inspected .tres reads the same way the engine writes one.
static func basis_to_rows(b: Basis) -> PackedFloat32Array:
	var rows := PackedFloat32Array()
	rows.resize(9)
	var i := 0
	for r in 3:
		for c in 3:
			rows[i] = b[r][c]
			i += 1
	return rows


## The basis to restore. Prefers the exact stored one; falls back to
## rotation_degrees * scale for saves written before the basis field existed.
## Requires all 9 floats - a short or long array is a corrupt file, and silently
## reading half a basis would be worse than falling back to the legacy path.
static func basis_of(pd: PrimitiveSaveData) -> Basis:
	if pd.has_basis and pd.basis_rows.size() == 9:
		var b := Basis.IDENTITY
		var i := 0
		for r in 3:
			for c in 3:
				b[r][c] = pd.basis_rows[i]
				i += 1
		return b
	return Basis.from_euler(Vector3(
			deg_to_rad(pd.rotation_degrees.x),
			deg_to_rad(pd.rotation_degrees.y),
			deg_to_rad(pd.rotation_degrees.z))) * Basis.from_scale(pd.scale)


func _has_mesh_descendant(node: Node) -> bool:
	for c in node.get_children():
		if c is MeshInstance3D and not c.is_in_group("ghost_guides"):
			return true
		if _has_mesh_descendant(c):
			return true
	return false


func restore_model(object_container: Node3D, data: ModelData, spawner: PrimitiveSpawner) -> Array[MeshInstance3D]:
	var existing := object_container.get_children()
	for child in existing:
		child.free()
	var created: Array[MeshInstance3D] = []
	var name_map: Dictionary[String, Node3D] = {}
	for pd in data.primitives:
		var parent: Node3D = object_container
		if pd.parent_name != "" and name_map.has(pd.parent_name):
			parent = name_map[pd.parent_name]
		if pd.node_type == PrimitiveSaveData.TYPE_GROUP:
			var group := Node3D.new()
			HierarchyManager.set_blender_name(group, _display_or(pd))
			group.transform = Transform3D(basis_of(pd), pd.position)
			group.set_meta(&"skew_enabled", pd.skew_enabled)
			parent.add_child(group)
			group.owner = object_container.owner if object_container.owner else object_container
			name_map[_display_or(pd)] = group
		else:
			var mi := spawner.spawn(pd.type, parent)
			HierarchyManager.set_blender_name(mi, _display_or(pd))
			mi.transform = Transform3D(basis_of(pd), pd.position)
			var mat := StandardMaterial3D.new()
			mat.albedo_color = pd.material_albedo
			mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA \
				if pd.material_albedo.a < 0.999 else StandardMaterial3D.TRANSPARENCY_DISABLED
			mat.metallic = pd.material_metallic
			mat.roughness = pd.material_roughness
			mi.set_surface_override_material(0, mat)
			mi.set_meta(&"skew_enabled", pd.skew_enabled)
			created.append(mi)
	return created


func _display_or(pd: PrimitiveSaveData) -> String:
	if pd.display_name != "":
		return pd.display_name
	# Legacy saves predate display_name; fall back to the engine name.
	return pd.node_name


