extends SceneTree

## Guard: the modeling-lab ground grid must render in the OPAQUE pass so it
## depth-tests correctly against translucent objects added via the RGBA wheel.
##
## A spatial ShaderMaterial is classified transparent the moment its fragment
## function writes ALPHA at ALL (even a constant `ALPHA = 1.0;`). A transparent
## grid plane joins the transparency pass and depth-sorts against transparent
## objects; its huge AABB makes it overdraw a low-alpha cube sitting above it
## ("the grid overlaps the object"). The grid is fully opaque by design (its
## comment says it must receive drop shadows), so the guard requires the grid
## shader to never write ALPHA.
## Fails if shader code contains an ALPHA assignment in the fragment section.

func _initialize() -> void:
	_run()


func _run() -> void:
	var ws: Node3D = (load("res://scenes/modeling_lab/workspace.tscn") as PackedScene).instantiate()
	root.add_child(ws)
	await process_frame

	var plane := ws.get_node_or_null("GridPlane") as MeshInstance3D
	if plane == null:
		print("FAIL: workspace has no GridPlane")
		quit(1)
		return
	var mat := plane.material_override as ShaderMaterial
	if mat == null or mat.shader == null:
		print("FAIL: GridPlane has no grid shader material")
		quit(1)
		return

	var code: String = mat.shader.code
	var fragment_start := code.find("void fragment()")
	var fragment_body := code.substr(fragment_start) if fragment_start >= 0 else ""

	var writes_alpha := fragment_body.contains("ALPHA =")
	if writes_alpha:
		var line := 0
		for ln in fragment_body.split("\n"):
			line += 1
			if ln.contains("ALPHA ="):
				print("FAIL: grid shader assigns ALPHA in fragment (line ~", line,
					"): transparent pass -> can overdraw translucent objects")
		quit(1)
		return

	print("PASS: grid shader never writes ALPHA -> opaque pass (depth-safe vs translucent objects)")
	quit(0)