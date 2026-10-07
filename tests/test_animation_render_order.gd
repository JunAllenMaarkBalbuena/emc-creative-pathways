extends SceneTree

## Render-order mechanism contract (plan Task 1, approved B2).
##
## The gate runs every test with --headless, where the dummy renderer returns
## no viewport texture (get_texture() is null), so no committed test can
## assert *pixels*. This test pins the mechanism that produces visual order
## instead; the actual pixel flip was proven by a windowed throwaway probe
## during implementation (see the task ledger). What the probe observed:
## higher transparent-pass priority draws in front, independent of z, so
##   - player layer i      -> priority 16 * (i + 1)   (16, 32, 48, ...)
##   - starter scene nodes -> priority 0
##   - strictly monotonic, and player layers never collide with starters.
## The contract under test:
##   1. RenderOrder.layer_priority is monotonic and starts above STARTER_PRIORITY.
##   2. set_layer_priority actually writes GeometryInstance3D.render_priority
##      on the two renderable types the composition uses (Sprite3D, MeshInstance3D).
##   3. the mesh material helper puts layer meshes in the transparent pass with
##      the matching priority, so priority (not depth) rules their order.

func _init() -> void:
	var failures := _run()
	if failures.is_empty():
		print("PASS: render-order priority mechanism")
		quit(0)
	else:
		for f in failures:
			print("FAIL: ", f)
		quit(1)


func _run() -> Array[String]:
	var failures: Array[String] = []

	# 1. Priority mapping: player layer i -> 16*(i+1); starters -> 0.
	var starter := RenderOrder.STARTER_PRIORITY
	if starter != 0:
		failures.append("STARTER_PRIORITY expected 0, got %d" % starter)
	for i in 5:
		var p := RenderOrder.layer_priority(i)
		if p != RenderOrder.PRIORITY_STEP * (i + 1):
			failures.append("layer_priority(%d) expected %d, got %d" % [
				i, RenderOrder.PRIORITY_STEP * (i + 1), p])
		if p <= starter:
			failures.append("layer_priority(%d)=%d must exceed STARTER_PRIORITY" % [i, p])
		if i > 0 and p <= RenderOrder.layer_priority(i - 1):
			failures.append("layer_priority(%d)=%d not strictly above %d" % [
				i, p, RenderOrder.layer_priority(i - 1)])

	# 2. set_layer_priority writes the priority on the two renderable types the
	#    composition spawns: sprites on the instance, meshes on their
	#    (transparent-pass) material because MeshInstance3D has no instance
	#    render_priority in 4.7.
	var spr := Sprite3D.new()
	RenderOrder.set_layer_priority(spr, RenderOrder.layer_priority(2))
	if spr.render_priority != 48:
		failures.append("Sprite3D.render_priority expected 48, got %d" % spr.render_priority)
	RenderOrder.set_layer_priority(spr, starter)
	if spr.render_priority != 0:
		failures.append("Sprite3D.render_priority expected 0 (starter), got %d" % spr.render_priority)

	var mesh := MeshInstance3D.new()
	RenderOrder.set_layer_priority(mesh, RenderOrder.layer_priority(0))
	var mesh_mat := mesh.material_override as StandardMaterial3D
	if mesh_mat == null:
		failures.append("MeshInstance3D got no material_override after set_layer_priority")
	else:
		if mesh_mat.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA:
			failures.append("mesh material must be TRANSPARENCY_ALPHA (got %d)" % mesh_mat.transparency)
		if mesh_mat.render_priority != 16:
			failures.append("mesh material priority expected 16, got %d" % mesh_mat.render_priority)

	# 3. The material helper both enables the transparent pass AND carries the
	#    same priority, otherwise a mesh sorts like a depth-occluding opaque
	#    and its order is z-dependent (the bug B2 exists to prevent).
	var mat := StandardMaterial3D.new()
	RenderOrder.apply_to_material(mat, RenderOrder.layer_priority(3))
	if mat.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA:
		failures.append("layer mesh material must be TRANSPARENCY_ALPHA (got %d)" % mat.transparency)
	if mat.render_priority != 64:
		failures.append("layer mesh material priority expected 64, got %d" % mat.render_priority)

	# Keep the harness exit clean: free the nodes we built (ObjectDB leaks are
	# engine warnings the gate ignores, but "pristine output" means no leaks).
	spr.free()
	mesh.free()

	return failures