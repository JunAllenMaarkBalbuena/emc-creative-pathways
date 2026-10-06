class_name PrimitiveSaveData
extends Resource

const TYPE_MESH := 0
const TYPE_GROUP := 1

@export var node_type: int = TYPE_MESH   # MESH or GROUP
@export var type: int = 0
@export var node_name: String = ""
@export var display_name: String = ""    # Blender-style ("cube.001")
@export var position: Vector3
@export var rotation_degrees: Vector3
@export var scale: Vector3 = Vector3.ONE
## Exact basis, row-major 9 floats. `rotation_degrees` + `scale` cannot express
## a sheared basis (a Global-axis scale of a rotated object is S*R, not R*S), so
## capturing only those two silently reloaded the object as its decomposition.
## Empty means "not stored" - see `has_basis`.
@export var basis_rows: PackedFloat32Array = PackedFloat32Array()
## Whether `basis_rows` is authoritative. A plain `basis_rows.is_empty()` check
## cannot tell "this save predates the field" from "this object's basis really
## is empty", so the flag makes absence explicit and survives round-tripping an
## unrotated, unscaled object. Old files simply lack this property and load with
## the default false, which routes them through the legacy rotation+scale path
## unchanged - that is the whole backward-compatibility story, so do not add a
## version integer on top of it without a migration to go with it.
@export var has_basis: bool = false
## Whether the Skew switch is on for this object (docs/decisions/2026-10-06-skew-toggle.md).
## Same absence story as `has_basis`: old files lack this property and load with
## the default false - i.e. the switch is OFF for every legacy save, which is the
## safe reading (rotation keeps flattening those, the pre-switch contract).
@export var skew_enabled: bool = false
@export var parent_name: String = ""     # display_name of the parent group
@export var material_albedo: Color = Color.WHITE
@export var material_metallic: float = 0.0
@export var material_roughness: float = 0.5
