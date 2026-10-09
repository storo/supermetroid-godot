extends "res://tools/native_probe/campaign_test.gd"

const BOMB_SAVE := "user://native_bomb_route_test.srm"

func run() -> void:
	capture_prefix="native_bomb"
	var args := OS.get_cmdline_user_args()
	var index := args.find("--route-fixture")
	require(index>=0 and index+1<args.size(),"Missing bomb fixture")
	if index<0 or index+1>=args.size():return
	var directory: String=args[index+1]
	var inputs := FileAccess.get_file_as_bytes(directory.path_join("bomb.inputs"))
	var lines := FileAccess.get_file_as_string(directory.path_join("bomb.csv")).strip_edges().split("\n")
	require(inputs.size()>66000 and inputs.size()%2==0 and lines.size()==inputs.size()/2+1,"Complete bomb trace")
	extension_resource=load("res://native/sm_native.gdextension")
	require(extension_resource!=null and ClassDB.class_exists("SmNativeCore"),"Extension registration")
	core=ClassDB.instantiate("SmNativeCore")
	if FileAccess.file_exists(BOMB_SAVE):DirAccess.remove_absolute(ProjectSettings.globalize_path(BOMB_SAVE))
	var before := FileAccess.get_sha256(ROM)
	require(core.boot(ROM,BOMB_SAVE),"Boot: "+core.get_error())
	if DisplayServer.get_name()!="headless":
		root.content_scale_size=Vector2i.ZERO
		root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
		renderer=Renderer.new()
		root.add_child(renderer)
	var rooms: Dictionary={}
	var state: Dictionary
	var awake := false
	var flyway_missiles := 0
	var previous_missiles := 5
	var pickup := -1
	var boss_initial_health := 0
	var boss_min_health := 65535
	var bomb_placed := false
	var audible := 0
	for tick in range(inputs.size()/2):
		require(core.step(inputs.decode_u16(tick*2)),"Bomb tick %d: %s" % [tick,core.get_error()])
		state=core.get_state()
		var columns := lines[tick+1].split(",")
		require(columns.size()==19,"Bomb trace columns")
		require(state.frame==int(columns[0]) and state.state==int(columns[1]) and state.room==columns[2].hex_to_int(),"Bomb frame/state/room parity at %d" % tick)
		require(state.position==Vector2(int(columns[3]),int(columns[4])) and state.pose==int(columns[5]) and state.health==int(columns[6]),"Bomb Samus parity at %d" % tick)
		var values := [state.items,state.missiles,state.missile_capacity,state.selected_item,state.active_projectiles,state.room_kills,state.room_quota,state.event_flags.decode_u16(0),state.movement_type,state.room_state,state.boss_flags[0],state.active_bombs]
		for i in range(values.size()):require(values[i]==int(columns[i+7]),"Bomb inventory/event/projectile parity at tick %d column %d" % [tick,i+7])
		if state.event_flags[0]&1:awake=true
		if awake:require((state.event_flags[0]&1)!=0,"Awakening event persists")
		if state.state==8:
			rooms[state.room]=true
			if awake and state.room==0x96ba and state.room_kills>0 and not captures.has("climb"):await capture("climb",state)
			if awake and state.room==0x92fd and state.position.x>800 and state.movement_type==4 and not captures.has("passage"):await capture("passage",state)
			if state.room==0x9879:
				if state.missiles<previous_missiles:flyway_missiles+=previous_missiles-state.missiles
				if state.selected_item==1 and state.active_projectiles>0 and not captures.has("red_door"):await capture("red_door",state)
			if state.room==0x9804:
				if state.items&0x1000:
					if pickup<0:pickup=tick
					if tick-pickup>=80 and not captures.has("pickup"):await capture("pickup",state)
				for enemy in core.get_enemies():
					if enemy.id==0xeeff:
						if boss_initial_health==0:boss_initial_health=enemy.health
						boss_min_health=mini(boss_min_health,enemy.health)
						if enemy.health<boss_initial_health and not captures.has("combat"):await capture("combat",state)
				if state.active_bombs>0 and not bomb_placed:
					require((state.items&0x1000)!=0 and state.movement_type in [4,8],"Original bomb placed from Morph Ball after pickup")
					bomb_placed=true
					if not captures.has("bomb"):await capture("bomb",state)
		previous_missiles=state.missiles
		if tick%180==0:
			for sample in core.get_audio():
				if sample!=Vector2.ZERO:
					audible+=1
					break
			await process_frame
	for room in [0x96ba,0x92fd,0x9879,0x9804]:require(rooms.has(room),"Bomb route room %04x" % room)
	require(awake and flyway_missiles==5 and pickup>=0 and boss_initial_health==800 and boss_min_health<800 and bomb_placed and audible>10,"Awake Zebes, five missile red door, native bomb pickup/placement, boss damage and audio")
	require(state.state==8 and state.room==0x9804 and (state.items&0x1000)!=0 and (state.boss_flags[0]&4)!=0 and state.health>0 and state.movement_type==0 and state.active_bombs==0,"Bomb Torizo defeated, placed bomb finished and standing control restored")
	for enemy in core.get_enemies():require(enemy.id!=0xeeff,"No surviving Bomb Torizo")
	require(captures.size()==6,"Climb/passage/red door/pickup/combat/bomb captures")
	await capture("defeated",state)
	var report := {"frames":inputs.size()/2,"state_trace_matches":true,"rooms":rooms.keys(),"captures":captures,"audible_packets":audible,"items":state.items,"health":state.health,"missiles":state.missiles,"capacity":state.missile_capacity,"events":Array(state.event_flags),"bosses":Array(state.boss_flags),"flyway_missiles_fired":flyway_missiles,"boss_initial_health":boss_initial_health,"boss_min_live_health":boss_min_health,"bomb_placed":bomb_placed,"bomb_torizo_defeated":true,"rom_unchanged":FileAccess.get_sha256(ROM)==before,"whole_campaign_verified":false}
	require(report.rom_unchanged,"ROM unchanged")
	var file := FileAccess.open("res://docs/qa/native_bomb_route.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  ")+"\n")
	file.close()
	core.close()
	require(core.get_enemies().is_empty(),"Closed core has no enemies")
	core=null
	if FileAccess.file_exists(BOMB_SAVE):DirAccess.remove_absolute(ProjectSettings.globalize_path(BOMB_SAVE))
	print("BOMB_GODOT_OK: %d ticks, awake Climb/Parlor/Morph passage/red missile door/native bombs/Bomb Torizo/bomb placement, exact replay and intact ROM" % (inputs.size()/2))
	quit()
