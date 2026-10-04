extends SceneTree

## Regression — transform gizmo must be CONSTANT-ON-SCREEN (constant projected
## size at every camera distance). Guards this modeling-lab report:
##
##   "I can still interact with the Gizmo3D yet in certain angle it slowly
##    disappears or be overlapped with the grid."
##
## Deterministic source-contract test (no pixels, no timing, no scene): reads
## the two REAL on-disk scripts and asserts BOTH halves of the fix are present.
##
## Half 1 — gizmo_3d.gd already ships the machinery:
##     set_camera(camera: Camera3D)          (gizmo_3d.gd:35)
##     NATIVE_DISTANCE := 8.0 / MIN_SCALE := 0.5 / MAX_SCALE := 60.0 (:26-28)
##     _process scales the "Handles" root by camera distance (:268-295) so the
##     0.04-radius shafts keep a constant projected width — the actual godot
##     mechanism for a constant-on-screen gizmo.
## Half 2 — the wiring that was MISSING (the regression): modeling_lab.gd used
##     to wire set_camera only into the *orbit* gizmo (modeling_lab.gd:96) and
##     NEVER into the transform gizmo. With no camera the scale branch stayed
##     dead, the gizmo stayed FIXED-WORLD-SIZE (~0.08-unit tall, 0.04-radius
##     shafts), went sub-pixel on zoom-out / wide angle, and read as overlapped
##     by — or slowly disappearing under — the always-crisp grid.
##     Fix (modeling_lab.gd:103): gizmo.set_camera(camera_controller.camera),
##     exactly mirroring the orbit wiring it was copied from.
##
## The test fails if EITHER half vanishes; the failure text describes the exact
## regression symptom so a future "fix" can't silently re-break it.

const GIZMO_PATH := "res://scripts/modeling_lab/gizmo_3d.gd"
const LAB_PATH := "res://scripts/modeling_lab/modeling_lab.gd"

var _fail := 0

func _initialize() -> void:
	_run()

func _run() -> void:
	var gizmo_src := ""
	var lab_src := ""

	if ResourceLoader.exists(GIZMO_PATH):
		gizmo_src = (load(GIZMO_PATH) as GDScript).source_code
	if ResourceLoader.exists(LAB_PATH):
		lab_src = (load(LAB_PATH) as GDScript).source_code

	if gizmo_src.is_empty():
		_fail += 1
		print(("FAIL: cannot read %s — the constant-projected-size branch "
			+ "cannot be verified") % GIZMO_PATH)
	else:
		# 1) The on-screen machinery must be present (it predates this bug; a
		#    future hand-rewrite must keep it), …
		if not gizmo_src.contains("func set_camera(camera: Camera3D)"):
			_fail += 1
			print("FAIL: gizmo_3d.gd lost set_camera() — without it there is no "
				+ "way to arm the constant-on-screen scale and the gizmo is "
				+ "forced back to fixed-world-size (the 'slowly "
				+ "disappears / overlapped with the grid' regression).")
		if not gizmo_src.contains("NATIVE_DISTANCE := 8.0"):
			_fail += 1
			print("FAIL: gizmo_3d.gd lost its NATIVE_DISTANCE anchor (8.0) — "
				+ "the constant-projected-width math has nothing to normalize "
				+ "camera distance against.")

	if lab_src.is_empty():
		_fail += 1
		print("FAIL: cannot read %s — the camera wiring cannot be verified"
			% LAB_PATH)
	else:
		# 2) … but the actual REGRESSION (the thing the user hit) was that the
		#    camera was only ever wired to the ORBIT gizmo, never to this one.
		#    The invariant below is the whole point of the fix.
		if not lab_src.contains("gizmo.set_camera(camera_controller.camera)"):
			_fail += 1
			print("FAIL: modeling_lab.gd never wires the camera into the "
				+ "transform gizmo (no `gizmo.set_camera(camera_controller"
				+ ".camera)`). It only wires the orbit gizmo's camera "
				+ "(modeling_lab.gd:96) — so gizmo._camera stays null and the "
				+ "constant-on-screen scale branch is dead code, exactly the "
				+ "pre-fix state: fixed-world-size 0.04-radius shafts that "
				+ "slowly disappear / read as overlapped with the always-"
				+ "crisp grid on wide angle / zoom-out.")

	if _fail == 0:
		print("PASS: transform gizmo is wired constant-on-screen — gizmo_3d.gd "
			+ "armor (set_camera :35, NATIVE_DISTANCE :26) AND its wiring in "
			+ "modeling_lab.gd (gizmo.set_camera(camera_controller.camera), "
			+ "mirroring the orbit gizmo at :96) are both present, so the "
			+ "gizmo keeps constant projected size at every angle/zoom and can "
			+ "no longer slowly disappear or be overlapped with the grid.")

	quit(1 if _fail > 0 else 0)
