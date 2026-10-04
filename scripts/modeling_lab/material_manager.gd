class_name MaterialManager
extends RefCounted

const PRESETS := {
	"plastic": {albedo = Color(0.9, 0.9, 0.95), metallic = 0.0, roughness = 0.4},
	"metal": {albedo = Color(0.75, 0.75, 0.8), metallic = 0.9, roughness = 0.3},
	"wood": {albedo = Color(0.55, 0.35, 0.15), metallic = 0.0, roughness = 0.9},
	"stone": {albedo = Color(0.4, 0.4, 0.45), metallic = 0.0, roughness = 0.95},
	"glass": {albedo = Color(0.85, 0.9, 1.0, 0.3), metallic = 0.0, roughness = 0.0},
}

const PRESET_NAMES := ["plastic", "metal", "wood", "stone", "glass"]

func apply_to(node: MeshInstance3D, props: Dictionary) -> StandardMaterial3D:
	if not node:
		return null
	var mat := StandardMaterial3D.new()
	if props.has("albedo"):
		mat.albedo_color = props.albedo
		# An RGBA base-color wheel is only honest if the alpha it picks is
		# actually rendered as transparency. StandardMaterial3D ignores
		# albedo_color.a for opacity unless TRANSPARENCY_ALPHA is on, so mirror
		# the base color's own alpha into the render mode. Guarded by
		# tests/test_modeling_material_alpha_renders.gd.
		mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA \
			if props.get("albedo").a < 0.999 else StandardMaterial3D.TRANSPARENCY_DISABLED
	if props.has("metallic"): mat.metallic = props.metallic
	if props.has("roughness"): mat.roughness = props.roughness
	if props.has("emission"):
		mat.emission_enabled = true
		mat.emission = props.emission
	node.set_surface_override_material(0, mat)
	return mat

func apply_preset(preset_name: String, node: MeshInstance3D) -> bool:
	var name_lower := preset_name.to_lower()
	if not PRESETS.has(name_lower):
		return false
	apply_to(node, PRESETS[name_lower])
	return true

func get_presets() -> Array[String]:
	return PRESET_NAMES.duplicate()

func get_preset_props(name: String) -> Dictionary:
	return PRESETS.get(name.to_lower(), PRESETS["plastic"])

func read_from(node: MeshInstance3D) -> Dictionary:
	if not node:
		return {albedo = Color.WHITE, metallic = 0.0, roughness = 0.5}
	var mat: StandardMaterial3D = node.get_surface_override_material(0) as StandardMaterial3D
	if not mat:
		return {albedo = Color.WHITE, metallic = 0.0, roughness = 0.5}
	return {
		albedo = mat.albedo_color,
		metallic = mat.metallic,
		roughness = mat.roughness,
	}
