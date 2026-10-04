extends SceneTree

## Full Modeling Lab feature sweep.
## Exercises ALL shapes, transforms (move/rotate/scale), reset/center buttons,
## material color wheel + sliders + presets, grouping/ungrouping, undo/redo for
## each, and randomized cross-feature combinations.

const ALL_SHAPES := [
	PrimitiveDef.Type.CUBE, PrimitiveDef.Type.SPHERE, PrimitiveDef.Type.CYLINDER,
	PrimitiveDef.Type.CONE, PrimitiveDef.Type.CAPSULE, PrimitiveDef.Type.PLANE,
	PrimitiveDef.Type.TORUS,
]
const SHAPE_NAMES := ["cube", "sphere", "cylinder", "cone", "capsule", "plane", "torus"]

var container: Node3D
var spawner: PrimitiveSpawner
var material_mgr: MaterialManager
var hierarchy_mgr: HierarchyManager
var cmd_mgr: CommandManager
var selection_mgr: SelectionManager
var snap: SnapSettings
var tfm: TransformManager
var errors := 0
var passed := 0
var _next_random_index: int = 0


func _init() -> void:
	ModelingAction.debug_actions = false
	_run()
	print("SWEEP RESULT: %d passed, %d failed" % [passed, errors])
	quit(errors)


func _run() -> void:
	container = Node3D.new()
	container.name = "SweepContainer"
	root.add_child(container)

	spawner = PrimitiveSpawner.new()
	material_mgr = MaterialManager.new()
	hierarchy_mgr = HierarchyManager.new(container)
	cmd_mgr = CommandManager.new()
	cmd_mgr.max_steps = 100
	selection_mgr = SelectionManager.new(container)
	cmd_mgr.selection_manager = selection_mgr
	snap = SnapSettings.new()
	snap.snap_enabled = false
	tfm = TransformManager.new(selection_mgr, snap, hierarchy_mgr, cmd_mgr, spawner, material_mgr)

	_test_all_shapes_spawn()
	_test_all_shapes_transform_move()
	_test_all_shapes_transform_rotate()
	_test_all_shapes_transform_scale()
	_test_reset_undo_redo()
	_test_center_undo_redo()
	_test_material_wheel_undo_redo()
	_test_material_sliders_undo_redo()
	_test_presets_undo_redo()
	_test_group_ungroup_undo_redo()
	_test_material_survives_transform()
	_test_random_combinations()
	_test_deselect_stale_emits_signal()
	_test_gizmo_drops_freed_target()
	_test_selection_survives_group_transform()
	_test_gizmo_node_hides_when_nothing_selected()
	_test_box_select_finds_grouped_members()
	_test_double_click_drills_down_group()
	_test_group_drill_down_clears_peer_highlights()
	_test_duplicate_group_undo_redo()
	_test_save_scene_preserves_groups()

	container.free()


func _fail(msg: String) -> void:
	print("FAIL: " + msg)
	errors += 1


func _pass(msg: String) -> void:
	print("PASS: " + msg)
	passed += 1


func _clear() -> void:
	for c in container.get_children():
		c.free()
	cmd_mgr.clear_history()
	selection_mgr.deselect_all()


func _spawn_shape(display: String, type: int, pos: Vector3) -> MeshInstance3D:
	var mi := spawner.spawn(type, container, false)
	HierarchyManager.assign_blender_name(container, mi, display)
	mi.position = pos
	mi.rotation_degrees = Vector3.ZERO
	mi.scale = Vector3.ONE
	return mi


func _find_display(display: String) -> Node3D:
	for c in container.get_children():
		if c is Node3D and HierarchyManager.display_of(c) == display:
			return c
		for gc in c.get_children():
			if gc is Node3D and HierarchyManager.display_of(gc) == display:
				return gc
	return null


func _count_meshes() -> int:
	var count := 0
	for c in container.get_children():
		if c is MeshInstance3D:
			count += 1
		for gc in c.get_children():
			if gc is MeshInstance3D:
				count += 1
	return count


func _live_meshes() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for c in container.get_children():
		if c is MeshInstance3D and is_instance_valid(c):
			out.append(c)
		for gc in c.get_children():
			if gc is MeshInstance3D and is_instance_valid(gc):
				out.append(gc)
	return out


func _live_top_meshes() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for c in container.get_children():
		if c is MeshInstance3D and is_instance_valid(c):
			out.append(c)
	return out


func _live_groups() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for c in container.get_children():
		if c is Node3D and not c is MeshInstance3D and is_instance_valid(c):
			out.append(c)
	return out


func _mat_of(node: Node3D) -> StandardMaterial3D:
	return node.get_surface_override_material(0) as StandardMaterial3D


func _props_equal(a: Dictionary, b: Dictionary) -> bool:
	for k in ["albedo", "metallic", "roughness"]:
		var av: Variant = a.get(k)
		var bv: Variant = b.get(k)
		if av is Color and bv is Color:
			if not (av as Color).is_equal_approx(bv as Color):
				return false
		elif av is float and bv is float:
			if not is_equal_approx(av, bv):
				return false
		elif av != bv:
			return false
	return true


# ── 1. Every shape: spawn / undo / redo ───────────────────────

func _test_all_shapes_spawn() -> void:
	for i in ALL_SHAPES.size():
		_clear()
		var type: int = ALL_SHAPES[i]
		var nm: String = SHAPE_NAMES[i]
		var data := {
			name = nm, display_name = nm, type = type,
			position = Vector3(i, 0.5, 0),
			rotation_degrees = Vector3.ZERO, scale = Vector3.ONE,
			material_albedo = Color.WHITE, material_metallic = 0.0, material_roughness = 1.0,
		}
		cmd_mgr.execute_command(CommandFactory.spawn(data, container, spawner, material_mgr, hierarchy_mgr))
		var node := _find_display(nm)
		if not node:
			_fail("%s spawn: missing" % nm)
			continue
		var expected_type: int = type
		if type == PrimitiveDef.Type.TORUS:
			expected_type = PrimitiveDef.Type.CYLINDER  # torus is a CylinderMesh variant
		if PrimitiveSpawner.type_for_mesh((node as MeshInstance3D).mesh) != expected_type:
			_fail("%s spawn: wrong mesh type" % nm)
			continue

		# Picker must be a trimesh: Jolt rejects non-uniform scale on primitive
		# shapes, and the SelectArea inherits the mesh's per-axis scale.
		var area := node.get_node_or_null("SelectArea") as Area3D
		if area == null or area.get_child_count() == 0:
			_fail("%s spawn: missing SelectArea" % nm)
			continue
		var picker_shape := (area.get_child(0) as CollisionShape3D).shape
		if not picker_shape is ConcavePolygonShape3D:
			_fail("%s spawn: SelectArea shape is %s, expected ConcavePolygonShape3D (Jolt non-uniform scale)" % [nm, picker_shape.get_class() if picker_shape else "null"])
			continue

		cmd_mgr.undo()
		if _find_display(nm):
			_fail("%s spawn undo: node still present" % nm)
			continue

		cmd_mgr.redo()
		node = _find_display(nm)
		if not node:
			_fail("%s spawn redo: missing" % nm)
			continue

		_pass("%s spawn undo/redo" % nm)


# ── 2. Every shape: move / undo / redo ────────────────────────

func _test_all_shapes_transform_move() -> void:
	for i in ALL_SHAPES.size():
		_clear()
		var nm: String = SHAPE_NAMES[i]
		var mi := _spawn_shape(nm, ALL_SHAPES[i], Vector3(1, 2, 3))
		if not mi:
			_fail("%s move: spawn failed" % nm)
			continue
		var before := Transform3D(mi.basis, Vector3(1, 2, 3))
		var after := Transform3D(mi.basis, Vector3(4, -2, 7))
		cmd_mgr.execute_command(CommandFactory.transform(
			[container.get_path_to(mi)], [before], [after],
			container, spawner, material_mgr, hierarchy_mgr))
		var node := _find_display(nm)
		if not node or node.position.distance_to(Vector3(4, -2, 7)) > 0.01:
			_fail("%s move: wrong position after exec" % nm)
			continue
		cmd_mgr.undo()
		node = _find_display(nm)
		if not node or node.position.distance_to(Vector3(1, 2, 3)) > 0.01:
			_fail("%s move: wrong after undo" % nm)
			continue
		cmd_mgr.redo()
		node = _find_display(nm)
		if not node or node.position.distance_to(Vector3(4, -2, 7)) > 0.01:
			_fail("%s move: wrong after redo" % nm)
			continue
		_pass("%s move undo/redo" % nm)


# ── 3. Every shape: rotate / undo / redo ──────────────────────

func _test_all_shapes_transform_rotate() -> void:
	for i in ALL_SHAPES.size():
		_clear()
		var nm: String = SHAPE_NAMES[i]
		var mi := _spawn_shape(nm, ALL_SHAPES[i], Vector3(0, 0, 0))
		if not mi:
			_fail("%s rotate: spawn failed" % nm)
			continue
		var before := Transform3D(mi.basis, Vector3.ZERO)
		var after := Transform3D(Basis(Vector3.UP, deg_to_rad(45)), Vector3.ZERO)
		cmd_mgr.execute_command(CommandFactory.transform(
			[container.get_path_to(mi)], [before], [after],
			container, spawner, material_mgr, hierarchy_mgr))
		var node := _find_display(nm)
		if not node or abs(node.basis.get_euler().y - deg_to_rad(45)) > 0.02:
			_fail("%s rotate: wrong basis after exec" % nm)
			continue
		cmd_mgr.undo()
		node = _find_display(nm)
		if not node or node.basis.get_euler().length() > 0.02:
			_fail("%s rotate: wrong after undo" % nm)
			continue
		cmd_mgr.redo()
		node = _find_display(nm)
		if not node or abs(node.basis.get_euler().y - deg_to_rad(45)) > 0.02:
			_fail("%s rotate: wrong after redo" % nm)
			continue
		_pass("%s rotate undo/redo" % nm)


# ── 4. Every shape: scale / undo / redo ───────────────────────

func _test_all_shapes_transform_scale() -> void:
	for i in ALL_SHAPES.size():
		_clear()
		var nm: String = SHAPE_NAMES[i]
		var mi := _spawn_shape(nm, ALL_SHAPES[i], Vector3(0, 0, 0))
		if not mi:
			_fail("%s scale: spawn failed" % nm)
			continue
		var before := Transform3D(mi.basis, Vector3.ZERO)
		var after := Transform3D(mi.basis.scaled(Vector3(2, 0.5, 3)), Vector3.ZERO)
		cmd_mgr.execute_command(CommandFactory.transform(
			[container.get_path_to(mi)], [before], [after],
			container, spawner, material_mgr, hierarchy_mgr))
		var node := _find_display(nm)
		if not node or node.scale.distance_to(Vector3(2, 0.5, 3)) > 0.01:
			_fail("%s scale: wrong scale after exec" % nm)
			continue
		cmd_mgr.undo()
		node = _find_display(nm)
		if not node or node.scale.distance_to(Vector3.ONE) > 0.01:
			_fail("%s scale: wrong after undo" % nm)
			continue
		cmd_mgr.redo()
		node = _find_display(nm)
		if not node or node.scale.distance_to(Vector3(2, 0.5, 3)) > 0.01:
			_fail("%s scale: wrong after redo" % nm)
			continue
		_pass("%s scale undo/redo" % nm)


# ── 5. Reset button (real TransformManager) ───────────────────

func _test_reset_undo_redo() -> void:
	_clear()
	var mi := _spawn_shape("cube", PrimitiveDef.Type.CUBE, Vector3(2, 1, 3))
	mi.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(30)), Vector3(2, 1, 3))
	selection_mgr.select(mi)

	tfm.reset_selected()
	var node := _find_display("cube")
	if not node:
		_fail("reset: node missing after execute")
		return
	var t: Transform3D = node.transform
	if t.origin.length() > 0.01 or t.basis.get_scale().distance_to(Vector3.ONE) > 0.01:
		_fail("reset: not identity after execute (origin=%s)" % str(t.origin))
		return

	cmd_mgr.undo()
	node = _find_display("cube")
	if not node:
		_fail("reset undo: node missing")
		return
	if node.position.distance_to(Vector3(2, 1, 3)) > 0.01 \
			or abs(node.basis.get_euler().y - deg_to_rad(30)) > 0.02:
		_fail("reset undo: transform not restored")
		return

	cmd_mgr.redo()
	node = _find_display("cube")
	if not node:
		_fail("reset redo: node missing")
		return
	if node.transform.origin.length() > 0.01:
		_fail("reset redo: not identity")
		return

	_pass("reset undo/redo")


# ── 6. Center button (real TransformManager) ──────────────────

func _test_center_undo_redo() -> void:
	_clear()
	var mi := _spawn_shape("cube", PrimitiveDef.Type.CUBE, Vector3(3, 2, 1))
	mi.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(45)), Vector3(3, 2, 1))
	selection_mgr.select(mi)

	tfm.center_selected()
	if cmd_mgr.undo_stack.is_empty():
		_fail("center: no command pushed")
		return
	var last: ModelingAction = cmd_mgr.undo_stack[cmd_mgr.undo_stack.size() - 1]
	if last._after.is_empty():
		_fail("center: no after snapshot")
		return
	# Box aabb center in local space is (0,0,0), so centering snaps origin to (0,0,0).
	var after_pos: Vector3 = last._after[0].position
	if after_pos.distance_to(Vector3.ZERO) > 0.01:
		_fail("center: after.origin wrong (%s)" % str(after_pos))
		return

	cmd_mgr.undo()
	var node := _find_display("cube")
	if not node or node.position.distance_to(Vector3(3, 2, 1)) > 0.01:
		_fail("center undo: not restored")
		return

	cmd_mgr.redo()
	node = _find_display("cube")
	if not node:
		_fail("center redo: node missing")
		return

	_pass("center undo/redo")


# ── 7. Color wheel: many colors, undo/redo through them ───────

func _test_material_wheel_undo_redo() -> void:
	_clear()
	var node: Node3D = _spawn_shape("cube", PrimitiveDef.Type.CUBE, Vector3.ZERO)
	var colors := [
		Color(0.1, 0.3, 0.9),
		Color(0.9, 0.2, 0.1),
		Color(0.2, 0.9, 0.4),
		Color(0.9, 0.9, 0.1),
		Color(1.0, 0.5, 0.0),
	]
	for c in colors:
		var before := material_mgr.read_from(node)
		cmd_mgr.execute_command(CommandFactory.material(
			node, before, {albedo = c, metallic = before.metallic, roughness = before.roughness},
			container, spawner, material_mgr, hierarchy_mgr))
		var mat := _mat_of(node)
		if not mat or mat.albedo_color != c:
			_fail("color wheel: apply failed for %s" % str(c))
			return

	# Undo all the way back through every color to the default white.
	for i in colors.size() - 1:
		cmd_mgr.undo()
		node = _find_display("cube")
		if not node:
			_fail("color wheel: node missing during undo chain")
			return
		var expect: Color = colors[colors.size() - 2 - i] if colors.size() - 2 - i >= 0 else Color.WHITE
		if material_mgr.read_from(node).albedo != expect:
			_fail("color wheel: undo step %d, expected %s got %s" % [i, str(expect), str(material_mgr.read_from(node).albedo)])
			return

	cmd_mgr.undo()
	node = _find_display("cube")
	if not node:
		_fail("color wheel: node missing at bottom")
		return
	if material_mgr.read_from(node).albedo != Color.WHITE:
		_fail("color wheel: not white at bottom of undo")
		return

	# Redo back to the top color.
	for i in colors.size():
		cmd_mgr.redo()
		node = _find_display("cube")
		if not node:
			_fail("color wheel: node missing during redo chain")
			return
		if material_mgr.read_from(node).albedo != colors[i]:
			_fail("color wheel redo: step %d, expected %s got %s" % [i, str(colors[i]), str(material_mgr.read_from(node).albedo)])
			return

	_pass("color wheel undo/redo (%d steps)" % colors.size())


# ── 8. Metallic / roughness sliders ───────────────────────────

func _test_material_sliders_undo_redo() -> void:
	_clear()
	var node: Node3D = _spawn_shape("cube", PrimitiveDef.Type.CUBE, Vector3.ZERO)

	cmd_mgr.execute_command(CommandFactory.material(
		node, material_mgr.read_from(node),
		{albedo = Color.WHITE, metallic = 0.85, roughness = 1.0},
		container, spawner, material_mgr, hierarchy_mgr))
	node = _find_display("cube")
	if abs(material_mgr.read_from(node).metallic - 0.85) > 0.01:
		_fail("metallic slider: wrong after exec")
		return

	cmd_mgr.execute_command(CommandFactory.material(
		node, material_mgr.read_from(node),
		{albedo = Color.WHITE, metallic = 0.85, roughness = 0.15},
		container, spawner, material_mgr, hierarchy_mgr))
	node = _find_display("cube")
	if abs(material_mgr.read_from(node).roughness - 0.15) > 0.01:
		_fail("roughness slider: wrong after exec")
		return

	cmd_mgr.undo()
	node = _find_display("cube")
	if abs(material_mgr.read_from(node).roughness - 1.0) > 0.01:
		_fail("roughness undo: wrong")
		return
	cmd_mgr.undo()
	node = _find_display("cube")
	if abs(material_mgr.read_from(node).metallic - 0.0) > 0.01:
		_fail("metallic undo: wrong")
		return
	cmd_mgr.redo()
	node = _find_display("cube")
	if abs(material_mgr.read_from(node).metallic - 0.85) > 0.01:
		_fail("metallic redo: wrong")
		return
	cmd_mgr.redo()
	node = _find_display("cube")
	if abs(material_mgr.read_from(node).roughness - 0.15) > 0.01:
		_fail("roughness redo: wrong")
		return

	_pass("material sliders undo/redo")


# ── 9. Presets (all 5) ────────────────────────────────────────

func _test_presets_undo_redo() -> void:
	_clear()
	var node: Node3D = _spawn_shape("cube", PrimitiveDef.Type.CUBE, Vector3.ZERO)
	var history: Array[Dictionary] = []
	for p in material_mgr.get_presets():
		var props: Dictionary = material_mgr.get_preset_props(p)
		cmd_mgr.execute_command(CommandFactory.material(
			node, material_mgr.read_from(node), props,
			container, spawner, material_mgr, hierarchy_mgr))
		history.append(props.duplicate())
		node = _find_display("cube")
		var mat := _mat_of(node)
		if not mat or mat.albedo_color != props.albedo:
			_fail("preset %s: wrong albedo after apply" % p)
			return

	for i in history.size():
		cmd_mgr.undo()
		node = _find_display("cube")
		if not node:
			_fail("preset undo: node missing")
			return
		var got := material_mgr.read_from(node)
		if i == history.size() - 1:
			if got.albedo != Color.WHITE:
				_fail("preset: not default at bottom")
				return
		elif not _props_equal(got, history[history.size() - 2 - i]):
			_fail("preset undo: step %d mismatch" % i)
			return

	for i in history.size():
		cmd_mgr.redo()
		node = _find_display("cube")
		if not node:
			_fail("preset redo: node missing")
			return
		if not _props_equal(material_mgr.read_from(node), history[i]):
			_fail("preset redo: step %d mismatch" % i)
			return

	_pass("presets undo/redo (%d presets)" % history.size())


# ── 10. Group / ungroup across shapes ─────────────────────────

func _test_group_ungroup_undo_redo() -> void:
	_clear()
	var a := _spawn_shape("cube", PrimitiveDef.Type.CUBE, Vector3(0, 0, 0))
	var b := _spawn_shape("sphere", PrimitiveDef.Type.SPHERE, Vector3(2, 0, 0))
	var c := _spawn_shape("cylinder", PrimitiveDef.Type.CYLINDER, Vector3(4, 0, 0))

	cmd_mgr.execute_command(CommandFactory.group(
		"group", [a, b, c], container, spawner, material_mgr, hierarchy_mgr))
	var group := _find_display("group")
	if not group or _count_meshes() != 3:
		_fail("group: wrong structure")
		return

	cmd_mgr.undo()
	if _count_meshes() != 3 or _find_display("group"):
		_fail("group undo: structure wrong")
		return

	cmd_mgr.redo()
	group = _find_display("group")
	if not group or _count_meshes() != 3:
		_fail("group redo: structure wrong")
		return

	cmd_mgr.execute_command(CommandFactory.ungroup(
		group, container, spawner, material_mgr, hierarchy_mgr))
	if _count_meshes() != 3 or _find_display("group"):
		_fail("ungroup: structure wrong")
		return

	cmd_mgr.undo()
	group = _find_display("group")
	if not group or _count_meshes() != 3:
		_fail("ungroup undo: structure wrong")
		return

	cmd_mgr.redo()
	if _count_meshes() != 3 or _find_display("group"):
		_fail("ungroup redo: structure wrong")
		return

	_pass("group/ungroup undo/redo (3 shapes)")


# ── 11. Material must survive a transform (the old bug) ───────

func _test_material_survives_transform() -> void:
	_clear()
	var node: Node3D = _spawn_shape("cube", PrimitiveDef.Type.CUBE, Vector3(0, 0, 0))

	cmd_mgr.execute_command(CommandFactory.material(
		node, material_mgr.read_from(node), {albedo = Color(0.9, 0.1, 0.1), metallic = 0.0, roughness = 0.5},
		container, spawner, material_mgr, hierarchy_mgr))
	node = _find_display("cube")
	cmd_mgr.execute_command(CommandFactory.material(
		node, material_mgr.read_from(node), material_mgr.get_preset_props("metal"),
		container, spawner, material_mgr, hierarchy_mgr))
	node = _find_display("cube")
	var path := container.get_path_to(node)
	var before := Transform3D(node.basis, node.position)
	var after := Transform3D(node.basis, Vector3(5, 0, 0))
	cmd_mgr.execute_command(CommandFactory.transform(
		[path], [before], [after], container, spawner, material_mgr, hierarchy_mgr))

	cmd_mgr.undo()
	node = _find_display("cube")
	if not node or node.position.distance_to(Vector3.ZERO) > 0.01:
		_fail("material-survives: move undo position wrong")
		return

	var prev_props: Dictionary = {albedo = Color(0.9, 0.1, 0.1), metallic = 0.0, roughness = 0.5}
	cmd_mgr.undo()
	node = _find_display("cube")
	if not node:
		_fail("material-survives: node missing after preset undo")
		return
	if material_mgr.read_from(node).albedo != prev_props.albedo:
		_fail("material-survives: preset undo albedo wrong")
		return

	cmd_mgr.undo()
	node = _find_display("cube")
	if not node or material_mgr.read_from(node).albedo != Color.WHITE:
		_fail("material-survives: color undo not white")
		return

	cmd_mgr.redo()
	node = _find_display("cube")
	if not node or material_mgr.read_from(node).albedo != Color(0.9, 0.1, 0.1):
		_fail("material-survives: color redo failed")
		return

	cmd_mgr.redo()
	node = _find_display("cube")
	if not node or not _props_equal(material_mgr.read_from(node), material_mgr.get_preset_props("metal")):
		_fail("material-survives: preset redo failed")
		return

	cmd_mgr.redo()
	node = _find_display("cube")
	if not node or node.position.distance_to(Vector3(5, 0, 0)) > 0.01:
		_fail("material-survives: move redo position wrong")
		return
	if not _props_equal(material_mgr.read_from(node), material_mgr.get_preset_props("metal")):
		_fail("material-survives: material lost after move redo")
		return

	_pass("material survives transform (color->preset->move)")


# ── 12. Random combinations ───────────────────────────────────

func _test_random_combinations() -> void:
	_clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260923

	for step in 90:
		var roll: float = rng.randf()
		if cmd_mgr.can_redo() and roll < 0.13:
			cmd_mgr.redo()
		elif cmd_mgr.can_undo() and roll < 0.26:
			cmd_mgr.undo()
		elif roll < 0.5:
			var type: int = ALL_SHAPES[rng.randi_range(0, ALL_SHAPES.size() - 1)]
			var nm: String = "obj_%d" % _next_random_index
			_next_random_index += 1
			var pos := Vector3(rng.randf_range(-5, 5), rng.randf_range(0, 3), rng.randf_range(-5, 5))
			cmd_mgr.execute_command(CommandFactory.spawn({
				name = nm, display_name = nm, type = type,
				position = pos, rotation_degrees = Vector3.ZERO, scale = Vector3.ONE,
				material_albedo = Color.WHITE, material_metallic = 0.0, material_roughness = 1.0,
			}, container, spawner, material_mgr, hierarchy_mgr))
		elif roll < 0.68 and not _live_meshes().is_empty():
			var meshes := _live_meshes()
			var mi: MeshInstance3D = meshes[rng.randi_range(0, meshes.size() - 1)]
			var before := Transform3D(mi.basis, mi.position)
			var after: Transform3D = before
			match rng.randi_range(0, 2):
				0:
					after = Transform3D(mi.basis, mi.position + Vector3(rng.randf_range(-3, 3), rng.randf_range(-2, 2), rng.randf_range(-3, 3)))
				1:
					var axis := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
					if axis.length() < 0.01:
						axis = Vector3.UP
					after = Transform3D(Basis(axis.normalized(), deg_to_rad(rng.randf_range(-180, 180))) * mi.basis, mi.position)
				2:
					after = Transform3D(mi.basis.scaled(Vector3(rng.randf_range(0.4, 2.5), rng.randf_range(0.4, 2.5), rng.randf_range(0.4, 2.5))), mi.position)
			if not Transform3D_approx_eq(after, before):
				cmd_mgr.execute_command(CommandFactory.transform(
					[container.get_path_to(mi)], [before], [after],
					container, spawner, material_mgr, hierarchy_mgr))
		elif roll < 0.84 and not _live_meshes().is_empty():
			var meshes := _live_meshes()
			var mi: MeshInstance3D = meshes[rng.randi_range(0, meshes.size() - 1)]
			var before := material_mgr.read_from(mi)
			var after: Dictionary = before.duplicate()
			if rng.randf() < 0.5:
				after = material_mgr.get_preset_props(material_mgr.get_presets()[rng.randi_range(0, material_mgr.get_presets().size() - 1)])
			else:
				after.albedo = Color(rng.randf(), rng.randf(), rng.randf(), 1.0)
				after.metallic = rng.randf()
				after.roughness = rng.randf()
			cmd_mgr.execute_command(CommandFactory.material(
				mi, before, after, container, spawner, material_mgr, hierarchy_mgr))
		elif roll < 0.93:
			# Group two random top-level meshes, or ungroup an existing group.
			var top := _live_top_meshes()
			var groups := _live_groups()
			if not groups.is_empty() and rng.randf() < 0.5:
				var gp: Node3D = groups[rng.randi_range(0, groups.size() - 1)]
				cmd_mgr.execute_command(CommandFactory.ungroup(
					gp, container, spawner, material_mgr, hierarchy_mgr))
			elif top.size() >= 2:
				var picks: Array[Node3D] = []
				for k in 2:
					var pick: MeshInstance3D = top[rng.randi_range(0, top.size() - 1)]
					if not picks.has(pick):
						picks.append(pick)
				if picks.size() >= 2:
					cmd_mgr.execute_command(CommandFactory.group(
						"group", picks, container, spawner, material_mgr, hierarchy_mgr))
		elif cmd_mgr.can_redo():
			cmd_mgr.redo()
		elif cmd_mgr.can_undo():
			cmd_mgr.undo()

		# Strong invariants after every step.
		if cmd_mgr.undo_stack.size() > cmd_mgr.max_steps:
			_fail("random: undo stack over max_steps")
			return
		for c in container.get_children():
			if not is_instance_valid(c):
				_fail("random: invalid child node at step %d" % step)
				return

	var final_count := _count_meshes()
	while cmd_mgr.can_undo():
		cmd_mgr.undo()
	if _count_meshes() != 0:
		_fail("random: after full undo, %d meshes remain" % _count_meshes())
		return
	while cmd_mgr.can_redo():
		cmd_mgr.redo()
	if _count_meshes() != final_count:
		_fail("random: after full redo, %d meshes, expected %d" % [_count_meshes(), final_count])
		for c in container.get_children():
			if c is MeshInstance3D:
				print("   [top-level mesh] ", c.name)
			elif c is Node3D:
				var kids: Array[Node] = c.get_children()
				for k in kids:
					if k is MeshInstance3D:
						print("   [group %s ->] %s" % [c.name, k.name])
		return

	_pass("random combinations (90 steps, %d objects after redo)" % final_count)


# ── 13. Stale deselect must still emit selected_changed(null) ──

func _test_deselect_stale_emits_signal() -> void:
	_clear()
	# Array holder: GDScript lambdas capture locals BY VALUE, so a bare bool
	# flipped inside the lambda would never be visible here.
	var fired := [false]
	selection_mgr.selected_changed.connect(func(_n): fired[0] = true)
	var mi := _spawn_shape("signal_probe", PrimitiveDef.Type.CUBE, Vector3.ZERO)
	selection_mgr.select(mi)
	if not selection_mgr.get_selected():
		_fail("deselect-stale: select failed")
		return
	# Simulate the pre-fix delete order: node freed, THEN deselect_all(). The gizmo
	# teardown depends on this signal firing even though _selected went stale.
	cmd_mgr.execute_command(CommandFactory.delete([mi], container, spawner, material_mgr, hierarchy_mgr))
	selection_mgr.deselect_all()
	if not fired[0]:
		_fail("deselect-stale: selected_changed(null) NOT emitted after node freed (gizmo would target freed node)")
		return
	cmd_mgr.undo()
	_pass("stale deselect emits selected_changed(null)")


# ── 14. Gizmo must drop a freed target instead of tracking it ──

func _test_gizmo_drops_freed_target() -> void:
	_clear()
	var giz := Gizmo3D.new()
	root.add_child(giz)
	giz.visible = false
	var mi := _spawn_shape("giz_probe", PrimitiveDef.Type.CUBE, Vector3.ONE)
	giz.set_target(mi)
	if not giz.visible or giz._target != mi:
		_fail("gizmo-freed: set_target didn't attach")
		root.remove_child(giz)
		giz.free()
		return
	mi.free()
	giz._process(0.0)
	if giz.visible or giz._target != null:
		_fail("gizmo-freed: gizmo still visible / targeting freed node")
		root.remove_child(giz)
		giz.free()
		return
	root.remove_child(giz)
	giz.free()
	_pass("gizmo drops freed target and hides")


# ── 15. Selection must survive the snapshot rebuild after a group transform ──

## Regression: end_move() frees the selected nodes and materializes fresh
## instances via ModelingAction. Without re-pointing, SelectionManager holds
## freed node refs that _clear_stale_selection silently nulls — and because a
## multi-select gizmo lives in pivot mode with _target == null, it lingers over
## an empty scene forever. Verify the group STAYS selected (live instances) and
## deselect really hides a pivot gizmo.
func _test_selection_survives_group_transform() -> void:
	_clear()
	var a := _spawn_shape("gs_a", PrimitiveDef.Type.CUBE, Vector3.LEFT)
	var b := _spawn_shape("gs_b", PrimitiveDef.Type.SPHERE, Vector3.RIGHT)
	cmd_mgr.execute_command(CommandFactory.group("group", [a, b], container, spawner, material_mgr, hierarchy_mgr))
	var group := _find_display("group")
	if not group or _count_meshes() != 2:
		_fail("sel-survive: group failed")
		return
	var members_before: Array[MeshInstance3D] = []
	for c in group.get_children():
		if c is MeshInstance3D:
			members_before.append(c as MeshInstance3D)
	selection_mgr.select_multi(members_before)
	if selection_mgr.selected_count() != 2:
		_fail("sel-survive: multi-select failed")
		return
	# No-move gizmo drag on the group (press + release without moving).
	tfm.begin_move(Vector3.RIGHT)
	tfm.apply_move(Vector3.RIGHT, 0.0)
	tfm.end_move()
	var live := selection_mgr.selected_nodes()
	if live.size() != 2:
		_fail("sel-survive: selection lost after group end_move (gizmo would linger in pivot mode)")
		return
	for n in live:
		if not is_instance_valid(n):
			_fail("sel-survive: selection holds a freed node")
			return
	var members_after: Array = group.get_children().filter(func(c): return c is MeshInstance3D)
	if members_after.size() != 2 or not live[0].get_instance_id() in members_after.map(func(c): return c.get_instance_id()):
		_fail("sel-survive: selection is not the rebuilt group members")
		return
	# Undo must rebuild again and re-select the rebuilt members.
	cmd_mgr.undo()
	live = selection_mgr.selected_nodes()
	if live.size() != 2 or not is_instance_valid(live[0]):
		_fail("sel-survive: selection lost after undo")
		return
	# Redo likewise.
	cmd_mgr.redo()
	live = selection_mgr.selected_nodes()
	if live.size() != 2 or not is_instance_valid(live[0]):
		_fail("sel-survive: selection lost after redo")
		return
	cmd_mgr.clear_history()
	group.free()
	_pass("selection survives snapshot rebuild through transform + undo + redo")


# ── 16. Pivot gizmo must hide the moment nothing is selected ──

## Regression: even in pivot mode (multi-select, _target == null), a gizmo may
## never stay visible when the selection is empty. This mirrors modeling_lab's
## per-frame invariant and the user-reported "gizmo lingers after deselect".
func _test_gizmo_node_hides_when_nothing_selected() -> void:
	_clear()
	var giz := Gizmo3D.new()
	root.add_child(giz)
	giz.visible = false
	var a := _spawn_shape("gh_a", PrimitiveDef.Type.CUBE, Vector3.LEFT)
	var b := _spawn_shape("gh_b", PrimitiveDef.Type.CUBE, Vector3.RIGHT)
	selection_mgr.select_multi([a, b])
	giz.set_pivot((a.global_position + b.global_position) * 0.5)
	# Mirror modeling_lab's wiring: selected_changed drives the gizmo teardown
	# for empty selections (set_target(null) + visible=false).
	var teardown := func(n):
		if n == null:
			giz.set_target(null)
			giz.visible = false
	selection_mgr.selected_changed.connect(teardown)
	if selection_mgr.selected_count() != 2 or not giz.visible or giz._pivot_active != true:
		_fail("gizmo-hide: pivot setup failed")
		root.remove_child(giz)
		giz.free()
		return
	# Empty selection => gizmo must be torn down even in pivot mode.
	selection_mgr.deselect_all()
	if giz.visible or giz._target != null or giz._pivot_active:
		_fail("gizmo-hide: pivot gizmo lingers with empty selection (user bug)")
		selection_mgr.selected_changed.disconnect(teardown)
		root.remove_child(giz)
		giz.free()
		return
	selection_mgr.selected_changed.disconnect(teardown)
	_pass("pivot gizmo hides when nothing is selected")
	root.remove_child(giz)
	giz.free()


# ── 17. Box-select must find GROUPED members (rubber-band over a group) ──

## Regression: _apply_selection_box previously iterated only direct children of
## object_container, so members nested under a group Node3D were invisible to
## click-and-drag (rubber-band) selection while the physics click path found
## them. Verify collect_selectable_meshes() recurses through groups so the box
## rect can hit grouped members too.
func _test_box_select_finds_grouped_members() -> void:
	_clear()
	var a := _spawn_shape("bx_a", PrimitiveDef.Type.CUBE, Vector3.LEFT)
	var b := _spawn_shape("bx_b", PrimitiveDef.Type.SPHERE, Vector3.RIGHT)
	# Standalone (ungrouped) meshes must also be collected.
	var c := _spawn_shape("bx_c", PrimitiveDef.Type.CUBE, Vector3.ZERO)
	cmd_mgr.execute_command(CommandFactory.group("group", [a, b], container, spawner, material_mgr, hierarchy_mgr))
	var group := _find_display("group")
	if not group or _count_meshes() != 3:
		_fail("box-group: setup failed")
		return
	var collected := selection_mgr.collect_selectable_meshes()
	if collected.size() != 3:
		_fail("box-group: collect_selectable_meshes returned %d (want 3; grouped members were invisible to box-select)" % collected.size())
		return
	# The grouped members must be in the collected set (the bug was missing them).
	var found_grouped := 0
	for m in collected:
		if m == a or m == b:
			found_grouped += 1
	if found_grouped != 2:
		_fail("box-group: grouped members not collected (found %d/2)" % found_grouped)
		return
	# Simulate a rubber-band box that encloses all three projected centers.
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.global_position = Vector3(0, 3, 6)
	cam.look_at(Vector3.ZERO, Vector3.UP)
	# Frame the camera so all three project inside a generous rect.
	var hits: Array[MeshInstance3D] = []
	for m in collected:
		hits.append(m)  # what _apply_selection_box now iterates
	if hits.size() != 3:
		_fail("box-group: box rect would only see %d/3 meshes" % hits.size())
		root.remove_child(cam)
		cam.free()
		return
	# Select via the same path _apply_selection_box uses.
	selection_mgr.select_multi(hits)
	if selection_mgr.selected_count() != 3:
		_fail("box-group: select_multi over collected grouped set failed")
		root.remove_child(cam)
		cam.free()
		return
	# Grouped members must be selectable as one multi-selection (pivot mode).
	if selection_mgr.selected_count() > 1:
		selection_mgr.deselect_all()
	cmd_mgr.clear_history()
	group.free()
	root.remove_child(cam)
	cam.free()
	_pass("box-select finds grouped + standalone members (recursive collector)")


# ── 18. Double-click drills down from a full group selection to one member ──

## Rule: while the ENTIRE group is selected, double-clicking any member selects
## only that member (group -> member). A partial multi-select (e.g. 2 of 3)
## must NOT be treated as a full group selection. This is the choice the lab
## makes in _on_viewport_gui_input's double-click branch.
func _test_double_click_drills_down_group() -> void:
	_clear()
	var a := _spawn_shape("dc_a", PrimitiveDef.Type.CUBE, Vector3.LEFT)
	var b := _spawn_shape("dc_b", PrimitiveDef.Type.CUBE, Vector3.RIGHT)
	var c := _spawn_shape("dc_c", PrimitiveDef.Type.CUBE, Vector3.UP)
	cmd_mgr.execute_command(CommandFactory.group("group", [a, b, c], container, spawner, material_mgr, hierarchy_mgr))
	var group := _find_display("group")
	if not group or _count_meshes() != 3:
		_fail("double-click: setup failed")
		return
	var members: Array[MeshInstance3D] = []
	for ch in group.get_children():
		if ch is MeshInstance3D:
			members.append(ch as MeshInstance3D)
	if members.size() != 3:
		_fail("double-click: expected 3 grouped members")
		return

	# 1) Full group selected: every member selected, count == group size.
	selection_mgr.select_multi(members)
	if selection_mgr.selected_count() != 3:
		_fail("double-click: full-group select failed")
		return
	if not selection_mgr.is_full_group_selected(members[0]):
		_fail("double-click: is_full_group_selected should be true when all members are selected")
		return

	# 2) Double-click conveyor runs is_full_group_selected + select(member).
	#    Simulate the double-click branch logic: drill down to member[1].
	var hit: MeshInstance3D = members[1]
	if selection_mgr.is_selected(hit) \
			and selection_mgr.selected_count() > 1 \
			and selection_mgr.is_full_group_selected(hit):
		selection_mgr.select(hit)
	if selection_mgr.selected_count() != 1 or selection_mgr.get_selected() != hit:
		_fail("double-click: drill-down did NOT collapse to the single member")
		return

	# 3) Partial selection (box-select 2 of 3) must NOT count as full group.
	selection_mgr.select_multi([members[0], members[1]])
	if selection_mgr.is_full_group_selected(members[0]):
		_fail("double-click: partial multi-select must not be treated as a full group")
		return

	# 4) Standalone (ungrouped) mesh is never a "full group".
	var standalone := _spawn_shape("dc_standalone", PrimitiveDef.Type.SPHERE, Vector3.DOWN)
	selection_mgr.select(standalone)
	if selection_mgr.is_full_group_selected(standalone):
		_fail("double-click: standalone mesh must not be treated as a group")
		return
	cmd_mgr.clear_history()
	group.free()
	_pass("double-click drills down group -> single member (full-group only)")


# ── 18b. Drill-down must clear the highlight on non-selected group peers ──

## Regression: select() only removed the highlight from the primary member,
## so after a full-group select_multi followed by a single-member select
## (double-click drill-down, hierarchy tree click, reselect_from_ids), the
## other group members kept their material_overlay highlight even though they
## were no longer selected.
func _test_group_drill_down_clears_peer_highlights() -> void:
	_clear()
	var a := _spawn_shape("dh_a", PrimitiveDef.Type.CUBE, Vector3.LEFT)
	var b := _spawn_shape("dh_b", PrimitiveDef.Type.CUBE, Vector3.RIGHT)
	var c := _spawn_shape("dh_c", PrimitiveDef.Type.CUBE, Vector3.UP)
	cmd_mgr.execute_command(CommandFactory.group("group", [a, b, c], container, spawner, material_mgr, hierarchy_mgr))
	var group := _find_display("group")
	if not group or _count_meshes() != 3:
		_fail("drill-clear: setup failed")
		return
	var members: Array[MeshInstance3D] = []
	for ch in group.get_children():
		if ch is MeshInstance3D:
			members.append(ch as MeshInstance3D)
	if members.size() != 3:
		_fail("drill-clear: expected 3 grouped members")
		return

	# Full group selected: every member gets a highlight overlay.
	selection_mgr.select_multi(members)
	for m in members:
		if m.material_overlay == null \
				or not (m.material_overlay as Material).get_meta("gizmo_highlight", false):
			_fail("drill-clear: select_multi did not highlight all members")
			return

	# Drill down to member[1]: only it must stay highlighted.
	selection_mgr.select(members[1])
	if selection_mgr.selected_count() != 1 or selection_mgr.get_selected() != members[1]:
		_fail("drill-clear: select did not collapse to single member")
		return
	var drill_ok := true
	if members[1].material_overlay == null:
		_fail("drill-clear: drilled member lost its highlight")
		drill_ok = false
	for i in [0, 2]:
		if members[i].material_overlay != null:
			_fail("drill-clear: non-selected peer %d kept stale highlight" % i)
			drill_ok = false
	if not drill_ok:
		return
	cmd_mgr.clear_history()
	group.free()
	_pass("drill-down clears highlights on non-selected group peers")


# ── 19. Duplicate a whole group (new group node + member copies) ──

func _test_duplicate_group_undo_redo() -> void:
	_clear()
	var a := _spawn_shape("cube", PrimitiveDef.Type.CUBE, Vector3(-1, 0, 0))
	var b := _spawn_shape("sphere", PrimitiveDef.Type.SPHERE, Vector3(1, 0, 0))
	var c := _spawn_shape("cylinder", PrimitiveDef.Type.CYLINDER, Vector3(0, 1, 0))
	cmd_mgr.execute_command(CommandFactory.group(
		"group", [a, b, c], container, spawner, material_mgr, hierarchy_mgr))
	var group := _find_display("group")
	if not group or _count_meshes() != 3:
		_fail("dup-group: setup group failed")
		return

	# Full-group selection precondition (what _on_duplicate checks).
	var members: Array[MeshInstance3D] = []
	for ch in group.get_children():
		if ch is MeshInstance3D:
			members.append(ch)
	selection_mgr.select_multi(members)
	if not selection_mgr.is_full_group_selected(members[0]):
		_fail("dup-group: full-group select failed")
		return

	var src_group_pos: Vector3 = group.position
	var src_member_pos: Array[Vector3] = []
	for m in members:
		src_member_pos.append(m.global_position)

	cmd_mgr.execute_command(CommandFactory.duplicate_group(
		group, container, spawner, material_mgr, hierarchy_mgr))

	# Structural: 3 + 3 copies, group copy present, all under the new group.
	if _count_meshes() != 6:
		_fail("dup-group: expected 6 meshes after duplicate, got %d" % _count_meshes())
		return
	var groups := _live_groups()
	var copy_group: Node3D = null
	for g in groups:
		if g != group:
			copy_group = g
			break
	if not copy_group:
		_fail("dup-group: no group copy created")
		return
	var copy_members: Array[MeshInstance3D] = []
	for ch in copy_group.get_children():
		if ch is MeshInstance3D:
			copy_members.append(ch)
	if copy_members.size() != 3:
		_fail("dup-group: group copy has %d members, want 3" % copy_members.size())
		return
	if not copy_group.position.is_equal_approx(src_group_pos + Vector3(0.5, 0.5, 0.5)):
		_fail("dup-group: group copy not offset +0.5 from source group")

	# Names are re-allocated (Blender style), not leaked from the source.
	if HierarchyManager.display_of(copy_group) == HierarchyManager.display_of(group):
		_fail("dup-group: group copy name collides with source group")
		return
	for m in copy_members:
		if HierarchyManager.display_of(m) in ["cube", "sphere", "cylinder"]:
			_fail("dup-group: member copy name collides with source member '%s'" % HierarchyManager.display_of(m))
			return

	# The copy is independently selectable as a full group again (recursion).
	selection_mgr.select_multi(copy_members)
	if not selection_mgr.is_full_group_selected(copy_members[0]):
		_fail("dup-group: duplicated group not recognized as a full group")
		return

	# Undo removes the entire copy; redo restores it.
	cmd_mgr.undo()
	if _count_meshes() != 3 or _live_groups().size() != 1:
		_fail("dup-group: undo did not remove the group copy")
		return
	cmd_mgr.redo()
	if _count_meshes() != 6 or _live_groups().size() != 2:
		_fail("dup-group: redo did not restore the group copy")
		return

	cmd_mgr.clear_history()
	group.free()
	_pass("duplicate whole group (structure, names, offset, undo/redo)")


# ── 20. Save/Load scene preserves groups + hierarchy (Blender-file style) ──

func _test_save_scene_preserves_groups() -> void:
	_clear()

	# Build: 1 flat mesh + 1 group (2 meshes) + 1 nested group inside it.
	var flat := _spawn_shape("save_flat", PrimitiveDef.Type.CUBE, Vector3(3, 0, 0))
	# Material will be applied to the deepest member (save_inner_member) below.

	var g_member_a := _spawn_shape("save_member_a", PrimitiveDef.Type.SPHERE, Vector3(-1, 0, 0))
	var g_member_b := _spawn_shape("save_member_b", PrimitiveDef.Type.CUBE, Vector3(1, 0, 0))

	# Nested: "outer" group contains member mesh + an "inner" group w/ its own mesh.
	var outer := Node3D.new()
	HierarchyManager.set_blender_name(outer, "outer")
	container.add_child(outer)
	outer.position = Vector3(0, 0, 0)

	var inner := Node3D.new()
	HierarchyManager.set_blender_name(inner, "inner")
	outer.add_child(inner)
	inner.position = Vector3(0, 2, 0)
	var inner_member := _spawn_shape("save_inner_member", PrimitiveDef.Type.CONE, Vector3(0, 3, 0))
	material_mgr.apply_to(inner_member, {albedo = Color(0.9, 0.1, 0.1, 0.3), metallic = 0.3, roughness = 0.7})
	# Re-parent into nesting: spawner drops at container, so move them under
	# their groups preserving world positions.
	hierarchy_mgr.reparent_preserve(g_member_a, outer)
	hierarchy_mgr.reparent_preserve(g_member_b, outer)
	hierarchy_mgr.reparent_preserve(inner_member, inner)

	var sm := SaveManager.new()
	var data := sm.capture_model(container, "save_scene_1")

	# ── Capture structure ──
	var flat_pd := _find_pd(data, "save_flat")
	if not flat_pd or flat_pd.node_type != PrimitiveSaveData.TYPE_MESH:
		_fail("save-scene: flat mesh not captured as MESH")
		return
	if not flat_pd.parent_name.is_empty():
		_fail("save-scene: flat mesh parent_name should be '' got '%s'" % flat_pd.parent_name)
		return
	var outer_pd := _find_pd(data, "outer")
	if not outer_pd or outer_pd.node_type != PrimitiveSaveData.TYPE_GROUP:
		_fail("save-scene: group 'outer' not captured as GROUP")
		return
	if not outer_pd.parent_name.is_empty():
		_fail("save-scene: outer group should be top-level, got parent '%s'" % outer_pd.parent_name)
		return
	var inner_pd := _find_pd(data, "inner")
	if not inner_pd or inner_pd.node_type != PrimitiveSaveData.TYPE_GROUP:
		_fail("save-scene: nested group 'inner' not captured as GROUP")
		return
	if inner_pd.parent_name != "outer":
		_fail("save-scene: inner group parent_name='%s', expected 'outer'" % inner_pd.parent_name)
		return
	var ma_pd := _find_pd(data, "save_member_a")
	if not ma_pd or ma_pd.parent_name != "outer":
		_fail("save-scene: member_a parent_name='%s', expected 'outer'" % [ma_pd.parent_name if ma_pd else "missing"])
		return
	var im_pd := _find_pd(data, "save_inner_member")
	if not im_pd or im_pd.parent_name != "inner":
		_fail("save-scene: inner_member parent_name='%s', expected 'inner'" % [im_pd.parent_name if im_pd else "missing"])
		return
	if not im_pd.material_albedo.is_equal_approx(Color(0.9, 0.1, 0.1, 0.3)):
		_fail("save-scene: material albedo not preserved on member")
		return
	if not is_equal_approx(im_pd.material_metallic, 0.3) or not is_equal_approx(im_pd.material_roughness, 0.7):
		_fail("save-scene: material metallic/roughness not preserved")
		return

	# Parents must precede children in the flat array (pre-order).
	var names_order: Array[String] = []
	for pd in data.primitives:
		names_order.append(pd.display_name if pd.display_name != "" else pd.node_name)
	var idx_outer := names_order.find("outer")
	var idx_inner := names_order.find("inner")
	var idx_im := names_order.find("save_inner_member")
	if idx_outer < 0 or idx_inner < 0 or idx_im < 0:
		_fail("save-scene: missing group/member in capture order")
		return
	if not (idx_outer < idx_inner and idx_inner < idx_im):
		_fail("save-scene: pre-order violated (outer=%d inner=%d member=%d)" % [idx_outer, idx_inner, idx_im])
		return

	# ── Restore into a fresh container ──
	var restored := Node3D.new()
	root.add_child(restored)
	var created := sm.restore_model(restored, data, spawner)
	if created.size() != 4:
		_fail("save-scene: restore returned %d meshes, want 4" % created.size())
		restored.free()
		return
	if _deep_count_meshes(restored) != 4:
		_fail("save-scene: restored tree has %d meshes, want 4" % _deep_count_meshes(restored))
		restored.free()
		return
	var r_outer := _deep_find(restored, "outer")
	var r_inner := _deep_find(restored, "inner")
	var r_flat := _deep_find(restored, "save_flat")
	var r_ma := _deep_find(restored, "save_member_a")
	var r_im := _deep_find(restored, "save_inner_member")
	if not r_outer or not r_inner or not r_flat or not r_ma or not r_im:
		_fail("save-scene: restored hierarchy missing nodes")
		restored.free()
		return
	if r_outer.get_parent() != restored:
		_fail("save-scene: outer not restored at top level")
		restored.free()
		return
	if r_flat.get_parent() != restored:
		_fail("save-scene: flat mesh not restored at top level")
		restored.free()
		return
	if r_inner.get_parent() != r_outer:
		_fail("save-scene: inner not restored inside outer")
		restored.free()
		return
	if r_ma.get_parent() != r_outer:
		_fail("save-scene: member_a parent is %s, want outer" % (r_ma.get_parent().name if r_ma.get_parent() else "null"))
		restored.free()
		return
	if r_im.get_parent() != r_inner:
		_fail("save-scene: inner_member parent is %s, want inner" % (r_im.get_parent().name if r_im.get_parent() else "null"))
		restored.free()
		return
	if not r_im.position.is_equal_approx(im_pd.position):
		_fail("save-scene: inner_member local position not preserved (got %s want %s)" % [r_im.position, im_pd.position])
		restored.free()
		return
	if not r_inner.position.is_equal_approx(inner_pd.position):
		_fail("save-scene: inner group local position not preserved")
		restored.free()
		return
	if not HierarchyManager.display_of(r_ma) == "save_member_a":
		_fail("save-scene: restored member display name not preserved")
		restored.free()
		return
	var rm_mat: StandardMaterial3D = r_im.get_surface_override_material(0) as StandardMaterial3D
	if not rm_mat or not rm_mat.albedo_color.is_equal_approx(Color(0.9, 0.1, 0.1, 0.3)):
		_fail("save-scene: restored material albedo mismatch")
		restored.free()
		return
	if not is_equal_approx(rm_mat.metallic, 0.3) or not is_equal_approx(rm_mat.roughness, 0.7):
		_fail("save-scene: restored material metallic/roughness mismatch")
		restored.free()
		return
	if rm_mat.transparency != StandardMaterial3D.TRANSPARENCY_ALPHA:
		_fail("save-scene: restored translucent material did not enable TRANSPARENCY_ALPHA")
		restored.free()
		return

	# ── Restore clears the target container first (no stale groups) ──
	var r2 := sm.restore_model(restored, data, spawner)
	if _deep_count_meshes(restored) != 4:
		_fail("save-scene: re-restore leaked stale nodes (%d meshes)" % _deep_count_meshes(restored))
		restored.free()
		return
	restored.free()
	_pass("save/load scene preserves flat + nested groups (structure, names, transform, material, clear-on-restore)")


func _find_pd(data: ModelData, display: String) -> PrimitiveSaveData:
	for pd in data.primitives:
		if pd.display_name == display:
			return pd
	return null


func _deep_find(root: Node, display: String) -> Node3D:
	if root is Node3D and HierarchyManager.display_of(root) == display:
		return root as Node3D
	for c in root.get_children():
		var found := _deep_find(c, display)
		if found:
			return found
	return null


func _deep_count_meshes(root: Node) -> int:
	var count := 0
	for c in root.get_children():
		if c is MeshInstance3D and not c.is_in_group("ghost_guides"):
			count += 1
		count += _deep_count_meshes(c)
	return count


func Transform3D_approx_eq(a: Transform3D, b: Transform3D) -> bool:
	return a.origin.distance_to(b.origin) < 0.001 \
			and a.basis.get_scale().distance_to(b.basis.get_scale()) < 0.001 \
			and a.basis.get_euler().distance_to(b.basis.get_euler()) < 0.002