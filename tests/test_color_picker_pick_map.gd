extends SceneTree

## Guard: clicking the wheel must return the SAME hue the wheel visually draws
## at that spot. The draw maps screen angle a -> hue a/TAU (blue sits at 240 deg).
## The old pick used raw atan2 which returns NEGATIVE angles for the upper half
## (240..360 deg), so blue picked as hue -0.333 == MAGENTA. Fix normalizes the
## angle into [0, TAU).

const ColorPickerControl := preload("res://scripts/digital_art_lab/color_picker_control.gd")


func _initialize() -> void:
	_run()


func _run() -> void:
	var fail := 0
	var wheel := ColorPickerControl.new()
	root.add_child(wheel)
	await process_frame

	# Wheel is drawn centered at (radius + spacing, radius + spacing + 20).
	var center := Vector2(wheel.wheel_radius + wheel.spacing,
		wheel.wheel_radius + wheel.spacing + 20.0)

	# (screen_deg, expected_pick_hue) — screen angle measured as the draw does:
	# 0=right, 90=down, 180=left, 270=up. Blue is at 240 deg.
	var cases := [
		[0.0, 0.0],       # red
		[60.0, 0.1667],   # yellow
		[120.0, 0.3333],  # green (down)
		[180.0, 0.5],     # cyan
		[210.0, 0.5833],  # sky-blue
		[240.0, 0.6667],  # BLUE
		[270.0, 0.75],    # violet/indigo
		[300.0, 0.8333],  # magenta
		[90.0, 0.25],     # chartreuse
	]
	for c in cases:
		var deg: float = c[0]
		var want_h: float = c[1]
		var a := deg_to_rad(deg)
		var click := center + Vector2(cos(a), sin(a)) * (wheel.wheel_radius * 0.8)
		wheel._pick_wheel(click - center)
		var got_h: float = wheel.get_color().h
		if absf(got_h - want_h) > 0.01:
			fail += 1
			print("FAIL: click at ", deg, "deg picked hue ", got_h,
				" (color ", wheel.get_color().to_html(), ") expected ", want_h)

	if fail == 0:
		print("PASS: wheel pick matches draw for all 9 angles (blue is blue)")
	quit(1 if fail > 0 else 0)