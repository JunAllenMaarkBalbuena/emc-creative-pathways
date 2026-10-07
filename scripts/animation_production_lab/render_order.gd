class_name RenderOrder
## Composition render-order mechanism for the Animation Production Lab
## (approved B2, see the studio-round plan).
##
## Godot 3D sorts opaque objects by depth and transparents by
## (render_priority, then depth). Spatial z therefore CANNOT decide layer
## order for a 2.5D composition — background and character live on the same
## plane and the player's depth slider is spatial, not compositional. This
## helper puts every registered layer through the TRANSPARENT pass with a
## monotonic render_priority so painter's order is decided by layer index,
## not by z or camera angle.
##
## Empirically verified on this machine (windowed probe, recorded in the task
## ledger): with equal z, the sprite holding the HIGHER render_priority is the
## one drawn on top — the pixel signature flips when the priorities swap.

const PRIORITY_STEP := 16
const STARTER_PRIORITY := 0


## Priority for player layer `layer_index` (0-based). Starts at
## STARTER_PRIORITY + PRIORITY_STEP so player layers can never collide with
## the fixed starter-scene nodes (which sit at STARTER_PRIORITY).
static func layer_priority(layer_index: int) -> int:
	return STARTER_PRIORITY + (layer_index + 1) * PRIORITY_STEP


## Write a node's transparent-pass render priority.
##
## Empirically (probe, this task): SpriteBase3D carries `render_priority` on
## the instance; GeometryInstance3D / MeshInstance3D does NOT — meshes have to
## carry priority on their (transparent) material instead. So:
##   - sprites: instance property.
##   - meshes: duplicate the current material_override (so a shared authored
##     starter material is never mutated for every instance), force the
##     transparent pass, and put the priority on it.
static func set_layer_priority(node: Node3D, value: int) -> void:
	if node is SpriteBase3D:
		(node as SpriteBase3D).render_priority = value
	elif node is MeshInstance3D:
		var mesh := node as MeshInstance3D
		var mat: StandardMaterial3D
		if mesh.material_override == null:
			mat = StandardMaterial3D.new()
		else:
			mat = mesh.material_override.duplicate() as StandardMaterial3D
		apply_to_material(mat, value)
		mesh.material_override = mat


## Force a layer mesh's material into the transparent pass so the
## instance/material priority rules its ordering. Visually identical at
## alpha 1.0 (opaque color blended over whatever is behind it).
static func apply_to_material(mat: StandardMaterial3D, value: int) -> void:
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.render_priority = value