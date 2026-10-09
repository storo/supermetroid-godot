extends "res://tools/native_probe/campaign_test.gd"

const ZEBES_SAVE := "user://native_zebes_route_test.srm"

func run() -> void:
	capture_prefix = "native_zebes"
	var args := OS.get_cmdline_user_args()
	var index := args.find("--route-fixture")
	require(index>=0 and index+1<args.size(),"Missing --route-fixture directory")
	if index<0 or index+1>=args.size():return
	var directory: String = args[index+1]
	var inputs := FileAccess.get_file_as_bytes(directory.path_join("zebes.inputs"))
	var lines := FileAccess.get_file_as_string(directory.path_join("zebes.csv")).strip_edges().split("\n")
	require(inputs.size()>32000 and inputs.size()%2==0 and lines.size()==inputs.size()/2+1,"Complete Zebes trace")
	extension_resource = load("res://native/sm_native.gdextension")
	require(extension_resource!=null and ClassDB.class_exists("SmNativeCore"),"Extension registration")
	core = ClassDB.instantiate("SmNativeCore")
	if FileAccess.file_exists(ZEBES_SAVE):DirAccess.remove_absolute(ProjectSettings.globalize_path(ZEBES_SAVE))
	var before := FileAccess.get_sha256(ROM)
	require(core.boot(ROM,ZEBES_SAVE),"Boot: "+core.get_error())
	if DisplayServer.get_name()!="headless":
		root.content_scale_size = Vector2i.ZERO
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
		renderer = Renderer.new()
		root.add_child(renderer)
	var rooms: Dictionary = {}
	var state: Dictionary
	var audible := 0
	for tick in range(inputs.size()/2):
		require(core.step(inputs.decode_u16(tick*2)),"Zebes tick %d: %s" % [tick,core.get_error()])
		state = core.get_state()
		var columns := lines[tick+1].split(",")
		require(state.frame==int(columns[0]) and state.state==int(columns[1]) and state.room==columns[2].hex_to_int(),"Zebes frame/state/room parity at %d" % tick)
		require(state.position==Vector2(int(columns[3]),int(columns[4])) and state.pose==int(columns[5]) and state.health==int(columns[6]),"Zebes Samus parity at %d" % tick)
		require(state.items==int(columns[7]) and state.missiles==int(columns[8]) and state.y_direction==int(columns[9]) and state.y_speed==int(columns[10]) and state.movement_type==int(columns[11]),"Zebes inventory/movement parity at %d" % tick)
		if state.state==8:
			rooms[state.room]=true
			if state.room==0x92fd and state.position.y>300 and not captures.has("parlor"):await capture("parlor",state)
			if state.room==0x96ba and state.position.y>1000 and not captures.has("climb"):await capture("climb",state)
			if state.room==0x9e9f and state.position.y>580 and not captures.has("brinstar"):await capture("brinstar",state)
		if tick%180==0:
			for sample in core.get_audio():
				if sample!=Vector2.ZERO:
					audible+=1
					break
			await process_frame
	for room in [0x91f8,0x92fd,0x96ba,0x975c,0x97b5,0x9e9f]:require(rooms.has(room),"Zebes visited room %04x" % room)
	require(state.state==8 and state.room==0x9e9f and state.items&4 and state.movement_type==4 and state.position.x>1160 and state.position.y>=680,"Morph Ball acquired via original PLM and rolled with normal controls")
	require(captures.size()==3 and audible>10,"Zebes render/audio evidence")
	await capture("morph",state)
	var report := {"frames":inputs.size()/2,"state_trace_matches":true,"rooms":rooms.keys(),"captures":captures,"audible_packets":audible,"items":state.items,"missiles":state.missiles,"morph_rolling":true,"final_pose":state.pose,"final_position":state.position,"rom_unchanged":FileAccess.get_sha256(ROM)==before,"whole_campaign_verified":false}
	require(report.rom_unchanged,"ROM unchanged")
	var file := FileAccess.open("res://docs/qa/native_zebes_route.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  ")+"\n")
	file.close()
	core.close()
	core=null
	if FileAccess.file_exists(ZEBES_SAVE):DirAccess.remove_absolute(ProjectSettings.globalize_path(ZEBES_SAVE))
	print("ZEBES_GODOT_OK: %d ticks, Landing/Parlor/Climb/Pit/elevator/Brinstar/Morph Ball, acquisition and rolling, exact input/state replay, intact ROM" % (inputs.size()/2))
	quit()
