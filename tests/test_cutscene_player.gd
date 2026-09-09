extends Node

## Regression test: cutscene_player._next_frame() read `.duration` off a Texture2D
## (Array[Texture2D] _frames), crashing multi-frame PNG cutscenes.
## Root cause: frame durations were dropped when images were collected.

var _fail := 0

func _ready() -> void:
	var tree := get_tree()
	var cp_scene := load("res://scenes/cutscene_player.tscn") as PackedScene
	var cp := cp_scene.instantiate()
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

	if cp._frame_idx >= 2 or cp._is_playing == false:
		print("PASS: cutscene advanced through frames using per-frame durations")
	else:
		_fail = 1
		print("FAIL: cutscene stuck at frame %d, _is_playing=%s" % [cp._frame_idx, cp._is_playing])
	tree.quit(_fail)

func _make_texture(color: Color) -> Texture2D:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)