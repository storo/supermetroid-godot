extends "res://tools/native_probe/green_test.gd"

const OUTPUT := "res://docs/qa/native_green_art_"
var extra_captures: Dictionary={}
var packet_directory := ""

func _initialize() -> void:
	capture_prefix="native_green_art"
	var args := OS.get_cmdline_user_args()
	var index := args.find("--route-fixture")
	if index>=0 and index+1<args.size():
		packet_directory=args[index+1].path_join("art_packets")
		DirAccess.make_dir_recursive_absolute(packet_directory)
	call_deferred("run")

func replay_tick(state: Dictionary) -> void:
	if state.frame in [5180,5260]:
		require(state.state==8 and state.room==0x9ad9,"Actual green wall camera checkpoint")
		var name := "wall_upper" if state.frame==5180 else "wall_middle"
		await capture(name,state)
		extra_captures[name]=captures[name]
		captures.erase(name)

func supplement_report(report: Dictionary) -> Dictionary:
	report.additional_art_captures=extra_captures
	report.asset_sha256=FileAccess.get_sha256("res://assets/remastered/green_bg2_tiles.png")
	report.full_asset_redraw_complete=false
	report.art_scope="66 BG2 tiles in Green Brinstar Main Shaft 9AD9/9AE6, native tile map, flips, scroll/CGRAM/blank/fade; foreground and native state preserved"
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
	# Isolate this library's protection checks from other new BG2 families.
	renderer.remastered_backgrounds=state.room==0x9ad9
	await save_image(name+"_remastered",snapshot)
	if name=="control":await display_checks(snapshot)
	size_original()
	await save_image(name+"_restored",snapshot)
	require(core.get_state()==before,"Green artwork presentation leaves native state unchanged")
	captures[name]={"frame":state.frame,"room":state.room,"room_state":state.room_state,
		"health":state.health,"camera":[state.camera.x,state.camera.y],
		"bg2_scroll":[snapshot.raster.decode_u16(100*1024+44),snapshot.raster.decode_u16(100*1024+46)],
		"presentation_leaves_core_unchanged":true}
	print("GREEN_ART_CAPTURE ",name," frame=",state.frame)

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
				for color in range(113,128):
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
		for tile in range(2048):
			var address := (base+tile*2)&65535
			var word := vram.decode_u16(address)
			if ((word>>10)&7)==7 and (word&1023)>=224 and (word&1023)<352:
				vram.encode_u16(address,word^0xc000 if kind=="tile_flip" else (word&0xfc00)|320)
		changed.vram=vram
		await changed_case(kind,changed,true)
