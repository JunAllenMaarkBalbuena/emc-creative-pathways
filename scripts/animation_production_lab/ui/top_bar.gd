extends Control

## Top bar: always visible. Mode + stage labels, a live status line, exit
## button, a Continue button that drives ASSETS..PREVIEW in the guided flow
## (hidden at BRIEF/PLAN/SUBMIT and in Studio mode — the panels own those
## controls), and a Creative Studio button that only appears once the guided
## run is completed (Task 16 — unlock gate is the lab's own save flag, spec
## §15). Undo/Redo (Task 4) are Studio-only: the guided flow is a tutorial
## and has no need for history controls. No class_name on purpose (the root
## types this via a preload const).

signal exit_requested
signal studio_requested
signal continue_requested
signal undo_requested
signal redo_requested
signal dock_toggle_requested(name: String, visible: bool)

@onready var mode_label: Label = %ModeLabel
@onready var stage_label: Label = %StageLabel
@onready var status_label: Label = %StatusLabel
@onready var continue_button: Button = %ContinueButton
@onready var studio_button: Button = %StudioButton
@onready var undo_button: Button = %UndoButton
@onready var redo_button: Button = %RedoButton
@onready var layers_toggle: CheckButton = %LayersToggle
@onready var inspector_toggle: CheckButton = %InspectorToggle
@onready var assets_toggle: CheckButton = %AssetsToggle
@onready var timeline_toggle: CheckButton = %TimelineToggle

func set_mode_label(text: String) -> void:
	mode_label.text = text

func set_stage_label(text: String) -> void:
	stage_label.text = text

func set_status_label(text: String) -> void:
	status_label.text = text

func set_continue_visible(visible_: bool) -> void:
	continue_button.visible = visible_

func set_studio_unlocked(unlocked: bool) -> void:
	studio_button.visible = unlocked

## Studio only: undo/redo exist for the free-form editor, never in guided.
func set_undo_redo_visible(visible_: bool) -> void:
	undo_button.visible = visible_
	redo_button.visible = visible_

func set_undo_enabled(enabled: bool) -> void:
	undo_button.disabled = not enabled

func set_redo_enabled(enabled: bool) -> void:
	redo_button.disabled = not enabled

## Studio only: the 4 docker visibility toggles (Layers/Inspector/Assets/
## Timeline). In guided the stage map drives panel visibility exclusively.
func set_dock_toggles_visible(visible_: bool) -> void:
	layers_toggle.visible = visible_
	inspector_toggle.visible = visible_
	assets_toggle.visible = visible_
	timeline_toggle.visible = visible_

## Sync a single toggle's pressed state without re-emitting (used when the
## root hides a docker through another path).
func set_dock_toggle(name: String, on: bool) -> void:
	match name:
		"layers":
			layers_toggle.set_pressed_no_signal(on)
		"inspector":
			inspector_toggle.set_pressed_no_signal(on)
		"assets":
			assets_toggle.set_pressed_no_signal(on)
		"timeline":
			timeline_toggle.set_pressed_no_signal(on)

func _on_dock_toggled(pressed: bool, name: String) -> void:
	dock_toggle_requested.emit(name, pressed)

func _on_continue_pressed() -> void:
	continue_requested.emit()

func _on_studio_pressed() -> void:
	studio_requested.emit()

func _on_exit_pressed() -> void:
	exit_requested.emit()

func _on_undo_pressed() -> void:
	undo_requested.emit()

func _on_redo_pressed() -> void:
	redo_requested.emit()