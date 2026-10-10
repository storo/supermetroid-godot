extends "res://tools/native_probe/campaign_test.gd"

const GREEN_SAVE := "user://native_green_route_test.srm"
const ROOMS := {0x92fd:"parlor",0x99bd:"pirates",0x9969:"mushrooms",0x9938:"elevator",0x9ad9:"arrival"}

func run() -> void:
	capture_prefix="native_green"
	var args := OS.get_cmdline_user_args()
	var index := args.find("--route-fixture")
	require(index>=0 and index+1<args.size(),"Missing green fixture")
	if index<0 or index+1>=args.size():return
	var directory: String=args[index+1]
	var inputs := FileAccess.get_file_as_bytes(directory.path_join("green.inputs"))
	var lines := FileAccess.get_file_as_string(directory.path_join("green.csv")).strip_edges().split("\n")
	var seed := FileAccess.get_file_as_bytes(directory.path_join("seed.srm"))
	require(seed.size()==8192 and inputs.size()>4000 and lines.size()==inputs.size()/2+1,"Complete original SRAM/input/state fixture")
	var seed_hash := FileAccess.get_sha256(directory.path_join("seed.srm"))
	var before := FileAccess.get_sha256(ROM)
	var save := FileAccess.open(GREEN_SAVE,FileAccess.WRITE)
	save.store_buffer(seed)
	save.close()
	extension_resource=load("res://native/sm_native.gdextension")
	core=ClassDB.instantiate("SmNativeCore")
	require(core.boot(ROM,GREEN_SAVE),"Reopen native station save: "+core.get_error())
	root.content_scale_size=Vector2i.ZERO
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
	renderer=Renderer.new()
	root.add_child(renderer)
	var rooms: Dictionary={}
	var ages: Dictionary={}
	var loaded: Dictionary={}
	var state: Dictionary
	var audible := 0
	var first_green_x := 0.0
	var moved := false
	for tick in range(inputs.size()/2):
		require(core.step(inputs.decode_u16(tick*2)),"Green native tick: "+core.get_error())
		state=core.get_state()
		var fields := lines[tick+1].split(",")
		require(fields.size()==25,"Green trace columns")
		require(state.frame==int(fields[0]) and state.state==int(fields[1]) and state.room==fields[2].hex_to_int(),"Green frame/state/room parity")
		require(state.position==Vector2(int(fields[3]),int(fields[4])) and state.pose==int(fields[5]) and state.health==int(fields[6]),"Green Samus parity")
		var values := [state.items,state.missiles,state.missile_capacity,state.selected_item,state.active_projectiles,state.room_kills,state.room_quota,state.event_flags.decode_u16(0),state.movement_type,state.room_state,state.boss_flags[0],state.active_bombs,state.max_health,state.save_station,state.save_slot,state.save_writes,state.area,state.supers]
		for i in range(values.size()):require(values[i]==int(fields[i+7]),"Green inventory/event/area parity at %d/%d" % [tick,i])
		if state.state==8:
			rooms[state.room]=true
			ages[state.room]=ages.get(state.room,0)+1
			if loaded.is_empty():
				loaded=state.duplicate(true)
				require(state.room==0x93d5 and state.area==0 and state.max_health==199 and state.items==0x1004 and state.save_station==1 and (state.boss_flags[0]&4)!=0 and (state.event_flags[0]&1)!=0,"Original station inventory and events loaded")
			if state.room==0x93d5 and state.pose in [1,2] and not captures.has("loaded"):await capture("loaded",state)
			if ROOMS.has(state.room) and ages[state.room]>=24 and not captures.has(ROOMS[state.room]):await capture(ROOMS[state.room],state)
			if state.room==0x9ad9:
				if ages[state.room]==1:first_green_x=state.position.x
				if absf(state.position.x-first_green_x)>20:moved=true
		if tick%180==0:
			for sample in core.get_audio():
				if sample!=Vector2.ZERO:
					audible+=1
					break
			await process_frame
	var complete: bool=state.state==8 and state.room==0x9ad9 and state.area==1 and state.health>0 and state.max_health==199 and state.items==0x1004 and moved and captures.size()==6
	require(complete,"Control in green Brinstar reached through native rooms/elevator")
	if not complete:return
	require(state.event_flags==loaded.event_flags and state.boss_flags==loaded.boss_flags,"Saved events and Bomb Torizo defeat retained")
	require(audible>10,"Native music/audio during saved-game continuation")
	await capture("control",state)
	require(FileAccess.get_sha256(directory.path_join("seed.srm"))==seed_hash,"Source SRAM unchanged")
	require(FileAccess.get_sha256(ROM)==before,"ROM unchanged")
	var report := {"frames":inputs.size()/2,"captures":captures,"rooms":rooms.keys(),"state_trace_matches":true,
		"original_station_sram_loaded":true,"seed_sha256":seed_hash,"source_seed_unchanged":true,
		"room":state.room,"area":state.area,"health":state.health,"max_health":state.max_health,
		"items":state.items,"missiles":state.missiles,"capacity":state.missile_capacity,"supers":state.supers,
		"saved_events_retained":true,"green_movement":moved,"audible_packets":audible,"rom_unchanged":true,
		"scope":"Original Crateria station SRAM, menu/load/control, Parlor ascent/bomb gate, Terminator, Green Pirates shaft, Lower Mushrooms, original elevator and green Brinstar arrival/control",
		"whole_campaign_verified":false}
	var file := FileAccess.open("res://docs/qa/native_green_route.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  ")+"\n")
	file.close()
	core.close()
	core=null
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GREEN_SAVE))
	print("GREEN_GODOT_OK: ",inputs.size()/2," saved-game ticks; native menu/station/Parlor/Terminator/pirates/mushrooms/elevator/green Brinstar control; C trace parity, source SRAM and ROM intact")
	quit()
