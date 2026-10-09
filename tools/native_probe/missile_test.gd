extends "res://tools/native_probe/campaign_test.gd"

const MISSILE_SAVE := "user://native_missile_route_test.srm"

func run() -> void:
	capture_prefix = "native_missile"
	var args := OS.get_cmdline_user_args()
	var index := args.find("--route-fixture")
	require(index>=0 and index+1<args.size(),"Missing missile fixture")
	if index<0 or index+1>=args.size():return
	var directory: String = args[index+1]
	var inputs := FileAccess.get_file_as_bytes(directory.path_join("missile.inputs"))
	var lines := FileAccess.get_file_as_string(directory.path_join("missile.csv")).strip_edges().split("\n")
	require(inputs.size()>43900 and inputs.size()%2==0 and lines.size()==inputs.size()/2+1,"Complete missile trace")
	extension_resource = load("res://native/sm_native.gdextension")
	require(extension_resource!=null and ClassDB.class_exists("SmNativeCore"),"Extension registration")
	core=ClassDB.instantiate("SmNativeCore")
	if FileAccess.file_exists(MISSILE_SAVE):DirAccess.remove_absolute(ProjectSettings.globalize_path(MISSILE_SAVE))
	var before := FileAccess.get_sha256(ROM)
	require(core.boot(ROM,MISSILE_SAVE),"Boot: "+core.get_error())
	if DisplayServer.get_name()!="headless":
		root.content_scale_size=Vector2i.ZERO
		root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
		renderer=Renderer.new()
		root.add_child(renderer)
	var rooms: Dictionary = {}
	var state: Dictionary
	var pickup := -1
	var fired := false
	var morph_rolled := false
	var audible := 0
	for tick in range(inputs.size()/2):
		require(core.step(inputs.decode_u16(tick*2)),"Missile tick %d: %s" % [tick,core.get_error()])
		state=core.get_state()
		var columns := lines[tick+1].split(",")
		require(state.frame==int(columns[0]) and state.state==int(columns[1]) and state.room==columns[2].hex_to_int(),"Missile frame/state/room parity at %d" % tick)
		require(state.position==Vector2(int(columns[3]),int(columns[4])) and state.pose==int(columns[5]) and state.health==int(columns[6]),"Missile Samus parity at %d" % tick)
		var values := [state.items,state.missiles,state.missile_capacity,state.selected_item,state.active_projectiles,state.room_kills,state.room_quota,state.event_flags.decode_u16(0),state.movement_type]
		for i in range(values.size()):require(values[i]==int(columns[i+7]),"Missile inventory/events/projectiles parity at tick %d column %d" % [tick,i+7])
		require(state.event_flags.size()==8 and state.boss_flags.size()==8,"Complete event/boss arrays")
		if state.state==8:
			rooms[state.room]=true
			if state.room==0x9e9f and state.items&4 and state.movement_type==4 and state.position.x>1160:morph_rolled=true
			if state.room==0x9f11 and state.position.y>250 and not captures.has("construction"):await capture("construction",state)
			if state.room==0xa107 and state.missile_capacity==5:
				if pickup<0:pickup=tick
				if tick-pickup>=80 and not captures.has("pickup"):await capture("pickup",state)
				if state.missiles<5 and state.active_projectiles>0:
					fired=true
					if not captures.has("fired"):await capture("fired",state)
		if tick%180==0:
			for sample in core.get_audio():
				if sample!=Vector2.ZERO:
					audible+=1
					break
			await process_frame
	for room in [0x9e9f,0x9f11,0xa107]:require(rooms.has(room),"Missile visited room %04x" % room)
	require(morph_rolled and fired and pickup>=0 and audible>10,"Morph, item acquisition, actual missile projectile and audio")
	require(state.state==8 and state.room==0xa107 and state.missile_capacity==5 and state.missiles==4 and state.selected_item==0 and state.position.x>120,"One missile fired, selection cancelled and movement after original message")
	require(captures.size()==3,"Construction/message/missile captures")
	await capture("control",state)
	var report := {"frames":inputs.size()/2,"state_trace_matches":true,"rooms":rooms.keys(),"captures":captures,"audible_packets":audible,"items":state.items,"capacity":state.missile_capacity,"missiles":state.missiles,"morph_rolling":morph_rolled,"missile_fired":fired,"selected_item":state.selected_item,"events":Array(state.event_flags),"rom_unchanged":FileAccess.get_sha256(ROM)==before,"whole_campaign_verified":false}
	require(report.rom_unchanged,"ROM unchanged")
	var file := FileAccess.open("res://docs/qa/native_missile_route.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  ")+"\n")
	file.close()
	core.close()
	core=null
	if FileAccess.file_exists(MISSILE_SAVE):DirAccess.remove_absolute(ProjectSettings.globalize_path(MISSILE_SAVE))
	print("MISSILE_GODOT_OK: %d ticks, Morph tunnel/Construction Zone/first missiles, original pickup message, missile fired and cancelled, exact input/state replay, intact ROM" % (inputs.size()/2))
	quit()
