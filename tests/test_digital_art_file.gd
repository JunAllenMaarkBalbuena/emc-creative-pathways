extends SceneTree

## Regression test: FileManager._sanitize_filename() used c.is_valid_identifier(),
## which rejects digit-only chars, so names like "Art 2" saved as "Art_.tres".
## Root cause: identifier rules != safe-filename rules.

func _init() -> void:
	var code := _run()
	quit(code)

func _run() -> int:
	var fm := FileManager.new()
	var got := fm._sanitize_filename("My Art 2 v3")
	if got != "My_Art_2_v3":
		print("FAIL: sanitize 'My Art 2 v3' -> '%s' (expected 'My_Art_2_v3')" % got)
		return 1

	var artwork_name := "Sketch45"
	var data := DigitalArtData.new()
	data.artwork_name = artwork_name
	var path := fm.save_artwork(data, artwork_name)
	if path.is_empty():
		print("FAIL: save_artwork('Sketch45') failed")
		return 1
	if not path.ends_with("Sketch45.tres"):
		print("FAIL: save_artwork path '%s' lost digits" % path)
		return 1
	var loaded := fm.load_artwork(path)
	if loaded == null or loaded.artwork_name != "Sketch45":
		print("FAIL: round-trip load of 'Sketch45' failed")
		return 1
	fm.delete_artwork(path)

	print("PASS: FileManager preserves digits in filenames ('My_Art_2_v3', 'Sketch45')")
	return 0