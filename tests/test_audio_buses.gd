extends SceneTree

## Regression test: the music slider must actually control background music.
## Root cause: the project has no audio bus layout (no [audio] section in
## project.godot, no res://default_bus_layout.tres), so the only bus that
## exists is "Master". SettingsManager.set_music_volume() wrote to a non-existent
## "Music" bus (get_bus_index == -1, silently ignored), and every AudioStreamPlayer
## whose bus was set to anything else fell back to "Master" at runtime.
## Result: master slider worked, music slider did nothing.

func _initialize() -> void:
	_run()

func _run() -> void:
	var fail := 0

	var music_idx := AudioServer.get_bus_index("Music")
	var sfx_idx := AudioServer.get_bus_index("SFX")
	var voice_idx := AudioServer.get_bus_index("Voice")
	if music_idx == -1:
		fail += 1
		print("FAIL: 'Music' audio bus does not exist")
	if sfx_idx == -1:
		fail += 1
		print("FAIL: 'SFX' audio bus does not exist")
	if voice_idx == -1:
		fail += 1
		print("FAIL: 'Voice' audio bus does not exist")

	var settings: Node = root.get_node_or_null("SettingsManager")
	if settings == null:
		fail += 1
		print("FAIL: SettingsManager autoload missing")
	else:
		var original: float = settings.get("music_volume")
		settings.call("set_music_volume", 0.05)
		if music_idx != -1:
			var db := AudioServer.get_bus_volume_db(music_idx)
			if db > -10.0:
				fail += 1
				print("FAIL: music slider did not lower the Music bus (db=%.2f)" % db)
		settings.call("set_music_volume", original)

	var checks := {
		"res://scenes/main_menu.tscn": "BGM",
		"res://scenes/world_demo.tscn": "BGM",
		"res://scenes/cutscene/cutscene_player.tscn": "BGMPlayer",
	}
	for path: String in checks:
		var scene := load(path) as PackedScene
		if scene == null:
			fail += 1
			print("FAIL: cannot load %s" % path)
			continue
		var inst := scene.instantiate()
		root.add_child(inst)
		await process_frame
		var player := inst.find_child(checks[path], true, false) as AudioStreamPlayer
		if player == null:
			fail += 1
			print("FAIL: %s has no AudioStreamPlayer named '%s'" % [path, checks[path]])
		elif player.bus != &"Music":
			fail += 1
			print("FAIL: %s.%s plays on bus '%s' instead of 'Music'" % [path, checks[path], player.bus])
		inst.queue_free()
		await process_frame

	if fail == 0:
		print("PASS: Music/SFX/Voice buses exist and all background music plays on the Music bus")
	quit(1 if fail > 0 else 0)