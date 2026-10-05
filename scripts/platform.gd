class_name Platform
extends RefCounted

## Platform detection + dev override for cross-platform builds.
## Use these helpers instead of raw OS.has_feature() so the UI can be
## authored once and adapt to desktop / mobile / web at runtime.

static func is_desktop_build() -> bool:
	return not OS.has_feature("mobile") and not OS.has_feature("web")

static func is_mobile_or_web() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("web")

## Dev override for desktop (Windows) playtests. Enable
## ProjectSettings "emc/simulate_mobile" to emulate touch-UI behavior on a
## desktop build while debugging mobile/web layouts.
static func simulate_mobile_enabled() -> bool:
	return bool(ProjectSettings.get_setting("emc/simulate_mobile", false))

## Runtime escape hatch for wants_touch_controls(): null means "follow the
## build", true/false force the decision. It lets the pause menu's
## touch-controls button switch the joystick on for desktop playtesting without
## editing ProjectSettings - which would ship enabled and hide desktop display
## settings for every desktop player via show_desktop_settings().
static var _touch_controls_override: Variant = null

static func set_touch_controls_override(value: Variant) -> void:
	_touch_controls_override = value

## Touch controls (virtual joystick, action buttons) show on touch-capable
## platforms and remain available on desktop via the mobile simulation toggle.
## An explicit override outranks both.
static func wants_touch_controls() -> bool:
	if _touch_controls_override != null:
		return bool(_touch_controls_override)
	return is_mobile_or_web() or simulate_mobile_enabled()

## Desktop-only settings (fullscreen, resolution) are hidden on mobile and
## web exports as well as while desktop mobile simulation is active.
static func show_desktop_settings() -> bool:
	return is_desktop_build() and not simulate_mobile_enabled()
