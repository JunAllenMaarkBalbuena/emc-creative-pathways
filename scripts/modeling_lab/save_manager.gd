class_name SaveManager
extends RefCounted

const MODEL_DIR := "res://data/player_models/"

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
	var dir: DirAccess = DirAccess.open("res://")
	if dir:
		var _discarded_dir: Error = dir.make_dir_recursive("data/player_models")

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
	for child in object_container.get_children():
		if child is MeshInstance3D and not child.is_in_group("ghost_guides"):
			var mat: StandardMaterial3D = child.get_surface_override_material(0) as StandardMaterial3D
			var pd := PrimitiveSaveData.new()
			pd.type = PrimitiveSpawner.type_for_mesh(child.mesh)
			pd.node_name = child.name
			pd.position = child.position
			pd.rotation_degrees = child.rotation_degrees
			pd.scale = child.scale
			if child.get_parent() and child.get_parent() != object_container:
				pd.parent_name = child.get_parent().name
			if mat:
				pd.material_albedo = mat.albedo_color
				pd.material_metallic = mat.metallic
				pd.material_roughness = mat.roughness
			data.primitives.append(pd)
	return data

func restore_model(object_container: Node3D, data: ModelData, spawner: PrimitiveSpawner) -> Array[MeshInstance3D]:
	for child in object_container.get_children():
		if child is MeshInstance3D:
			child.queue_free()
	var created: Array[MeshInstance3D] = []
	var name_map: Dictionary = {}
	for pd in data.primitives:
		var mi := spawner.spawn(pd.type, object_container)
		mi.name = pd.node_name
		mi.position = pd.position
		mi.rotation_degrees = pd.rotation_degrees
		mi.scale = pd.scale
		var mat := StandardMaterial3D.new()
		mat.albedo_color = pd.material_albedo
		mat.metallic = pd.material_metallic
		mat.roughness = pd.material_roughness
		mi.set_surface_override_material(0, mat)
		created.append(mi)
		name_map[pd.node_name] = mi
	return created
