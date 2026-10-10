extends "res://tools/native_probe/pink_test.gd"

const Renderer = preload("res://scripts/native_raster_renderer.gd")
const OUTPUT := "res://docs/qa/native_pink_art_"
const CHECKPOINTS := {7941:"arrival",8021:"wall_left",8101:"wall_right",8191:"wall_lower",8241:"control"}
var captures: Dictionary={}
var renderer: NativeRasterRenderer
var packet_directory := ""
var dachora_age := 0

func require(condition: bool, detail: String) -> void:
	if not check(condition,detail):assert(false,detail)

func prepare_display() -> void:
	report_prefix="native_pink_art"
	var args := OS.get_cmdline_user_args()
	packet_directory=args[args.find("--route-fixture")+1].path_join("art_packets")
	DirAccess.make_dir_recursive_absolute(packet_directory)
	root.content_scale_size=Vector2i.ZERO
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
	renderer=Renderer.new()
	root.add_child(renderer)

func replay_tick(state: Dictionary) -> void:
	if state.state==8 and state.room==0x9cb3:
		dachora_age+=1
		if dachora_age==40:await capture("dachora",state)
	if CHECKPOINTS.has(state.frame):
		require(state.state==8 and state.room==0x9d19,"Actual Big Pink gameplay checkpoint")
		await capture(CHECKPOINTS[state.frame],state)
	if state.frame%180==0:await process_frame

func finish_report(report: Dictionary) -> Dictionary:
	require(captures.size()==6,"All Big Pink art checkpoints present")
	report.captures=captures
	report.asset_sha256=FileAccess.get_sha256("res://assets/remastered/pink_bg2_tiles.png")
	report.full_asset_redraw_complete=false
	report.art_scope="Sixteen Big Pink BG2 tiles in 9D19/9D26, native IDs/flips/scroll/CGRAM; geometry, sprites and core state preserved"
	return report

func save_packet(name: String, snapshot: Dictionary) -> void:
	require(not packet_directory.is_empty(),"Private art fixture directory")
	for field in ["vram","raster"]:
		var file := FileAccess.open(packet_directory.path_join(name+"."+field),FileAccess.WRITE)
		file.store_buffer(snapshot[field])
		file.close()

func save_image(name: String, snapshot: Dictionary) -> void:
	renderer.present(snapshot)
	for i in range(5):await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT+name+".png")

func size_original() -> void:
	root.size=Vector2i(256,224)
	renderer.scale=Vector2.ONE
	renderer.enhanced=false

func size_enhanced() -> void:
	root.size=Vector2i(512,448)
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
	if name=="control":await display_checks(snapshot)
	size_original()
	await save_image(name+"_restored",snapshot)
	require(core.get_state()==before,"Big Pink artwork presentation leaves native state unchanged")
	captures[name]={"frame":state.frame,"room":state.room,"room_state":state.room_state,
		"health":state.health,"camera":[state.camera.x,state.camera.y],
		"bg2_scroll":[snapshot.raster.decode_u16(100*1024+44),snapshot.raster.decode_u16(100*1024+46)],
		"presentation_leaves_core_unchanged":true}
	print("PINK_ART_CAPTURE ",name," frame=",state.frame)

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
	for excluded in ["map","room","state"]:
		changed=snapshot.duplicate()
		if excluded=="map":changed.state=12
		if excluded=="room":changed.room=0x9b9d
		if excluded=="state":changed.room_state=0
		await save_image(excluded+"_excluded",changed)
	for mode in ["fade_zero","forced_blank","palette_flash"]:
		changed=snapshot.duplicate()
		var raster: PackedByteArray=snapshot.raster.duplicate()
		for row in range(224):
			if mode=="palette_flash":
				for color in range(49,64):
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
			if ((word>>10)&7)==3 and (word&1023)>=492 and (word&1023)<=543 and (word&15)>=12:
				vram.encode_u16(address,word^0xc000 if kind=="tile_flip" else (word&0xfc00)|508)
				modified+=1
		require(modified>0,"Big Pink ID/flip fixture changes actual palette-3 map entries")
		changed.vram=vram
		await changed_case(kind,changed,true)
