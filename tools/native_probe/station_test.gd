extends "res://tools/native_probe/campaign_test.gd"

const STATION_SAVE := "user://native_station_route_test.srm"

func run() -> void:
	capture_prefix="native_station"
	var args := OS.get_cmdline_user_args()
	var index := args.find("--route-fixture")
	require(index>=0 and index+1<args.size(),"Missing station fixture")
	if index<0 or index+1>=args.size():return
	var directory: String=args[index+1]
	var inputs := FileAccess.get_file_as_bytes(directory.path_join("station.inputs"))
	var lines := FileAccess.get_file_as_string(directory.path_join("station.csv")).strip_edges().split("\n")
	require(inputs.size()>140000 and inputs.size()%2==0 and lines.size()==inputs.size()/2+1,"Complete energy/save trace")
	extension_resource=load("res://native/sm_native.gdextension")
	require(extension_resource!=null and ClassDB.class_exists("SmNativeCore"),"Extension registration")
	core=ClassDB.instantiate("SmNativeCore")
	if FileAccess.file_exists(STATION_SAVE):DirAccess.remove_absolute(ProjectSettings.globalize_path(STATION_SAVE))
	var before := FileAccess.get_sha256(ROM)
	require(core.boot(ROM,STATION_SAVE),"Boot: "+core.get_error())
	if DisplayServer.get_name()!="headless":
		root.content_scale_size=Vector2i.ZERO
		root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
		renderer=Renderer.new()
		root.add_child(renderer)
	var rooms: Dictionary={}
	var state: Dictionary
	var pickup := -1
	var baseline_writes := -1
	var saved := false
	var audible := 0
	for tick in range(inputs.size()/2):
		require(core.step(inputs.decode_u16(tick*2)),"Station tick %d: %s" % [tick,core.get_error()])
		state=core.get_state()
		var columns := lines[tick+1].split(",")
		require(columns.size()==23,"Station trace columns")
		require(state.frame==int(columns[0]) and state.state==int(columns[1]) and state.room==columns[2].hex_to_int(),"Station frame/state/room parity at %d" % tick)
		require(state.position==Vector2(int(columns[3]),int(columns[4])) and state.pose==int(columns[5]) and state.health==int(columns[6]),"Station Samus parity at %d" % tick)
		var values := [state.items,state.missiles,state.missile_capacity,state.selected_item,state.active_projectiles,state.room_kills,state.room_quota,state.event_flags.decode_u16(0),state.movement_type,state.room_state,state.boss_flags[0],state.active_bombs,state.max_health,state.save_station,state.save_slot,state.save_writes]
		for i in range(values.size()):require(values[i]==int(columns[i+7]),"Station inventory/save parity at tick %d column %d" % [tick,i+7])
		if state.state==8:
			rooms[state.room]=true
			if state.boss_flags[0]&4:
				require((state.items&0x1000)!=0 and (state.event_flags[0]&1)!=0,"Bombs and awake event retained after boss")
				if state.room==0x9879 and not captures.has("exit"):await capture("exit",state)
				if state.room==0x92fd and state.position.x>960 and state.position.y<200 and state.active_bombs>0 and not captures.has("barrier"):await capture("barrier",state)
			if state.room==0x990d and state.max_health==199:
				if pickup<0:pickup=tick
				if tick-pickup>=80 and not captures.has("tank"):await capture("tank",state)
			if state.room==0x93d5:
				if baseline_writes<0:baseline_writes=state.save_writes
				if not captures.has("station"):await capture("station",state)
				if state.save_writes>baseline_writes:saved=true
		if tick%180==0:
			for sample in core.get_audio():
				if sample!=Vector2.ZERO:
					audible+=1
					break
			await process_frame
	require(pickup>=0 and saved and audible>10,"Native tank pickup and save station write with audio")
	require(state.state==8 and state.room==0x93d5 and state.max_health==199 and state.save_station==1 and state.save_slot==0 and state.movement_type==0 and state.pose in [1,2],"Standing control after saving at Crateria station 1")
	require(captures.size()==4,"Exit/barrier/tank/station captures")
	await capture("saved",state)
	var saved_state: Dictionary=state.duplicate(true)
	var save_bytes := FileAccess.get_file_as_bytes(STATION_SAVE)
	require(save_bytes.size()==8192,"Original 8192-byte SRAM format")
	var save_hash := FileAccess.get_sha256(STATION_SAVE)
	require(save_hash==FileAccess.get_sha256(directory.path_join("station.srm")),"Godot and C wrote identical SRAM bytes")
	var seed := FileAccess.open(directory.path_join("reload_seed.srm"),FileAccess.WRITE)
	seed.store_buffer(save_bytes)
	seed.close()
	core.close()
	require(FileAccess.get_sha256(STATION_SAVE)==save_hash,"Closing does not replace the station save")
	require(core.boot(ROM,STATION_SAVE),"Reopen saved game: "+core.get_error())
	var load_inputs := PackedByteArray()
	var loaded_age := 0
	var first_loaded_x := 0.0
	var moved := false
	for tick in range(12000):
		var joy := 0x1080 if tick%60<2 else 0
		if loaded_age>0:
			# The original station materialization keeps Samus facing forward
			# before restoring control; wait for it before testing movement.
			joy=0 if loaded_age<400 else 0x100 if loaded_age<430 else 0x200 if loaded_age<460 else 0
		load_inputs.append(joy&255)
		load_inputs.append(joy>>8)
		require(core.step(joy),"Reload tick %d: %s" % [tick,core.get_error()])
		state=core.get_state()
		if state.state==8:
			require(state.room==0x93d5 and state.area==0 and state.save_station==1,"Reload starts at saved Crateria station")
			require(state.items==saved_state.items and state.max_health==199 and state.health==saved_state.health and state.missiles==saved_state.missiles and state.missile_capacity==saved_state.missile_capacity,"Inventory, energy and ammunition survived close/reopen")
			require(state.event_flags==saved_state.event_flags and state.boss_flags==saved_state.boss_flags,"Events and defeated boss survived close/reopen")
			if loaded_age==0:first_loaded_x=state.position.x
			if absf(state.position.x-first_loaded_x)>12:moved=true
			loaded_age+=1
			if loaded_age>=500:break
		if tick%180==0:await process_frame
	var loaded_ok := loaded_age>=500 and moved
	require(loaded_ok,"Controllable gameplay after loading")
	if not loaded_ok:return
	await capture("loaded",state)
	var load_file := FileAccess.open(directory.path_join("reload.inputs"),FileAccess.WRITE)
	load_file.store_buffer(load_inputs)
	load_file.close()
	var report := {"frames":inputs.size()/2,"reload_frames":load_inputs.size()/2,"state_trace_matches":true,"rooms":rooms.keys(),"captures":captures,"audible_packets":audible,"items":saved_state.items,"health":saved_state.health,"max_health":saved_state.max_health,"missiles":saved_state.missiles,"capacity":saved_state.missile_capacity,"save_station":saved_state.save_station,"save_slot":saved_state.save_slot,"save_writes":saved_state.save_writes,"sram_bytes":save_bytes.size(),"sram_sha256":save_hash,"c_and_godot_sram_identical":true,"inventory_events_restored":true,"loaded_movement":moved,"rom_unchanged":FileAccess.get_sha256(ROM)==before,"whole_campaign_verified":false}
	require(report.rom_unchanged,"ROM unchanged")
	var file := FileAccess.open("res://docs/qa/native_station_route.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  ")+"\n")
	file.close()
	core.close()
	core=null
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STATION_SAVE))
	print("STATION_GODOT_OK: %d fresh-game ticks, grey exit/bomb barrier/energy tank/save station, identical native SRAM, close/reopen inventory+event persistence and movement" % (inputs.size()/2))
	quit()
