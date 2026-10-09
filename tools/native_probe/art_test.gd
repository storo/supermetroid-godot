extends "res://tools/native_probe/campaign_test.gd"

const ART_SAVE := "user://native_art_route_test.srm"
const OUTPUT := "res://docs/qa/native_art_"

func image_capture(name: String, snapshot: Dictionary) -> void:
	renderer.present(snapshot)
	for i in range(5):await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT+name+".png")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var index := args.find("--route-fixture")
	require(index>=0 and index+1<args.size(),"Missing --route-fixture")
	var directory: String = args[index+1]
	var inputs := FileAccess.get_file_as_bytes(directory.path_join("route.inputs"))
	var lines := FileAccess.get_file_as_string(directory.path_join("route.csv")).strip_edges().split("\n")
	require(inputs.size()>16000 and inputs.size()%2==0 and lines.size()==inputs.size()/2+1,"Complete campaign trace")
	extension_resource = load("res://native/sm_native.gdextension")
	require(extension_resource!=null and ClassDB.class_exists("SmNativeCore"),"Extension registration")
	core = ClassDB.instantiate("SmNativeCore")
	if FileAccess.file_exists(ART_SAVE):DirAccess.remove_absolute(ProjectSettings.globalize_path(ART_SAVE))
	var before := FileAccess.get_sha256(ROM)
	require(core.boot(ROM,ART_SAVE),"Boot: "+core.get_error())
	for tick in range(inputs.size()/2):
		require(core.step(inputs.decode_u16(tick*2)),"Core step: "+core.get_error())
		var state: Dictionary = core.get_state()
		var columns := lines[tick+1].split(",")
		require(state.frame==int(columns[0]) and state.state==int(columns[1]) and state.room==columns[2].hex_to_int(),"State parity at %d" % tick)
		require(state.position==Vector2(int(columns[3]),int(columns[4])) and state.pose==int(columns[5]) and state.health==int(columns[6]),"Samus parity at %d" % tick)
		if tick%180==0:await process_frame
	var state_before: Dictionary = core.get_state()
	require(state_before.state==8 and state_before.room==0x91f8,"Playable Landing Site")
	var snapshot: Dictionary = core.get_snapshot()
	root.content_scale_size = Vector2i.ZERO
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	renderer = Renderer.new()
	root.add_child(renderer)
	root.size = Vector2i(256,224)
	renderer.enhanced = false
	await image_capture("original",snapshot)
	renderer.main_view.get_texture().get_image().save_png(OUTPUT+"layers.png")
	root.size = Vector2i(512,448)
	renderer.scale = Vector2(2,2)
	renderer.enhanced = true
	renderer.remastered_backgrounds = false
	await image_capture("filtered",snapshot)
	renderer.remastered_backgrounds = true
	await image_capture("remastered",snapshot)
	var display_only := snapshot.duplicate()
	display_only.camera = snapshot.camera+Vector2(256,0)
	await image_capture("parallax",display_only)
	display_only = snapshot.duplicate()
	display_only.state = 12 # Map/pause must not acquire outdoor art.
	await image_capture("map_excluded",display_only)
	display_only = snapshot.duplicate()
	display_only.room = 0x9f11 # Underground room: same packets, different art selector.
	await image_capture("room_excluded",display_only)
	# Display-only register fixtures check that new scenery follows native fades
	# and forced blanking. They do not write registers in the gameplay core.
	for mode in ["fade_zero","forced_blank"]:
		display_only = snapshot.duplicate()
		var raster: PackedByteArray = snapshot.raster.duplicate()
		for row in range(224):
			raster[row*1024+(2 if mode=="fade_zero" else 3)] = 0 if mode=="fade_zero" else 1
		display_only.raster = raster
		await image_capture(mode,display_only)
	renderer.enhanced = false
	root.size = Vector2i(256,224)
	renderer.scale = Vector2.ONE
	await image_capture("original_restored",snapshot)
	require(core.get_state()==state_before,"Art presentation does not advance or modify the core")
	require(before==FileAccess.get_sha256(ROM),"ROM unchanged")
	var report := {"frames":inputs.size()/2,"room":state_before.room,"camera":[snapshot.camera.x,snapshot.camera.y],
		"state_trace_matches":true,"presentation_leaves_core_unchanged":true,"rom_unchanged":true,
		"backdrop_sha256":FileAccess.get_sha256("res://assets/remastered/crateria_backdrop.png"),
		"scope":"Landing Site BG2 only; native terrain/sprites/HUD and gameplay preserved; original toggle and display-only parallax/selection checks",
		"whole_campaign_verified":false,"full_asset_redraw_complete":false}
	var file := FileAccess.open(OUTPUT+"route.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  ")+"\n")
	file.close()
	core.close()
	core = null
	if FileAccess.file_exists(ART_SAVE):DirAccess.remove_absolute(ProjectSettings.globalize_path(ART_SAVE))
	print("ART_GODOT_OK: native Ceres/escape/Landing route; original/filter/new backdrop/parallax/room+map exclusion; unchanged core and ROM")
	quit()
