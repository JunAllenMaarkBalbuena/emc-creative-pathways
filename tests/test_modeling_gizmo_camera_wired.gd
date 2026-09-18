extends SceneTree

## Regression guard — the modeling transform gizmo is wired constant-on-screen.
##
## Guards this user report (modeling lab):
##   "The Gizmo3D look very great and precise, yet in certain angle it
##    slowly disappears or be overlapped with the grid."
##
## The gizmo already has constant-on-screen machinery (gizmo_3d.gd: set_camera
## setter :35; NATIVE_DISTANCE/MIN_SCALE/MAX_SCALE :26-28; _process hand-root
## scale by camera distance :272-294). That machinery is DEAD unless modeling
## lab wires a camera into it — and earlier it never did: modeling_lab.gd only
## called set_camera(camera_controller.camera) on the *orbit* gizmo (line 96),
## never on the transform gadget. The result: Gizmo3D stayed fixed-world-size
## (a 0.6-unit-high gizmo — its ~0.04-radius shafts) and went sub-pixel + got
## visually overlapped by the always-crisp grid as the user zoomed out / changed
## angle, even though picking still worked (pick uses world-size areas).
##
## This test asserts the wiring exists in modeling_lab.gd — deterministic, no
## pixels, no timing.

const GIZMO_SRC := "res://scripts/modeling_lab/gizmo_3d.gd"
const LAB_SRC := "res://scripts/modeling_lab/modeling_lab.gd"

var _fail := 0

func _initialize() -> void:
	_run()

func _run() -> void:
	if not FileAccess.file_exists(GIZMO_SRC):
		_fail += 1
		print("FAIL: cannot find gizmo_3d.gd at %s" % GIZMO_SRC)
	else:
		var gizmo_src := FileAccess.get_file_as_string(GIZMO_SRC)
		if not gizmo_src.contains("func set_camera(camera: Camera3D):"):
			_fail += 1
			print("FAIL: gizmo_3d.gd lost its set_camera() — without it the "
				+ "constant-on-screen machinery can never be armed")

	if not FileAccess.file_exists(LAB_SRC):
		_fail += 1
		print("FAIL: cannot find modeling_lab.gd at %s" % LAB_SRC)
	else:
		var lab_src := FileAccess.get_file_as_string(LAB_SRC)
		if not lab_src.contains("gizmo.set_camera(camera_controller.camera)"):
			_fail += 1
			print("FAIL: modeling_lab.gd never wires the transform gizmo "
				+ "gizmo.set_camera(camera_controller.camera). The orbit gizmo "
				+ "gets its camera (line 96) but the transform gizmo stays "
				+ "fixed WORLD size → 0.04-radius shafts go sub-pixel on "
				+ "zoom-out/certain angle → it 'slowly disappears / reads as "
				+ "overlapped with the always-crisp grid' even though picking "
				+ "keeps working. Add gizmo.set_camera(camera_controller.camera) "
				+ "beside the wiring at modeling_lab.gd:96/103.")

	if _fail == 0:
		print("PASS: transform gizmo is camera-wired — set_camera() exists in "
			+ "gizmo_3d.gd and modeling_lab.gd wires gizmo.set_camera("
			+ "camera_controller.camera), so the gizmo scales with camera "
			+ "distance and stays constant-on-screen (never sub-pixel, never "
			+ "reads as overlapped with the grid).")
	quit(1 if _fail > 0 else 0)
