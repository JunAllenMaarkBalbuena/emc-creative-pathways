extends SceneTree

## Unit coverage for the on-screen joystick and its platform gating.
##
## Nothing else in the suite exercised this: the joystick only matters on a
## device with a touchscreen, so on desktop CI it was completely unverified.
## These drive it with synthetic InputEvents instead - the same objects a
## finger or a mouse produces - so the control's behaviour is checked
## everywhere, not just on hardware nobody has in CI.
##
## Under test:
##   1. A drag maps to a normalised direction, and the emitted value's length
##      is the fraction of the joystick radius.
##   2. Screen coords are respected: dragging up is -y, not +y.
##   3. The deadzone swallows a resting thumb's wobble.
##   4. Dragging past the radius clamps to full deflection instead of running
##      away, so holding off-centre cannot outrun normal movement speed.
##   5. Release zeroes the value, so the character actually stops.
##   6. Mouse drags work, because that is how touch controls get playtested on
##      a desktop build.
##   7. The runtime override the pause-menu button uses can force touch
##      controls on (desktop) and off (mobile/web), and clears back to the
##      platform default.

var _failed := 0

## Number of value_changed emissions seen. A member, not a local: GDScript
## lambdas capture locals by value, so assigning to a captured local inside
## the listener would never be visible out here.
var _signal_count := 0

## Last value reported through the signal.
var _signal_value := Vector2.ZERO


func _init() -> void:
	_test_drag_right_maps_to_half_radius()
	_test_drag_up_maps_to_negative_y()
	_test_deadzone_zeroes_small_drift()
	_test_drag_past_radius_clamps_to_full()
	_test_release_returns_to_zero()
	_test_mouse_drag_works()
	_test_reset_stops_a_deflected_joystick()
	_test_reset_clears_dragging()
	_test_reset_on_neutral_joystick_is_silent()
	_test_platform_override()
	quit(_failed)


func _fail(msg: String) -> void:
	_failed += 1
	print("FAIL: " + msg)


func _pass(msg: String) -> void:
	print("PASS: " + msg)


## A joystick attached to the tree, sized so _update_value's centre is real.
##
## Inside SceneTree._init no layout pass has run yet, so `size` is still
## (0,0) and the control would measure every touch from its top-left corner.
## _ready() has already set custom_minimum_size by the time add_child returns,
## so assigning size here is deterministic rather than dependent on when the
## first frame happens to be processed.
func _joy() -> EMCMobileJoystick:
	var joy := EMCMobileJoystick.new()
	root.add_child(joy)
	joy.size = Vector2(joy.radius * 2.0, joy.radius * 2.0)
	joy.value_changed.connect(_on_value_changed)
	return joy


func _on_value_changed(value: Vector2) -> void:
	_signal_count += 1
	_signal_value = value


## The centre a neutral touch sits on, matching _update_value's own maths.
func _centre(joy: EMCMobileJoystick) -> Vector2:
	return joy.size * 0.5


func _touch(pressed: bool, point: Vector2) -> InputEventScreenTouch:
	var ev := InputEventScreenTouch.new()
	ev.index = 0
	ev.pressed = pressed
	ev.position = point
	return ev


func _test_drag_right_maps_to_half_radius() -> void:
	var joy := _joy()
	joy._gui_input(_touch(true, _centre(joy) + Vector2(joy.radius * 0.5, 0.0)))
	if joy._value.x <= 0.0:
		_fail("dragging right should report +x, got %s" % str(joy._value))
		return
	if absf(joy._value.y) > 0.001:
		_fail("a purely horizontal drag should not report y, got %s" % str(joy._value))
		return
	if absf(joy._value.length() - 0.5) > 0.01:
		_fail("half the radius should read 0.5, got %.3f" % joy._value.length())
		return
	if _signal_count != 1:
		_fail("a drag should emit value_changed once, got %d" % _signal_count)
		return
	joy.queue_free()
	_pass("drag right maps to +x at half the radius")


func _test_drag_up_maps_to_negative_y() -> void:
	var joy := _joy()
	joy._gui_input(_touch(true, _centre(joy) + Vector2(0.0, -joy.radius * 0.5)))
	if joy._value.y >= 0.0:
		_fail("dragging up should report -y in screen coords, got %s" % str(joy._value))
		return
	joy.queue_free()
	_pass("drag up maps to -y")


func _test_deadzone_zeroes_small_drift() -> void:
	var joy := _joy()
	# 3% of the radius is well under the 0.12 deadzone - a resting thumb.
	joy._gui_input(_touch(true, _centre(joy) + Vector2(joy.radius * 0.03, 0.0)))
	if joy._value != Vector2.ZERO:
		_fail("movement inside the deadzone should read zero, got %s" % str(joy._value))
		return
	joy.queue_free()
	_pass("deadzone swallows a resting thumb")


func _test_drag_past_radius_clamps_to_full() -> void:
	var joy := _joy()
	# A finger that slides off the edge of the control must not report a
	# magnitude above 1, or movement outruns movement_speed.
	joy._gui_input(_touch(true, _centre(joy) + Vector2(joy.radius * 6.0, 0.0)))
	if joy._value.length() > 1.001:
		_fail("drag past the radius should clamp to unit length, got %.3f" % joy._value.length())
		return
	if joy._value.length() < 0.99:
		_fail("a drag well past the radius should read full deflection, got %.3f" % joy._value.length())
		return
	joy.queue_free()
	_pass("drag past the radius clamps to full deflection")


func _test_release_returns_to_zero() -> void:
	var joy := _joy()
	joy._gui_input(_touch(true, _centre(joy) + Vector2(joy.radius * 0.6, 0.0)))
	if joy._value.is_zero_approx():
		_fail("precondition: joystick should be deflected before release")
		return
	# The release position is ignored by design; the control re-centres itself.
	joy._gui_input(_touch(false, Vector2.ZERO))
	if not joy._value.is_zero_approx():
		_fail("release should zero the value so the character stops, got %s" % str(joy._value))
		return
	if not _signal_value.is_zero_approx():
		_fail("release should emit a zero value, got %s" % str(_signal_value))
		return
	joy.queue_free()
	_pass("release zeroes the value and emits zero")


func _test_mouse_drag_works() -> void:
	# The desktop playtest path: mouse_enabled turns the joystick into a
	# mouse-draggable control, since a desktop build has no touchscreen.
	var joy := _joy()
	if not joy.mouse_enabled:
		_fail("precondition: mouse_enabled should default on for desktop playtesting")
		return
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = _centre(joy) + Vector2(joy.radius * 0.5, 0.0)
	joy._gui_input(press)
	var motion := InputEventMouseMotion.new()
	motion.position = _centre(joy) + Vector2(0.0, -joy.radius * 0.5)
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	joy._gui_input(motion)
	if joy._value.y >= 0.0:
		_fail("a mouse drag up should report -y, got %s" % str(joy._value))
		return
	joy.queue_free()
	_pass("mouse drag deflects the joystick for desktop playtesting")


func _test_reset_stops_a_deflected_joystick() -> void:
	# The bug this guards: the joystick is hidden while deflected (dialogue
	# opens, or touch controls toggled off), so the finger lift lands on
	# nothing and _value would stay deflected forever. PlayerController only
	# adopts the virtual value when it is longer than the keyboard's, so a
	# stranded _value of length 1 pins the character into a permanent walk.
	var joy := _joy()
	joy._gui_input(_touch(true, _centre(joy) + Vector2(joy.radius * 0.8, 0.0)))
	if joy._value.is_zero_approx():
		_fail("precondition: joystick should be deflected before reset")
		return
	joy.reset()
	if not joy._value.is_zero_approx():
		_fail("reset should zero the value so the character stops, got %s" % str(joy._value))
		return
	if not _signal_value.is_zero_approx():
		_fail("reset should emit zero - PlayerController only hears movement via this signal, got %s" % str(_signal_value))
		return
	joy.queue_free()
	_pass("reset zeroes a deflected joystick and emits zero")


func _test_reset_clears_dragging() -> void:
	# Without clearing _dragging, a drag event arriving after reset would be
	# honoured and re-deflect a joystick the player believes is neutral.
	var joy := _joy()
	joy._gui_input(_touch(true, _centre(joy) + Vector2(joy.radius * 0.8, 0.0)))
	joy.reset()
	var drag := InputEventScreenDrag.new()
	drag.position = _centre(joy) + Vector2(0.0, -joy.radius * 0.5)
	joy._gui_input(drag)
	if not joy._value.is_zero_approx():
		_fail("a drag after reset should be ignored, got %s" % str(joy._value))
		return
	joy.queue_free()
	_pass("reset clears the drag flag so stale drags cannot re-deflect")


func _test_reset_on_neutral_joystick_is_silent() -> void:
	# reset() runs on every dialogue start, so on a neutral stick it must not
	# spam value_changed with redundant zeros.
	var joy := _joy()
	var before := _signal_count
	joy.reset()
	joy.reset()
	if _signal_count != before:
		_fail("reset on an already-neutral joystick should emit nothing, got %d extra emissions" % (_signal_count - before))
		return
	joy.queue_free()
	_pass("reset on a neutral joystick emits nothing")


func _test_platform_override() -> void:
	# Restores the platform default at the end so the override cannot leak
	# into anything that runs after this case.
	var default_value := Platform.wants_touch_controls()

	Platform.set_touch_controls_override(true)
	if not Platform.wants_touch_controls():
		_fail("override true should force touch controls on, got false")
		Platform.set_touch_controls_override(null)
		return

	Platform.set_touch_controls_override(false)
	if Platform.wants_touch_controls():
		_fail("override false should force touch controls off, got true")
		Platform.set_touch_controls_override(null)
		return

	Platform.set_touch_controls_override(null)
	if Platform.wants_touch_controls() != default_value:
		_fail("clearing the override should restore the platform default")
		return
	_pass("platform override forces touch controls and clears cleanly")