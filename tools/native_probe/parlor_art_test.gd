extends "res://tools/native_probe/campaign_test.gd"

const OUTPUT := "res://docs/qa/native_parlor_art_"
const ART_SAVE := "user://native_parlor_art_test.srm"
const ART_TILES := [200,201,202,203,204,205,206,207,216,217,218,219,220,221,222,223,
	232,233,234,235,236,237,238,239,248,249,250,251,252,253,254,255,
	490,491,492,493,494,495,506,507,508,509,510,511]
var packet_directory := ""
var output_view: SubViewport

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var index := args.find("--route-fixture")
	require(index>=0 and index+1<args.size(),"Missing Parlor art fixture")
	var directory: String=args[index+1]
	packet_directory=directory.path_join("art_packets")
	DirAccess.make_dir_recursive_absolute(packet_directory)
	var jobs: Array=JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("runs.json")))
	var before := FileAccess.get_sha256(ROM)
	extension_resource=load("res://native/sm_native.gdextension")
	root.content_scale_size=Vector2i.ZERO
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
	output_view=SubViewport.new()
	output_view.size=Vector2i(256,224)
	output_view.disable_3d=true
	output_view.world_2d=World2D.new()
	output_view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(output_view)
	renderer=Renderer.new()
	output_view.add_child(renderer)
	var frames := 0
	var trace_frames := 0
	for job: Dictionary in jobs:
		if FileAccess.file_exists(ART_SAVE):DirAccess.remove_absolute(ProjectSettings.globalize_path(ART_SAVE))
		if job.has("seed"):
			var save := FileAccess.open(ART_SAVE,FileAccess.WRITE)
			save.store_buffer(FileAccess.get_file_as_bytes(directory.path_join(job.seed)))
			save.close()
		core=ClassDB.instantiate("SmNativeCore")
		require(core.boot(ROM,ART_SAVE),"Boot original Parlor route: "+core.get_error())
		var inputs := FileAccess.get_file_as_bytes(directory.path_join(job.inputs))
		var lines := PackedStringArray()
		if job.has("trace"):lines=FileAccess.get_file_as_string(directory.path_join(job.trace)).strip_edges().split("\n")
		var checkpoints: Dictionary={}
		for case: Dictionary in job.cases:checkpoints[int(case.frame)]=case
		for tick in range(inputs.size()/2):
			require(core.step(inputs.decode_u16(tick*2)),"Parlor art native tick")
			var state: Dictionary=core.get_state()
			frames+=1
			if not lines.is_empty():
				var fields := lines[tick+1].split(",")
				require(fields.size()==25,"Parlor continuation trace columns")
				require(state.frame==int(fields[0]) and state.state==int(fields[1]) and state.room==fields[2].hex_to_int(),"Parlor continuation state/frame/room parity")
				require(state.position==Vector2(int(fields[3]),int(fields[4])) and state.pose==int(fields[5]) and state.health==int(fields[6]),"Parlor continuation Samus parity")
				var values := [state.items,state.missiles,state.missile_capacity,state.selected_item,state.active_projectiles,state.room_kills,state.room_quota,state.event_flags.decode_u16(0),state.movement_type,state.room_state,state.boss_flags[0],state.active_bombs,state.max_health,state.save_station,state.save_slot,state.save_writes,state.area,state.supers]
				for i in range(values.size()):require(values[i]==int(fields[i+7]),"Parlor continuation inventory/event parity")
				trace_frames+=1
			if checkpoints.has(state.frame):
				var case: Dictionary=checkpoints[state.frame]
				require(state.state==8 and state.room==0x92fd and state.room_state in [0x9314,0x932e],"Actual Parlor state checkpoint")
				require(state.position==Vector2(case.x,case.y) and state.camera==Vector2(case.camera_x,case.camera_y),"Parlor checkpoint camera and position parity")
				for field in ["state","room","room_state","pose","health","items","beams","missiles"]:require(state[field]==int(case[field]),"Parlor original checkpoint field: "+field)
				await capture(case.name,state)
			if tick%180==0:
				var progress := FileAccess.open(directory.path_join("progress.json"),FileAccess.WRITE)
				progress.store_string(JSON.stringify({"job":job.name,"frame":tick+1}))
				progress.close()
				await process_frame
		core.close()
		core=null
		DirAccess.remove_absolute(ProjectSettings.globalize_path(ART_SAVE))
	require(captures.size()==7 and trace_frames==5316,"Both Parlor states and continuation trace")
	require(FileAccess.get_sha256(ROM)==before,"Parlor source ROM unchanged")
	var report := {"frames":frames,"trace_frames":trace_frames,"trace_columns":25,"captures":captures,
		"asset_sha256":FileAccess.get_sha256("res://assets/remastered/parlor_bg2_tiles.png"),
		"scope":"44 native Crateria Rocks BG2 cells in Parlor 92FD, actual dormant 9314 and awake 932E states, three/four original camera checkpoints",
		"rom_unchanged":true,"whole_campaign_verified":false,"full_asset_redraw_complete":false}
	var file := FileAccess.open(OUTPUT+"route.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  ")+"\n")
	file.close()
	print("PARLOR_ART_GODOT_OK: ",frames," native ticks; both original Parlor states, seven live camera checkpoints and 25-field continuation parity")
	quit()

func save_packet(name: String, snapshot: Dictionary) -> void:
	require(not packet_directory.is_empty(),"Private art fixture directory")
	for field in ["vram","raster"]:
		var file := FileAccess.open(packet_directory.path_join(name+"."+field),FileAccess.WRITE)
		file.store_buffer(snapshot[field])
		file.close()

func save_image(name: String, snapshot: Dictionary) -> void:
	renderer.present(snapshot)
	# Render the owned offscreen viewport even if another test covers its window.
	for i in range(5):
		await process_frame
		RenderingServer.force_draw(false)
	output_view.get_texture().get_image().save_png(OUTPUT+name+".png")

func size_original() -> void:
	output_view.size=Vector2i(256,224)
	renderer.scale=Vector2.ONE
	renderer.enhanced=false

func size_enhanced() -> void:
	output_view.size=Vector2i(512,448)
	renderer.scale=Vector2(2,2)
	renderer.enhanced=true

func capture(name: String, state: Dictionary) -> void:
	var before: Dictionary=core.get_state()
	var snapshot: Dictionary=core.get_snapshot()
	save_packet(name,snapshot)
	size_original()
	await save_image(name+"_original",snapshot)
	renderer.main_view.get_texture().get_image().save_png(OUTPUT+name+"_layers.png")
	renderer.sub_view.get_texture().get_image().save_png(OUTPUT+name+"_sub_layers.png")
	size_enhanced()
	renderer.remastered_backgrounds=false
	await save_image(name+"_filtered",snapshot)
	renderer.remastered_backgrounds=true
	await save_image(name+"_remastered",snapshot)
	if name=="awake_upper":await display_checks(snapshot)
	size_original()
	await save_image(name+"_restored",snapshot)
	require(core.get_state()==before,"Parlor artwork presentation leaves native state unchanged")
	captures[name]={"frame":state.frame,"room":state.room,"room_state":state.room_state,
		"health":state.health,"camera":[state.camera.x,state.camera.y],
		"bg2_scroll":[snapshot.raster.decode_u16(100*1024+44),snapshot.raster.decode_u16(100*1024+46)],
		"presentation_leaves_core_unchanged":true}
	print("PARLOR_ART_CAPTURE ",name," frame=",state.frame)

func changed_case(name: String, snapshot: Dictionary, layers: bool=false) -> void:
	save_packet(name,snapshot)
	renderer.remastered_backgrounds=false
	await save_image(name+"_filtered",snapshot)
	if layers:
		renderer.main_view.get_texture().get_image().save_png(OUTPUT+name+"_layers.png")
		renderer.sub_view.get_texture().get_image().save_png(OUTPUT+name+"_sub_layers.png")
	renderer.remastered_backgrounds=true
	await save_image(name,snapshot)

func display_checks(snapshot: Dictionary) -> void:
	var changed: Dictionary=snapshot.duplicate()
	changed.camera=snapshot.camera+Vector2(1024,512)
	await save_image("camera_only",changed)
	for periodic in [true,false]:
		changed=snapshot.duplicate()
		var raster: PackedByteArray=snapshot.raster.duplicate()
		for row in range(224):
			for offset in [44,46]:
				var delta := (512 if offset==44 else 256) if periodic else (16 if offset==44 else 8)
				var address: int=row*1024+offset
				raster.encode_u16(address,(raster.decode_u16(address)+delta)&0xffff)
		changed.raster=raster
		if periodic:await save_image("scroll_period",changed)
		else:await changed_case("scroll_shift",changed,true)
	for excluded in ["map","room","state","endgame"]:
		changed=snapshot.duplicate()
		if excluded=="map":changed.state=12
		if excluded=="room":changed.room=0x9d19
		if excluded=="state":changed.room_state=0
		if excluded=="endgame":changed.room_state=0x9348
		await save_image(excluded+"_excluded",changed)
	for mode in ["fade_zero","forced_blank","palette_flash"]:
		changed=snapshot.duplicate()
		var raster: PackedByteArray=snapshot.raster.duplicate()
		for row in range(224):
			if mode=="palette_flash":
				for color in range(65,80):
					var address: int=row*1024+256+color*2
					raster.encode_u16(address,(raster.decode_u16(address)&0x7fe0)|20)
			else:raster[row*1024+(2 if mode=="fade_zero" else 3)]=0 if mode=="fade_zero" else 1
		changed.raster=raster
		if mode=="palette_flash":await changed_case(mode,changed)
		else:await save_image(mode,changed)
	# Change only the presentation packet. Native tile ID / X and Y flips
	# must affect the replacement at the same coordinates as the tile renderer.
	for kind in ["tile_flip","tile_remap"]:
		changed=snapshot.duplicate()
		var vram: PackedByteArray=snapshot.vram.duplicate()
		var base: int=snapshot.raster.decode_u16(100*1024+40)*2
		var modified := 0
		for tile in range(2048):
			var address := (base+tile*2)&65535
			var word := vram.decode_u16(address)
			if ((word>>10)&7)==4 and (((word&1023)>=200 and (word&1023)<=255 and (word&15)>=8) or ((word&1023)>=490 and (word&1023)<=511 and (word&15)>=10)):
				vram.encode_u16(address,word^0xc000 if kind=="tile_flip" else (word&0x3c00)|ART_TILES[tile%ART_TILES.size()]|((tile%4)<<14))
				modified+=1
		require(modified>0,"Parlor ID/flip fixture changes actual palette-4 map entries")
		changed.vram=vram
		await changed_case(kind,changed,true)
