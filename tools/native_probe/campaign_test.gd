extends SceneTree

const Renderer = preload("res://scripts/native_raster_renderer.gd")
const ROM := "res://rom_src/Super Metroid (Japan, USA) (En,Ja).sfc"
const SAVE := "user://native_campaign_route_test.srm"
var core: RefCounted
var extension_resource: Resource
var renderer: Node2D
var captures: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func require(condition: bool, detail: String) -> void:
	if not condition:
		push_error("CAMPAIGN_GODOT_FAILED: " + detail)
		if core: core.close()
		quit(1)
		assert(false,detail)

func capture(name: String, state: Dictionary) -> void:
	var snapshot: Dictionary = core.get_snapshot()
	var modes: Dictionary = {}
	for row in range(224):modes[snapshot.raster[row*1024]]=true
	captures[name] = {"frame":state.frame,"room":state.room,"health":state.health,"timer_status":state.timer_status,"mode":snapshot.mode,"scanline_modes":modes.keys(),"mode7_flags":snapshot.mode7_flags,"mode7_matrix":snapshot.mode7}
	if renderer == null: return
	root.size = Vector2i(256,224)
	renderer.scale = Vector2.ONE
	renderer.enhanced = false
	renderer.present(snapshot)
	for i in range(5): await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/qa/native_campaign_%s_original.png" % name)
	root.size = Vector2i(512,448)
	renderer.scale = Vector2(2,2)
	renderer.enhanced = true
	renderer.present(snapshot)
	for i in range(5): await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/qa/native_campaign_%s_enhanced.png" % name)
	print("CAMPAIGN_CAPTURE %s frame=%d" % [name,state.frame])

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var index := args.find("--route-fixture")
	require(index>=0 and index+1<args.size(),"Missing --route-fixture directory")
	var directory: String = args[index+1]
	var inputs := FileAccess.get_file_as_bytes(directory.path_join("route.inputs"))
	var lines := FileAccess.get_file_as_string(directory.path_join("route.csv")).strip_edges().split("\n")
	require(inputs.size()>16000 and inputs.size()%2==0 and lines.size()==inputs.size()/2+1,"Complete input/state trace")
	extension_resource = load("res://native/sm_native.gdextension")
	require(extension_resource!=null and ClassDB.class_exists("SmNativeCore"),"Extension registration")
	core = ClassDB.instantiate("SmNativeCore")
	if FileAccess.file_exists(SAVE):DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	var before := FileAccess.get_sha256(ROM)
	require(core.boot(ROM,SAVE),"Boot: "+core.get_error())
	if DisplayServer.get_name()!="headless":
		root.content_scale_size = Vector2i.ZERO
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
		renderer = Renderer.new()
		root.add_child(renderer)
	var rooms: Dictionary = {}
	var audible := 0
	var getaway_started := -1
	var state: Dictionary
	for tick in range(inputs.size()/2):
		require(core.step(inputs.decode_u16(tick*2)),"Tick %d: %s" % [tick,core.get_error()])
		state = core.get_state()
		var columns := lines[tick+1].split(",")
		require(state.frame==int(columns[0]) and state.state==int(columns[1]) and state.room==columns[2].hex_to_int(),"Frame/state/room parity at %d" % tick)
		require(state.position==Vector2(int(columns[3]),int(columns[4])) and state.pose==int(columns[5]) and state.health==int(columns[6]),"Samus parity at %d" % tick)
		require(state.ceres_status==int(columns[7]) and state.timer_status==int(columns[8]),"Event/timer parity at %d" % tick)
		if state.state==8:rooms[state.room]=true
		if state.room==0xe0b5 and state.state==8:
			if state.health<99 and state.ceres_status==0 and not captures.has("ridley"):
				await capture("ridley",state)
			if state.ceres_status==1:
				if getaway_started<0:getaway_started=tick
				if tick-getaway_started>=80 and not captures.has("getaway"):
					await capture("getaway",state)
		if state.room==0xe06b and state.state==8 and state.timer_status!=0 and not captures.has("escape"):
			await capture("escape",state)
		if tick%180==0:
			for sample in core.get_audio():
				if sample!=Vector2.ZERO:
					audible+=1
					break
			await process_frame
	for room in [0xdf45,0xdf8d,0xdfd7,0xe021,0xe06b,0xe0b5,0x91f8]:require(rooms.has(room),"Visited room %04x" % room)
	require(state.state==8 and state.room==0x91f8 and state.area==0 and state.position.x<1130 and state.position.y>=800,"Playable Landing Site after escape")
	require(captures.has("ridley") and captures.has("getaway") and captures.has("escape") and audible>10,"Boss/getaway/timer/audio evidence")
	await capture("landing",state)
	var report := {"frames":inputs.size()/2,"state_trace_matches":true,"rooms":rooms.keys(),"captures":captures,"audible_packets":audible,"rom_unchanged":FileAccess.get_sha256(ROM)==before,"whole_campaign_verified":false}
	require(report.rom_unchanged,"ROM unchanged")
	var file := FileAccess.open("res://docs/qa/native_campaign_route.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  ")+"\n")
	file.close()
	core.close()
	core=null
	if FileAccess.file_exists(SAVE):DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	print("CAMPAIGN_GODOT_OK: %d native ticks, all Ceres rooms, Ridley/getaway/timer, escape, playable Landing Site, exact input/state replay, intact ROM" % (inputs.size()/2))
	quit()
