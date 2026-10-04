extends Control

var parent_ref = null

func _draw():
	if parent_ref and parent_ref.has_method("_gizmo_draw"):
		parent_ref._gizmo_draw(self)
