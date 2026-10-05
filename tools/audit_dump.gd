extends SceneTree

## Offline integrity audit. Loads every script, scene and resource in the
## project and records what the engine actually says about them, then dumps the
## per-scene node paths so NodePath references in scripts can be cross-checked
## against the real scene trees.
##
## Deliberately does NOT instantiate scenes or add them to the tree. Doing so
## would run _ready, which writes saves, triggers SceneTransition and mutates
## LevelProgression. An audit must not be able to change what it measures.
## PackedScene.get_state() gives the full node tree with no side effects.
##
## Run:
##   godot --headless --path <project> --script res://tools/audit_dump.gd
##
## Writes res://.godot/audit_dump.json (gitignored).

const SKIP_DIRS := [".godot", "addons", "vendor", "build", "dist", ".git", "export_templates", "feature_profiles", "script_templates", "text_editor_themes"]
const OUT_PATH := "res://.godot/audit_dump.json"
const SELF_PATH := "res://tools/audit_dump.gd"

var _load_failures: Array[Dictionary] = []
var _load_ok: Array[Dictionary] = []
var _scenes: Array[Dictionary] = []
var _scripts: Array[Dictionary] = []


## Deferred to the first _process() frame on purpose.
##
## ResourceLoader is not usable during _initialize(): the engine is still
## booting, and calling load() from there dies with "Condition ' !nc ' is true"
## plus an internal VM error on opcode 31. Doing the work one frame later is
## also what stops this script from being able to hang: a --script SceneTree
## that throws before quit() never exits, and an audit that hangs for an hour
## is worse than no audit.
var _pending := true


func _initialize() -> void:
	pass


func _process(_delta: float) -> bool:
	if not _pending:
		return true
	_pending = false
	_run()
	# Returning true quits the main loop. Belt and braces alongside the explicit
	# quit() at the end of _run(), so no failure path can leave this spinning.
	return true


func _run() -> void:
	var t0 := Time.get_ticks_msec()

	var gd_files := _collect("res://", ".gd")
	var tscn_files := _collect("res://", ".tscn")
	var tres_files := _collect("res://", ".tres")
	var shader_files := _collect("res://", ".gdshader")

	print("[audit] found %d .gd, %d .tscn, %d .tres, %d .gdshader" % [
		gd_files.size(), tscn_files.size(), tres_files.size(), shader_files.size()])

	# ---- Pass A: can the engine load each one at all? ----
	# A successful load proves every ext_resource path and uid inside resolves,
	# because Godot reports a broken dependency as a load failure. This is the
	# check that catches dead sub_resources and dangling uid references.
	for p in gd_files:
		_record_load(p, "GDScript")
	for p in shader_files:
		_record_load(p, "Shader")
	for p in tres_files:
		_record_load(p, "Resource")
	for p in tscn_files:
		_record_load(p, "PackedScene")

	# ---- Pass C: node tree per scene, for NodePath cross-checking ----
	for p in tscn_files:
		_dump_scene(p)

	var elapsed := Time.get_ticks_msec() - t0

	var out := {
		"elapsed_ms": elapsed,
		"counts": {
			"gd": gd_files.size(), "tscn": tscn_files.size(),
			"tres": tres_files.size(), "gdshader": shader_files.size(),
		},
		"load_ok": _load_ok,
		"load_failures": _load_failures,
		"scenes": _scenes,
		"scripts": _scripts,
	}

	var f := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if f == null:
		printerr("[audit] cannot write %s: %s" % [OUT_PATH, error_string(FileAccess.get_open_error())])
		quit(2)
		return
	f.store_string(JSON.stringify(out))
	f.close()

	print("[audit] load ok       : %d" % _load_ok.size())
	print("[audit] load FAILURES : %d" % _load_failures.size())
	print("[audit] scenes dumped : %d" % _scenes.size())
	print("[audit] elapsed       : %d ms" % elapsed)
	print("[audit] wrote %s" % OUT_PATH)
	quit(0)


## Try to load a resource and classify the result. Cache mode IGNORE so a
## previously-cached copy cannot mask a broken file on disk.
func _record_load(path: String, kind: String) -> void:
	# This script loads itself. CACHE_MODE_IGNORE forces a recompile, which
	# invalidates the running script's own function table partway through its
	# execution - the next call into it dies with an empty-name error, and the
	# whole engine can segfault. Skipping self is not optional.
	if path == SELF_PATH:
		print("[skip] %s  (self)" % path)
		return

	# Printed before the load, not after. A segfault inside ResourceLoader cannot
	# be caught from GDScript, so the last line printed before the crash is the
	# only way to identify the offending file.
	print("[load] %s  %s" % [kind, path])
	var res := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if res == null:
		_load_failures.append({"path": path, "kind": kind, "error": "load returned null"})
		print("[FAIL] %s  %s" % [kind, path])
		return

	var entry := {"path": path, "kind": kind}

	match kind:
		"GDScript":
			var s := res as GDScript
			if s == null:
				entry["error"] = "not a GDScript"
				_load_failures.append(entry)
				print("[FAIL] not a GDScript  %s" % path)
				return
			# A script that failed to compile still loads as an object, so
			# validity has to be asked for explicitly.
			if not s.can_instantiate() and not s.is_abstract():
				entry["error"] = "cannot instantiate (likely compile error)"
				_load_failures.append(entry)
				print("[FAIL] invalid script  %s" % path)
				return
			entry["class_name"] = s.get_global_name()
			entry["is_tool"] = s.is_tool()
			entry["base"] = s.get_instance_base_type()
			_scripts.append({
				"path": path,
				"class_name": s.get_global_name(),
				"base": s.get_instance_base_type(),
				"is_tool": s.is_tool(),
			})
		"PackedScene":
			var ps := res as PackedScene
			if ps == null:
				entry["error"] = "not a PackedScene"
				_load_failures.append(entry)
				print("[FAIL] not a PackedScene  %s" % path)
				return
			var st := ps.get_state()
			entry["node_count"] = st.get_node_count() if st != null else -1
			entry["can_instantiate"] = ps.can_instantiate()
			if not ps.can_instantiate():
				entry["error"] = "can_instantiate() == false"
				_load_failures.append(entry)
				print("[FAIL] cannot instantiate  %s" % path)
				return
		"Shader":
			if not (res as Shader).get_code().is_empty():
				entry["code_len"] = (res as Shader).get_code().length()

	_load_ok.append(entry)


## Dump a scene's node tree and, per node, the script attached to it plus that
## script's NodePath and unique-name literals. Pure introspection via
## SceneState; nothing is instantiated.
func _dump_scene(path: String) -> void:
	var ps := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if ps == null:
		return
	var st := ps.get_state()
	if st == null:
		_scenes.append({"path": path, "error": "get_state() returned null", "nodes": [], "scripts": []})
		return

	var nodes: Array[Dictionary] = []
	var script_entries: Array[Dictionary] = []

	for i in st.get_node_count():
		var np := st.get_node_path(i, false)
		var rec := {
			"idx": i,
			"path": String(np),
			"name": String(st.get_node_name(i)),
			"type": String(st.get_node_type(i)),
		}

		# Only the four accessors documented as stable across 4.x are used here.
		# SceneState.get_node_unique_name() and get_node_groups() were tried and
		# are not dependable in 4.7 - calling them aborts the whole run with
		# "Nonexistent utility function". Unique names are read from the scene
		# text instead, which cannot fail.
		nodes.append(rec)

		# Find the script property on this node.
		# SceneState has no get_node_properties() in 4.7; the accessor trio
		# get_node_property_count/name/value is the real API.
		var prop_count := st.get_node_property_count(i)
		for pi in prop_count:
			if String(st.get_node_property_name(i, pi)) != "script":
				continue
			var sv = st.get_node_property_value(i, pi)
			if sv == null:
				continue
			var spath := ""
			if sv is Script:
				spath = (sv as Script).resource_path
			elif sv is String:
				spath = String(sv)
			if spath == "":
				continue
			script_entries.append({
				"node_path": String(np),
				"script": spath,
				"literals": _extract_path_literals(spath),
			})
			break

	_scenes.append({
		"path": path,
		"node_count": st.get_node_count(),
		"nodes": nodes,
		"scripts": script_entries,
		"unique_names": _parse_unique_names(path),
	})


## Collect `unique_name_in_owner=true` node names straight from the scene text.
##
## Parsed rather than queried because SceneState does not expose a dependable
## accessor for this in 4.7, and a %Name that does not resolve is a null node
## reference at runtime rather than a load error - exactly the class of bug that
## only shows up when a player reaches that screen.
func _parse_unique_names(scene_path: String) -> Array[String]:
	var out: Array[String] = []
	if not FileAccess.file_exists(scene_path):
		return out
	var f := FileAccess.open(scene_path, FileAccess.READ)
	if f == null:
		return out
	var re_node := RegEx.new()
	re_node.compile("\\[node name=\"([^\"]+)\"[^\\]]*unique_name_in_owner=true")
	for line in f.get_as_text().split("\n"):
		var m := re_node.search(line)
		if m != null:
			out.append(m.get_string(1))
	f.close()
	return out


## Pull `$"Some/Path"` and `%UniqueName` literals out of a script's source.
##
## `%` is filtered carefully because it is also the modulo operator in GDScript.
## Unique-name access is written `%Name` with no space before it, whereas modulo
## is conventionally spaced `a % b`, so requiring a non-space before the `%`
## separates the two in practice.
func _extract_path_literals(script_path: String) -> Dictionary:
	var empty := {"dollar": [], "percent": []}
	if not FileAccess.file_exists(script_path):
		return empty
	var f := FileAccess.open(script_path, FileAccess.READ)
	if f == null:
		return empty
	var src := f.get_as_text()
	f.close()

	var dollar: Array[Dictionary] = []
	var percent: Array[Dictionary] = []

	var re_dollar := RegEx.new()
	re_dollar.compile("\\$\"([^\"]+)\"")
	for m in re_dollar.search_all(src):
		dollar.append({"path": m.get_string(1), "line": src.count("\n", 0, m.get_start()) + 1})

	var re_pct := RegEx.new()
	re_pct.compile("(?<!\\s)%([A-Za-z_][A-Za-z0-9_]*)")
	for m in re_pct.search_all(src):
		percent.append({"name": m.get_string(1), "line": src.count("\n", 0, m.get_start()) + 1})

	return {"dollar": dollar, "percent": percent}


## Recursively collect files under `dir` with the given extension, skipping
## vendored and generated trees.
func _collect(dir_path: String, ext: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if name.begins_with("."):
			name = d.get_next()
			continue
		var full := dir_path.path_join(name)
		if d.current_is_dir():
			if not SKIP_DIRS.has(name):
				out.append_array(_collect(full, ext))
		elif name.get_extension().to_lower() == ext.trim_prefix("."):
			out.append(full)
		name = d.get_next()
	d.list_dir_end()
	return out
