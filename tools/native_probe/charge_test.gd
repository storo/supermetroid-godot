extends "res://tools/native_probe/campaign_test.gd"

const CHARGE_SAVE := "user://native_charge_route_test.srm"

func capture(name: String, state: Dictionary) -> void:
	var before: Dictionary=core.get_state()
	await super.capture(name,state)
	for field in ["missiles","missile_capacity","beams","beam_charge","charged_projectiles","time_frozen"]:captures[name][field]=state[field]
	require(core.get_state()==before,"Charge presentation leaves native state unchanged")
	captures[name].presentation_leaves_core_unchanged=true

func run() -> void:
	capture_prefix="native_charge"
	var args := OS.get_cmdline_user_args()
	var index := args.find("--route-fixture")
	require(index>=0 and index+1<args.size(),"Missing charge route fixture")
	var directory: String=args[index+1]
	var inputs := FileAccess.get_file_as_bytes(directory.path_join("charge.inputs"))
	var lines := FileAccess.get_file_as_string(directory.path_join("charge.csv")).strip_edges().split("\n")
	var seed := FileAccess.get_file_as_bytes(directory.path_join("seed.srm"))
	require(seed.size()==8192 and inputs.size()>16000 and lines.size()==inputs.size()/2+1,"Complete charge route trace")
	var seed_hash := FileAccess.get_sha256(directory.path_join("seed.srm"))
	var before := FileAccess.get_sha256(ROM)
	var save := FileAccess.open(CHARGE_SAVE,FileAccess.WRITE)
	save.store_buffer(seed)
	save.close()
	extension_resource=load("res://native/sm_native.gdextension")
	core=ClassDB.instantiate("SmNativeCore")
	require(core.boot(ROM,CHARGE_SAVE),"Original station save boot: "+core.get_error())
	root.content_scale_size=Vector2i.ZERO
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
	renderer=Renderer.new()
	root.add_child(renderer)
	var loaded: Dictionary={}
	var rooms: Dictionary={}
	var state: Dictionary
	var audible := 0
	var maximum_charge := 0
	var charge_frames := 0
	var charge_item_frame := 0
	var missile_frame := 0
	var final_ammo := -1
	for tick in range(inputs.size()/2):
		require(core.step(inputs.decode_u16(tick*2)),"Charge route native tick: "+core.get_error())
		state=core.get_state()
		var f := lines[tick+1].split(",")
		require(f.size()==29,"Charge trace columns")
		var values := [state.frame,state.state,state.room,state.position.x,state.position.y,state.pose,state.health,state.items,state.missiles,state.missile_capacity,state.selected_item,state.active_projectiles,state.room_kills,state.room_quota,state.event_flags.decode_u16(0),state.movement_type,state.room_state,state.boss_flags[0],state.active_bombs,state.max_health,state.save_station,state.save_slot,state.save_writes,state.area,state.supers,state.beams,state.beam_charge,state.charged_projectiles,state.time_frozen]
		for field in range(values.size()):
			var expected: int=f[field].hex_to_int() if field==2 else int(f[field])
			require(values[field]==expected,"Charge state parity at tick %d column %d" % [tick+1,field])
		if state.state==8:
			rooms[state.room]=true
			if loaded.is_empty():
				loaded=state.duplicate(true)
				require(state.room==0x93d5 and state.max_health==199 and state.items==0x1004 and state.beams==0,"Original station inventory loaded")
			if state.room==0x9d19:
				if not captures.has("arrival"):await capture("arrival",state)
				if state.missile_capacity==10 and missile_frame==0:
					missile_frame=state.frame
					require(state.missiles==5 and state.beams==0,"Original lower missile tank adds five rounds and capacity")
					await capture("missile",state)
				if missile_frame>0 and state.active_bombs>0 and state.position.y>1660 and state.position.y<1730 and not captures.has("bomb_passage"):await capture("bomb_passage",state)
				if missile_frame>0 and state.frame==missile_frame+60:await capture("missile_notice",state)
				if state.position.y>1760 and not captures.has("alcove"):await capture("alcove",state)
				if (state.beams&0x1000)!=0 and charge_item_frame==0:
					charge_item_frame=state.frame
					final_ammo=state.missiles
					await capture("charge_item",state)
				if charge_item_frame==0:require(state.beam_charge==0 and state.charged_projectiles==0,"Charge is unavailable before its original pickup")
				if charge_item_frame>0 and state.frame==charge_item_frame+60:await capture("charge_notice",state)
				if state.beam_charge>=60:
					maximum_charge=maxi(maximum_charge,state.beam_charge)
					if not captures.has("charging"):await capture("charging",state)
				if state.charged_projectiles>0:
					charge_frames+=1
					require(charge_item_frame>0 and maximum_charge>=60 and state.missiles==final_ammo,"Charged beam follows original charge threshold without missile consumption")
					if not captures.has("charged_shot"):await capture("charged_shot",state)
		if tick%180==0:
			for sample in core.get_audio():
				if sample!=Vector2.ZERO:
					audible+=1
					break
			await process_frame
	require(state.state==8 and state.room==0x9d19 and state.health>0 and state.max_health==199 and state.items==0x1004 and state.beams==0x1000 and state.missile_capacity==10 and state.missiles==5 and state.time_frozen==0,"Charge Beam and original control retained")
	require(captures.size()==9 and charge_frames>0 and maximum_charge>=60 and audible>10,"Pickup/bombs/charged projectile and audio evidence")
	require(state.event_flags==loaded.event_flags and state.boss_flags==loaded.boss_flags,"Saved events and boss flags retained")
	await capture("control",state)
	require(FileAccess.get_sha256(ROM)==before and FileAccess.get_sha256(directory.path_join("seed.srm"))==seed_hash,"Source ROM and SRAM unchanged")
	var report := {"frames":inputs.size()/2,"columns_compared_per_tick":29,"state_trace_matches":true,"rooms":rooms.keys(),"captures":captures,"missile_pickup_frame":missile_frame,"charge_pickup_frame":charge_item_frame,"maximum_charge_counter":maximum_charge,"charged_projectile_frames":charge_frames,"charged_beam_does_not_consume_missiles":true,"original_station_sram_loaded":true,"seed_sha256":seed_hash,"source_seed_unchanged":true,"rom_unchanged":true,"saved_events_retained":true,"room":state.room,"health":state.health,"max_health":state.max_health,"items":state.items,"beams":state.beams,"missiles":state.missiles,"capacity":state.missile_capacity,"audible_packets":audible,"whole_campaign_verified":false,"spore_spawn_verified":false}
	var output := FileAccess.open("res://docs/qa/native_charge_route.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"  ")+"\n")
	output.close()
	core.close()
	core=null
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CHARGE_SAVE))
	print("CHARGE_GODOT_OK: ",inputs.size()/2," ticks, 29 fields identical; lower missiles, bomb passage, Charge Beam and charged shot; whole campaign pending")
	quit()
