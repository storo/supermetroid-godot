extends "res://tools/native_probe/campaign_test.gd"

const AWAKEN_SAVE := "user://native_awaken_route_test.srm"

func run() -> void:
	capture_prefix="native_awaken"
	var args := OS.get_cmdline_user_args()
	var index := args.find("--route-fixture")
	require(index>=0 and index+1<args.size(),"Missing awaken fixture")
	if index<0 or index+1>=args.size():return
	var directory: String=args[index+1]
	var inputs := FileAccess.get_file_as_bytes(directory.path_join("awaken.inputs"))
	var lines := FileAccess.get_file_as_string(directory.path_join("awaken.csv")).strip_edges().split("\n")
	require(inputs.size()>46800 and inputs.size()%2==0 and lines.size()==inputs.size()/2+1,"Complete return/combat trace")
	extension_resource=load("res://native/sm_native.gdextension")
	require(extension_resource!=null and ClassDB.class_exists("SmNativeCore"),"Extension registration")
	core=ClassDB.instantiate("SmNativeCore")
	if FileAccess.file_exists(AWAKEN_SAVE):DirAccess.remove_absolute(ProjectSettings.globalize_path(AWAKEN_SAVE))
	var before := FileAccess.get_sha256(ROM)
	require(core.boot(ROM,AWAKEN_SAVE),"Boot: "+core.get_error())
	if DisplayServer.get_name()!="headless":
		root.content_scale_size=Vector2i.ZERO
		root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
		renderer=Renderer.new()
		root.add_child(renderer)
	var rooms: Dictionary={}
	var state: Dictionary
	var saw_missiles := false
	var saw_unawakened_pirates := false
	var saw_wall_pirate := false
	var audible := 0
	for tick in range(inputs.size()/2):
		require(core.step(inputs.decode_u16(tick*2)),"Awaken tick %d: %s" % [tick,core.get_error()])
		state=core.get_state()
		var columns := lines[tick+1].split(",")
		require(state.frame==int(columns[0]) and state.state==int(columns[1]) and state.room==columns[2].hex_to_int(),"Awaken frame/state/room parity at %d" % tick)
		require(state.position==Vector2(int(columns[3]),int(columns[4])) and state.pose==int(columns[5]) and state.health==int(columns[6]),"Awaken Samus parity at %d" % tick)
		var values := [state.items,state.missiles,state.missile_capacity,state.selected_item,state.active_projectiles,state.room_kills,state.room_quota,state.event_flags.decode_u16(0),state.movement_type,state.room_state]
		for i in range(values.size()):require(values[i]==int(columns[i+7]),"Awaken inventory/event/room-state parity at tick %d column %d" % [tick,i+7])
		if state.state==8:
			rooms[state.room]=true
			if state.room==0xa107 and state.missile_capacity==5:saw_missiles=true
			if saw_missiles:
				if state.room==0x9f11 and state.position.y<250 and not captures.has("ascent"):await capture("ascent",state)
				if state.room==0x9e9f and not captures.has("return"):await capture("return",state)
				if state.room==0x975c and state.room_quota==5:
					if state.room_kills<5:
						require((state.event_flags[0]&1)==0,"Zebes stays asleep before the death quota")
						saw_unawakened_pirates=true
						for enemy in core.get_enemies():
							require(enemy.slot>=0 and enemy.slot<32 and enemy.health>0,"Live enemy read-only diagnostics")
							if enemy.id==0xf353:saw_wall_pirate=true
						if state.room_kills>0 and not captures.has("combat"):await capture("combat",state)
		if tick%180==0:
			for sample in core.get_audio():
				if sample!=Vector2.ZERO:
					audible+=1
					break
			await process_frame
	require(saw_missiles and saw_unawakened_pirates and saw_wall_pirate and audible>10,"Tank, sleeping Zebes, original wall pirate and audio")
	require(state.state==8 and state.room==0x975c and state.room_state==0x9787 and state.room_quota==5 and state.room_kills==5 and (state.event_flags[0]&1)!=0,"Original Pit quota awakened Zebes")
	for enemy in core.get_enemies():require(enemy.id!=0xf353 and enemy.id!=0xf653,"All five original pirates defeated")
	require(captures.size()==3,"Ascent/return/combat evidence")
	await capture("awake",state)
	var report := {"frames":inputs.size()/2,"state_trace_matches":true,"rooms":rooms.keys(),"captures":captures,"audible_packets":audible,"items":state.items,"capacity":state.missile_capacity,"missiles":state.missiles,"health":state.health,"room_state":state.room_state,"kills":state.room_kills,"quota":state.room_quota,"events":Array(state.event_flags),"zebes_awake":true,"rom_unchanged":FileAccess.get_sha256(ROM)==before,"whole_campaign_verified":false}
	require(report.rom_unchanged,"ROM unchanged")
	var file := FileAccess.open("res://docs/qa/native_awaken_route.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  ")+"\n")
	file.close()
	core.close()
	require(core.get_enemies().is_empty(),"Closed core exposes no enemies")
	core=null
	if FileAccess.file_exists(AWAKEN_SAVE):DirAccess.remove_absolute(ProjectSettings.globalize_path(AWAKEN_SAVE))
	print("AWAKEN_GODOT_OK: %d ticks, first missiles/return elevator/five original Pit pirates/death quota/Zebes event, exact input/state replay, intact ROM" % (inputs.size()/2))
	quit()
