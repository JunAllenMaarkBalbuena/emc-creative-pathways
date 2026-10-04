extends SceneTree

## RED: Regression guard for the modeling-lab material "base color" render contract.
## Today material_manager.apply_to writes albedo_color (including .a) but NEVER
## toggles the material's transparency mode — so an RGBA base color is a lie:
## sliding alpha (or choosing the glass preset, albedo.a = 0.3) has zero visible
## effect; the surface stays fully opaque. For an honest color wheel the material
## must actually honor alpha:
##   albedo.a >= 0.999  -> TRANSPARENCY_DISABLED
##   albedo.a <  0.999  -> TRANSPARENCY_ALPHA
## Fails on current code (no transparency branch exists).


func _initialize() -> void:
	_run()


func _run() -> void:
	var fail := 0
	var mm := MaterialManager.new()
	var sel := MeshInstance3D.new()
	sel.mesh = BoxMesh.new()
	root.add_child(sel)
	await process_frame

	var opaque := mm.apply_to(sel, {albedo = Color(0.9, 0.9, 0.95)})
	var want_opaque := StandardMaterial3D.TRANSPARENCY_DISABLED
	if opaque and opaque.transparency == want_opaque:
		print("PASS: opaque albedo (alpha 1) stays TRANSPARENCY_DISABLED")
	else:
		fail += 1
		print("FAIL: opaque albedo got transparency=",
			opaque.transparency if opaque else -1,
			" expected DISABLED (", want_opaque, ")")

	var translucent := mm.apply_to(sel, {albedo = Color(1.0, 0.5, 0.5, 0.3)})
	var want_alpha := StandardMaterial3D.TRANSPARENCY_ALPHA
	if translucent and translucent.transparency == want_alpha:
		print("PASS: translucent albedo (alpha 0.3) enables TRANSPARENCY_ALPHA")
	else:
		fail += 1
		print("FAIL: alpha=0.3 got transparency=",
			translucent.transparency if translucent else -1,
			" expected ALPHA (", want_alpha, ")")

	var glass := mm.apply_to(sel, {albedo = Color(0.85, 0.9, 1.0, 0.3)})
	if glass and glass.transparency == want_alpha:
		print("PASS: glass preset alpha propagates to TRANSPARENCY_ALPHA")
	else:
		fail += 1
		print("FAIL: glass preset did not enable TRANSPARENCY_ALPHA")

	if fail == 0:
		print("PASS: base-color alpha is render-honest (opaque vs translucent)")
	quit(1 if fail > 0 else 0)
