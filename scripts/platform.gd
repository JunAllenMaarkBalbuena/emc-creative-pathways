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

## Touch controls (virtual joystick, action buttons) show on touch-capable
## platforms and remain available on desktop via the mobile simulation toggle.
static func wants_touch_controls() -> bool:
	return is_mobile_or_web() or simulate_mobile_enabled()

## Desktop-only settings (fullscreen, resolution) are hidden on mobile and
## web exports as well as while desktop mobile simulation is active.
static func show_desktop_settings() -> bool:
	return is_desktop_build() and not simulate_mobile_enabled()
