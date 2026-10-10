extends "res://tools/native_probe/campaign_test.gd"

const ASCENT_SAVE := "user://native_pink_ascent_test.srm"
const PREFIX_FRAME := 10072
var output_view: SubViewport

func capture(name: String, state: Dictionary) -> void:
	var before: Dictionary=core.get_state()
	var snapshot: Dictionary=core.get_snapshot()
	for size in [1,2]:
		output_view.size=Vector2i(256,224)*size
		renderer.scale=Vector2.ONE*size
		renderer.enhanced=size==2
		renderer.present(snapshot)
		for i in range(5):
			await process_frame
			RenderingServer.force_draw(false)
		output_view.get_texture().get_image().save_png("res://docs/qa/native_pink_ascent_%s_%s.png" % [name,"original" if size==1 else "enhanced"])
	require(core.get_state()==before,"Ascent drawing leaves native state intact")
	captures[name]={"frame":state.frame,"room":state.room,"room_state":state.room_state,"health":state.health,
		"x":state.position.x,"y":state.position.y,"pose":state.pose,"movement_type":state.movement_type,
		"camera":[state.camera.x,state.camera.y],"presentation_leaves_core_unchanged":true}
	print("PINK_ASCENT_CAPTURE ",name," frame=",state.frame)

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var index := args.find("--route-fixture")
	require(index>=0 and index+1<args.size(),"Missing ascent route fixture")
	var directory: String=args[index+1]
	var inputs := FileAccess.get_file_as_bytes(directory.path_join("ascent.inputs"))
	var lines := FileAccess.get_file_as_string(directory.path_join("ascent.csv")).strip_edges().split("\n")
	var seed := FileAccess.get_file_as_bytes(directory.path_join("seed.srm"))
	require(seed.size()==8192 and inputs.size()>PREFIX_FRAME*2 and lines.size()==inputs.size()/2+1,"Complete original ascent input/state fixture")
	var seed_hash := FileAccess.get_sha256(directory.path_join("seed.srm"))
	var before := FileAccess.get_sha256(ROM)
	var save := FileAccess.open(ASCENT_SAVE,FileAccess.WRITE)
	save.store_buffer(seed)
	save.close()
	extension_resource=load("res://native/sm_native.gdextension")
	core=ClassDB.instantiate("SmNativeCore")
	require(core.boot(ROM,ASCENT_SAVE),"Boot original ascent SRAM: "+core.get_error())
	output_view=SubViewport.new()
	output_view.size=Vector2i(256,224)
	output_view.disable_3d=true
	output_view.world_2d=World2D.new()
	output_view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(output_view)
	renderer=Renderer.new()
	output_view.add_child(renderer)
	var loaded: Dictionary={}
	var approach: Dictionary={}
	var state: Dictionary
	var audible := 0
	var previous_joy := 0
	var previous_movement := 0
	var wall_jump_frames := 0
	var wall_jumps: Array=[]
	var standing_x := 0.0
	var moved := false
	for tick in range(inputs.size()/2):
		var joy := inputs.decode_u16(tick*2)
		require(core.step(joy),"Ascent native tick: "+core.get_error())
		state=core.get_state()
		var f := lines[tick+1].split(",")
		require(f.size()==29,"Ascent trace columns")
		var values := [state.frame,state.state,state.room,state.position.x,state.position.y,state.pose,state.health,state.items,state.missiles,state.missile_capacity,state.selected_item,state.active_projectiles,state.room_kills,state.room_quota,state.event_flags.decode_u16(0),state.movement_type,state.room_state,state.boss_flags[0],state.active_bombs,state.max_health,state.save_station,state.save_slot,state.save_writes,state.area,state.supers,state.beams,state.beam_charge,state.charged_projectiles,state.time_frozen]
		for field in range(values.size()):
			var expected: int=f[field].hex_to_int() if field==2 else int(f[field])
			require(values[field]==expected,"Ascent C/Godot state parity at %d column %d" % [tick+1,field])
		if state.state==8 and loaded.is_empty():
			loaded=state.duplicate(true)
			require(state.room==0x93d5 and state.items==0x1004 and state.beams==0 and state.save_station==1,"Original Crateria station inventory loaded")
		if state.frame==PREFIX_FRAME:
			approach=state.duplicate(true)
			require(state.state==8 and state.room==0x9d19 and state.position==Vector2(620,1920) and state.health==24 and state.beams==0x1000 and state.missiles==5 and state.missile_capacity==10,"Certified Charge Beam control checkpoint")
			await capture("alcove_control",state)
		if state.frame>PREFIX_FRAME:
			require(state.state==8 and state.room==0x9d19 and state.health==approach.health and state.items==approach.items and state.beams==approach.beams and state.missiles==approach.missiles and state.missile_capacity==approach.missile_capacity and state.time_frozen==0,"Original room/health/inventory retained throughout ascent")
			require(state.event_flags==approach.event_flags and state.boss_flags==approach.boss_flags and state.save_writes==approach.save_writes,"Ascent preserves original events/bosses/save writes")
			if state.frame==10162:await capture("normal_jump",state)
			if state.movement_type==20:
				wall_jump_frames+=1
				if previous_movement!=20:
					require((joy&0x80)!=0 and (previous_joy&0x80)==0,"Native wall jump begins with a new jump press")
					wall_jumps.append({"frame":state.frame,"x":state.position.x,"y":state.position.y,"pose":state.pose})
					if wall_jumps.size()==1:await capture("wall_first",state)
					if wall_jumps.size()==3:await capture("wall_third",state)
			if wall_jumps.size()==3 and state.position.y<1700 and state.movement_type in [0,1,5,21] and not captures.has("top_platform"):await capture("top_platform",state)
			if captures.has("top_platform") and state.movement_type in [4,8] and state.position.x<694 and state.position.y<1720 and not captures.has("tunnel_morph"):await capture("tunnel_morph",state)
			if captures.has("tunnel_morph") and state.position.x<678 and state.position.y<1720 and state.movement_type in [0,1,5,21]:
				if not captures.has("exit_standing"):
					standing_x=state.position.x
					await capture("exit_standing",state)
				if absf(state.position.x-standing_x)>16:moved=true
		previous_joy=joy
		previous_movement=state.movement_type
		if tick%180==0:
			for sample in core.get_audio():
				if sample!=Vector2.ZERO:
					audible+=1
					break
			await process_frame
	require(state.state==8 and state.room==0x9d19 and state.position==Vector2(640,1675) and state.movement_type==0 and state.pose==1 and state.active_bombs==0 and moved,"Stable original control after returning from the alcove")
	require(wall_jumps.size()==3 and wall_jump_frames==6 and audible>10 and captures.size()==7,"Three native wall jumps, Morph passage, standing movement and audio")
	require(state.event_flags==loaded.event_flags and state.boss_flags==loaded.boss_flags,"Certified saved events retained")
	await capture("control",state)
	require(FileAccess.get_sha256(ROM)==before and FileAccess.get_sha256(directory.path_join("seed.srm"))==seed_hash,"Ascent source ROM/SRAM unchanged")
	var report := {"frames":inputs.size()/2,"columns_compared_per_tick":29,"state_trace_matches":true,"captures":captures,
		"wall_jumps":wall_jumps,"wall_jump_frames":wall_jump_frames,"prefix_frame":PREFIX_FRAME,
		"original_station_sram_loaded":true,"seed_sha256":seed_hash,"source_seed_unchanged":true,"rom_unchanged":true,
		"saved_events_retained":true,"health_and_equipment_retained_during_ascent":true,"standing_movement_after_exit":moved,
		"room":state.room,"health":state.health,"max_health":state.max_health,"items":state.items,"beams":state.beams,
		"missiles":state.missiles,"capacity":state.missile_capacity,"audible_packets":audible,
		"whole_campaign_verified":false,"spore_spawn_verified":false}
	var output := FileAccess.open("res://docs/qa/native_pink_ascent_route.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"  ")+"\n")
	output.close()
	core.close()
	core=null
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ASCENT_SAVE))
	print("PINK_ASCENT_GODOT_OK: ",inputs.size()/2," ticks, 29 fields identical; three wall jumps, Morph passage and stable standing control; health, ammo and original events retained")
	quit()
