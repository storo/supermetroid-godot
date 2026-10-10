extends "res://tools/native_probe/campaign_test.gd"

const WALL_SAVE := "user://native_ceres_wall_test.srm"
const OUTPUT := "res://docs/qa/native_ceres_art_"
const ROOMS := {0xdf8d:"corridor",0xdfd7:"stairs",0xe06b:"hall"}
var wall_captures: Dictionary={}

func save_image(name: String, snapshot: Dictionary) -> void:
	renderer.present(snapshot)
	for i in range(5):await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT+name+".png")

func original_size() -> void:
	root.size=Vector2i(256,224)
	renderer.scale=Vector2.ONE
	renderer.enhanced=false

func enhanced_size() -> void:
	root.size=Vector2i(512,448)
	renderer.scale=Vector2(2,2)
	renderer.enhanced=true

func wall_case(name: String, state: Dictionary) -> void:
	var before: Dictionary=core.get_state()
	var snapshot: Dictionary=core.get_snapshot()
	original_size()
	await save_image(name+"_original",snapshot)
	renderer.main_view.get_texture().get_image().save_png(OUTPUT+name+"_layers.png")
	enhanced_size()
	renderer.remastered_backgrounds=false
	await save_image(name+"_filtered",snapshot)
	renderer.remastered_backgrounds=true
	await save_image(name+"_remastered",snapshot)
	if name=="pre_corridor":
		var changed: Dictionary=snapshot.duplicate()
		changed.camera=snapshot.camera+Vector2(512,128)
		await save_image("camera_only",changed)
		# A full native tilemap period must wrap identically; a partial scroll
		# must move the wall and retain all foreground/sprite/HUD layers.
		for periodic in [true,false]:
			changed=snapshot.duplicate()
			var moved_raster: PackedByteArray=snapshot.raster.duplicate()
			for row in range(224):
				for offset in [44,46]:
					var delta := (512 if offset==44 else 256) if periodic else (16 if offset==44 else 8)
					var address: int=row*1024+offset
					moved_raster.encode_u16(address,(moved_raster.decode_u16(address)+delta)&0xffff)
			changed.raster=moved_raster
			if periodic:await save_image("scroll_period",changed)
			else:
				renderer.remastered_backgrounds=false
				await save_image("scroll_filtered",changed)
				renderer.main_view.get_texture().get_image().save_png(OUTPUT+"scroll_layers.png")
				renderer.remastered_backgrounds=true
				await save_image("scroll_shift",changed)
		changed=snapshot.duplicate()
		changed.state=12
		await save_image("map_excluded",changed)
		changed=snapshot.duplicate()
		changed.room=0xe021
		changed.room_state=0xe033
		await save_image("library_excluded",changed)
		changed=snapshot.duplicate()
		changed.room_state=0
		await save_image("wrong_state_excluded",changed)
		for mode in ["fade_zero","forced_blank","palette_flash"]:
			changed=snapshot.duplicate()
			var raster: PackedByteArray=snapshot.raster.duplicate()
			for row in range(224):
				if mode=="palette_flash":
					for color in range(81,89):
						var offset: int=row*1024+256+color*2
						raster.encode_u16(offset,(raster.decode_u16(offset)&0x7fe0)|20)
				else:raster[row*1024+(2 if mode=="fade_zero" else 3)]=0 if mode=="fade_zero" else 1
			changed.raster=raster
			if mode=="palette_flash":
				renderer.remastered_backgrounds=false
				await save_image("palette_filtered",changed)
				renderer.remastered_backgrounds=true
			await save_image(mode,changed)
	original_size()
	await save_image(name+"_restored",snapshot)
	require(core.get_state()==before,"Wall presentation leaves native state intact")
	wall_captures[name]={"frame":state.frame,"room":state.room,"room_state":state.room_state,
		"ceres_status":state.ceres_status,"camera":[state.camera.x,state.camera.y],
		"bg2_scroll":[snapshot.raster.decode_u16(100*1024+44),snapshot.raster.decode_u16(100*1024+46)]}
	print("CERES_WALL_CAPTURE ",name," frame=",state.frame)

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var index := args.find("--route-fixture")
	require(index>=0 and index+1<args.size(),"Missing campaign fixture")
	if index<0 or index+1>=args.size():return
	var directory: String=args[index+1]
	var inputs := FileAccess.get_file_as_bytes(directory.path_join("route.inputs"))
	var lines := FileAccess.get_file_as_string(directory.path_join("route.csv")).strip_edges().split("\n")
	require(inputs.size()>16000 and lines.size()==inputs.size()/2+1,"Complete fresh campaign trace")
	extension_resource=load("res://native/sm_native.gdextension")
	core=ClassDB.instantiate("SmNativeCore")
	if FileAccess.file_exists(WALL_SAVE):DirAccess.remove_absolute(ProjectSettings.globalize_path(WALL_SAVE))
	var hash_before := FileAccess.get_sha256(ROM)
	require(core.boot(ROM,WALL_SAVE),"Boot: "+core.get_error())
	root.content_scale_size=Vector2i.ZERO
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
	renderer=Renderer.new()
	root.add_child(renderer)
	var ages: Dictionary={}
	var elevator_checked := false
	for tick in range(inputs.size()/2):
		require(core.step(inputs.decode_u16(tick*2)),"Ceres wall tick: "+core.get_error())
		var state: Dictionary=core.get_state()
		var fields := lines[tick+1].split(",")
		require(state.frame==int(fields[0]) and state.state==int(fields[1]) and state.room==fields[2].hex_to_int(),"Frame/state/room parity")
		require(state.position==Vector2(int(fields[3]),int(fields[4])) and state.pose==int(fields[5]) and state.health==int(fields[6]),"Samus parity")
		require(state.ceres_status==int(fields[7]) and state.timer_status==int(fields[8]),"Native escape/timer parity")
		if state.state==8 and ROOMS.has(state.room):
			var name: String=("escape_" if state.ceres_status>=2 else "pre_")+ROOMS[state.room]
			ages[name]=ages.get(name,0)+1
			if ages[name]>=24 and not wall_captures.has(name):await wall_case(name,state)
		if state.state==8 and state.room==0xdf45 and not elevator_checked:
			var snapshot: Dictionary=core.get_snapshot()
			enhanced_size()
			renderer.remastered_backgrounds=false
			await save_image("elevator_filtered",snapshot)
			renderer.remastered_backgrounds=true
			await save_image("elevator_excluded",snapshot)
			elevator_checked=true
		if tick%180==0:await process_frame
	var complete := wall_captures.size()==6 and elevator_checked
	require(complete,"Three Ceres wall rooms before and during escape")
	if not complete:return
	require(core.get_state().room==0x91f8 and core.get_state().state==8,"Fresh route reaches Landing Site")
	require(FileAccess.get_sha256(ROM)==hash_before,"ROM unchanged")
	var report := {"frames":inputs.size()/2,"captures":wall_captures,"state_trace_matches":true,
		"presentation_leaves_core_unchanged":true,"rom_unchanged":true,
		"asset_sha256":FileAccess.get_sha256("res://assets/remastered/ceres_bg2_wall.png"),
		"scope":"StatueHall BG2 library in three Ceres rooms and their two states; native scroll, CGRAM, fades, HUD/terrain/sprites preserved",
		"whole_campaign_verified":false,"full_asset_redraw_complete":false}
	var file := FileAccess.open(OUTPUT+"route.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  ")+"\n")
	file.close()
	core.close()
	core=null
	DirAccess.remove_absolute(ProjectSettings.globalize_path(WALL_SAVE))
	print("CERES_ART_GODOT_OK: ",inputs.size()/2," fresh ticks; three wall rooms/two states, unchanged native state, scroll/palette/fade/exclusion fixtures")
	quit()
