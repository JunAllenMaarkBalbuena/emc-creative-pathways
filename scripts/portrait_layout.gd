class_name PortraitLayout
extends Resource

## Per-NPC/per-dialogue portrait layout for DialogueUI.
## Uses the same anchor + offset system as Godot's Control nodes
## so portraits scale correctly at any resolution.
##
## Anchors: 0.0 = left/top edge, 1.0 = right/bottom edge
## Offsets: pixel distance from the anchor point

@export var dialogue_id: String = ""

@export_group("NPC Portrait")
@export var npc_scale := Vector2(1.0, 1.0)
@export_range(0.0, 1.0, 0.001) var npc_anchor_left := 0.829
@export_range(0.0, 1.0, 0.001) var npc_anchor_top := 0.356
@export_range(0.0, 1.0, 0.001) var npc_anchor_right := 0.966
@export_range(0.0, 1.0, 0.001) var npc_anchor_bottom := 0.648
@export var npc_offset_left := -0.558
@export var npc_offset_top := 0.312
@export var npc_offset_right := -0.190
@export var npc_offset_bottom := 0.096

@export_group("Player Portrait")
@export var player_scale := Vector2(1.0, 1.0)
@export_range(0.0, 1.0, 0.001) var player_anchor_left := 0.033
@export_range(0.0, 1.0, 0.001) var player_anchor_top := 0.356
@export_range(0.0, 1.0, 0.001) var player_anchor_right := 0.142
@export_range(0.0, 1.0, 0.001) var player_anchor_bottom := 0.648
@export var player_offset_left := -0.016
@export var player_offset_top := 0.312
@export var player_offset_right := 0.416
@export var player_offset_bottom := 0.096
