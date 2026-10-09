extends RefCounted

static func install_native() -> void:
	# Native gameplay keeps the SNES button roles, including Start/Select/Y.
	var keys := {"left":[KEY_A,KEY_LEFT],"right":[KEY_D,KEY_RIGHT],
		"up":[KEY_W,KEY_UP],"down":[KEY_S,KEY_DOWN],
		"jump":[KEY_SPACE,KEY_Z],"fire":[KEY_J,KEY_X],"run":[KEY_SHIFT],
		"aim_up":[KEY_Q],"aim_down":[KEY_E],"select":[KEY_K],
		"start":[KEY_ENTER],"cancel":[KEY_BACKSPACE]}
	for name in keys:
		var action: String = "native_"+name
		if not InputMap.has_action(action):InputMap.add_action(action)
		for key in keys[name]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			if not InputMap.action_has_event(action,event):InputMap.action_add_event(action,event)
	var buttons := {"left":JOY_BUTTON_DPAD_LEFT,"right":JOY_BUTTON_DPAD_RIGHT,
		"up":JOY_BUTTON_DPAD_UP,"down":JOY_BUTTON_DPAD_DOWN,
		"jump":JOY_BUTTON_A,"fire":JOY_BUTTON_X,"run":JOY_BUTTON_B,
		"cancel":JOY_BUTTON_Y,"aim_up":JOY_BUTTON_RIGHT_SHOULDER,
		"aim_down":JOY_BUTTON_LEFT_SHOULDER,"select":JOY_BUTTON_BACK,"start":JOY_BUTTON_START}
	for name in buttons:
		var action: String = "native_"+name
		var event := InputEventJoypadButton.new()
		event.button_index = buttons[name]
		if not InputMap.action_has_event(action,event):InputMap.action_add_event(action,event)
	for binding in [["left",JOY_AXIS_LEFT_X,-1.0],["right",JOY_AXIS_LEFT_X,1.0],
		["up",JOY_AXIS_LEFT_Y,-1.0],["down",JOY_AXIS_LEFT_Y,1.0]]:
		var action := "native_"+str(binding[0])
		var event := InputEventJoypadMotion.new()
		event.axis = binding[1]
		event.axis_value = binding[2]
		if not InputMap.action_has_event(action,event):InputMap.action_add_event(action,event)

static func install() -> void:
	var bindings := {
		"left": [KEY_A, KEY_LEFT], "right": [KEY_D, KEY_RIGHT],
		"up": [KEY_W, KEY_UP], "down": [KEY_S, KEY_DOWN],
		"jump": [KEY_SPACE, KEY_Z], "fire": [KEY_J, KEY_X],
		"missile": [KEY_K], "run": [KEY_SHIFT], "aim_up": [KEY_Q],
		"aim_down": [KEY_E], "morph": [KEY_C], "bomb": [KEY_B],
		"pause": [KEY_ESCAPE, KEY_P], "map": [KEY_TAB, KEY_M],
		"art": [KEY_F1], "catalog": [KEY_F4], "save": [KEY_F5],
		"load": [KEY_F9], "fullscreen": [KEY_F11], "restart": [KEY_R]
	}
	for action in bindings:
		if not InputMap.has_action(action): InputMap.add_action(action)
		for key in bindings[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action, event)
	var pad := {"jump":JOY_BUTTON_A,"fire":JOY_BUTTON_X,"missile":JOY_BUTTON_B,
		"run":JOY_BUTTON_RIGHT_SHOULDER,"aim_up":JOY_BUTTON_LEFT_SHOULDER,
		"morph":JOY_BUTTON_Y,"pause":JOY_BUTTON_START,"map":JOY_BUTTON_BACK}
	for action in pad:
		var event := InputEventJoypadButton.new()
		event.button_index = pad[action]
		InputMap.action_add_event(action,event)
	for binding in [["left",JOY_AXIS_LEFT_X,-1.0],["right",JOY_AXIS_LEFT_X,1.0],
		["up",JOY_AXIS_LEFT_Y,-1.0],["down",JOY_AXIS_LEFT_Y,1.0]]:
		var event := InputEventJoypadMotion.new()
		event.axis = binding[1]
		event.axis_value = binding[2]
		InputMap.action_add_event(binding[0],event)
