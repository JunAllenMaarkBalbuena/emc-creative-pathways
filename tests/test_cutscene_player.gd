extends Node

## Regression tests for cutscene_player.gd:
## 1. _next_frame() read `.duration` off a Texture2D, crashing multi-frame cutscenes.
## 2. _finish() never cleared the last frame/hid the layer, so after a door
##    entry cutscene (player kept at tree root) the final frame stayed on screen.

var _fail := 0

func _ready() -> void:
	var tree := get_tree()

	# --- Natural end: must play through and then clean up the screen. ---
	var cp := (load("res://scenes/cutscene/cutscene_player.tscn") as PackedScene).instantiate()
	add_child(cp)
	await tree.process_frame

	var def := CutsceneDefinition.new()
	def.cutscene_id = "test"
	var fa := CutsceneFrame.new()
	fa.image = _make_texture(Color.RED)
	fa.duration = 0.1
	var fb := CutsceneFrame.new()
	fb.image = _make_texture(Color.BLUE)
	fb.duration = 0.15
	def.frames = [fa, fb]

	cp.play(def)
	await tree.create_timer(0.5).timeout
	if cp._frame_idx < 2 or cp._is_playing:
		_fail = 1
		print("FAIL: cutscene stuck at frame %d, _is_playing=%s" % [cp._frame_idx, cp._is_playing])
	elif cp.visible:
		_fail = 1
		print("FAIL: after natural end the cutscene layer is still visible (last frame stuck on screen)")
	elif cp.frame_rect.texture != null:
		_fail = 1
		print("FAIL: after natural end the last frame texture is still set")

	# --- Skip path: must also clean up the screen. ---
	var cp2 := (load("res://scenes/cutscene/cutscene_player.tscn") as PackedScene).instantiate()
	add_child(cp2)
	await tree.process_frame
	var def2 := CutsceneDefinition.new()
	def2.cutscene_id = "test2"
	def2.frames = [fa, fb]
	cp2.play(def2)
	await tree.create_timer(0.15).timeout
	if not cp2._is_playing:
		_fail = 1
		print("FAIL: skip test cutscene never started")
	cp2.skip()
	if cp2.visible:
		_fail = 1
		print("FAIL: after skip the cutscene layer is still visible")
	if cp2.frame_rect.texture != null:
		_fail = 1
		print("FAIL: after skip the last frame texture is still set")

	if _fail == 0:
		print("PASS: cutscene clean-up on natural end and on skip")
	tree.quit(_fail)

func _make_texture(color: Color) -> Texture2D:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)