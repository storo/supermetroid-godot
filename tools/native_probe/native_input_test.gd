extends SceneTree

const Setup = preload("res://scripts/input_setup.gd")
const Campaign = preload("res://scripts/native_campaign.gd")
var campaign: Control

func check(condition: bool, detail: String) -> void:
	if not condition:
		push_error("NATIVE_INPUT_FAILED: "+detail)
		quit(1)
		assert(false,detail)

func key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode=code
	event.pressed=pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func button(code: int, pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index=code
	event.pressed=pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func axis(code: int, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.axis=code
	event.axis_value=value
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _initialize() -> void:
	Setup.install()
	Setup.install_native()
	var count := 0
	for name in Campaign.BUTTONS:count+=InputMap.action_get_events("native_"+name).size()
	Setup.install_native()
	var repeated_count := 0
	for name in Campaign.BUTTONS:repeated_count+=InputMap.action_get_events("native_"+name).size()
	check(count==repeated_count,"Bindings duplicate on reopening campaign")
	# Construct the controller without entering the scene tree or booting a ROM.
	campaign=Campaign.new()
	check(campaign.joypad()==0,"Initial buttons released")
	for pair in [[KEY_K,0x2000],[KEY_ENTER,0x1000],[KEY_BACKSPACE,0x4000],
		[KEY_SHIFT,0x8000],[KEY_Q,0x10],[KEY_E,0x20],[KEY_SPACE,0x80],[KEY_J,0x40]]:
		key(pair[0],true)
		check(campaign.joypad()==pair[1],"Keyboard button %d" % pair[0])
		key(pair[0],false)
		check(campaign.joypad()==0,"Keyboard release")
	for pair in [[JOY_BUTTON_A,0x80],[JOY_BUTTON_B,0x8000],[JOY_BUTTON_X,0x40],
		[JOY_BUTTON_Y,0x4000],[JOY_BUTTON_START,0x1000],[JOY_BUTTON_BACK,0x2000],
		[JOY_BUTTON_LEFT_SHOULDER,0x20],[JOY_BUTTON_RIGHT_SHOULDER,0x10],
		[JOY_BUTTON_DPAD_LEFT,0x200],[JOY_BUTTON_DPAD_RIGHT,0x100],
		[JOY_BUTTON_DPAD_UP,0x800],[JOY_BUTTON_DPAD_DOWN,0x400]]:
		button(pair[0],true)
		check(campaign.joypad()==pair[1],"Controller button %d" % pair[0])
		button(pair[0],false)
		check(campaign.joypad()==0,"Controller release")
	button(JOY_BUTTON_B,true)
	button(JOY_BUTTON_A,true)
	button(JOY_BUTTON_DPAD_RIGHT,true)
	check(campaign.joypad()==0x8180,"Run, jump and right can be combined")
	button(JOY_BUTTON_B,false)
	button(JOY_BUTTON_A,false)
	button(JOY_BUTTON_DPAD_RIGHT,false)
	axis(JOY_AXIS_LEFT_X,0.8)
	check(campaign.joypad()==0x100,"Stick right")
	axis(JOY_AXIS_LEFT_X,-0.8)
	axis(JOY_AXIS_LEFT_Y,-0.8)
	check(campaign.joypad()==0xa00,"Stick upper-left diagonal")
	axis(JOY_AXIS_LEFT_X,0.05)
	axis(JOY_AXIS_LEFT_Y,0.05)
	check(campaign.joypad()==0,"Stick deadzone")
	campaign.free()
	print("NATIVE_INPUT_OK: actual key/gamepad/stick events, twelve SNES buttons, combinations, release, deadzone, idempotent bindings")
	quit()
