extends SceneTree

## Regression test: the modeling workspace must render an actual ground grid
## (Blender/Godot-editor style), not a plain flat plane. The GridPlane must
## carry a ShaderMaterial running the grid shader with exposed tuning uniforms
## (minor/major spacing and colored X/Z axes).

func _initialize() -> void:
	_run()

func _run() -> void:
	var fail := 0
	var ws: Node3D = (load("res://scenes/modeling_lab/workspace.tscn") as PackedScene).instantiate()
	root.add_child(ws)
	await process_frame

	var plane := ws.get_node_or_null("GridPlane") as MeshInstance3D
	if plane == null:
		fail += 1
		print("FAIL: workspace has no GridPlane")
		quit(1)
		return

	var mat := plane.material_override as ShaderMaterial
	if mat == null or mat.shader == null:
		fail += 1
		print("FAIL: GridPlane has no grid shader material (it is a plain flat plane)")
		quit(1)
		return

	if not mat.shader.resource_path.ends_with("grid_shader.gdshader"):
		fail += 1
		print("FAIL: GridPlane material shader is not the grid shader (%s)" % mat.shader.resource_path)

	var names: Array[String] = []
	for u in mat.shader.get_shader_uniform_list():
		names.append(u.get("name", ""))
	for expected in ["grid_minor", "grid_major", "axis_color_x", "axis_color_z", "line_color", "base_color"]:
		if not expected in names:
			fail += 1
			print("FAIL: grid shader is missing uniform '%s'" % expected)

	if not is_equal_approx(mat.get_shader_parameter("grid_minor"), 1.0):
		fail += 1
		print("FAIL: grid_minor should be 1.0 on the scene material")
	if not is_equal_approx(mat.get_shader_parameter("grid_major"), 5.0):
		fail += 1
		print("FAIL: grid_major should be 5.0 on the scene material")

	var base_col: Color = mat.get_shader_parameter("base_color")
	if base_col.a < 1.0:
		fail += 1
		print("FAIL: grid base should be opaque so it receives drop shadows")

	if fail == 0:
		print("PASS: GridPlane renders a real ground grid (shader + tuning uniforms)")
	quit(1 if fail > 0 else 0)