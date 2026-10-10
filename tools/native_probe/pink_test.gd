extends SceneTree

const ROM := "res://rom_src/Super Metroid (Japan, USA) (En,Ja).sfc"
const SAVE := "user://native_pink_publish_test.srm"
var core: Object
var report_prefix := "native_pink"

func prepare_display() -> void:
	pass

func replay_tick(_state: Dictionary) -> void:
	pass

func finish_report(report: Dictionary) -> Dictionary:
	return report

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> bool:
	if condition:return true
	push_error(message)
	if core:core.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	quit(1)
	return false

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var index := args.find("--route-fixture")
	if not check(index>=0 and index+1<args.size(),"Missing route fixture"):return
	var directory: String=args[index+1]
	var inputs := FileAccess.get_file_as_bytes(directory.path_join("pink.inputs"))
	var lines := FileAccess.get_file_as_string(directory.path_join("pink.csv")).strip_edges().split("\n")
	var seed := FileAccess.get_file_as_bytes(directory.path_join("seed.srm"))
	if not check(seed.size()==8192 and inputs.size()>4000 and lines.size()==inputs.size()/2+1,"Incomplete fixture"):return
	var before := FileAccess.get_sha256(ROM)
	var seed_hash := FileAccess.get_sha256(directory.path_join("seed.srm"))
	var save := FileAccess.open(SAVE,FileAccess.WRITE)
	save.store_buffer(seed)
	save.close()
	var extension := load("res://native/sm_native.gdextension")
	if not check(extension!=null,"Native extension unavailable"):return
	core=ClassDB.instantiate("SmNativeCore")
	if not check(core.boot(ROM,SAVE),"Boot failed: "+core.get_error()):return
	prepare_display()
	var rooms: Dictionary={}
	var pirates := false
	var state: Dictionary
	for tick in range(inputs.size()/2):
		if not check(core.step(inputs.decode_u16(tick*2)),"Native tick failed"):return
		state=core.get_state()
		var f := lines[tick+1].split(",")
		if not check(f.size()==25,"Invalid trace row"):return
		var values := [state.frame,state.state,state.room,state.position.x,state.position.y,state.pose,state.health,state.items,state.missiles,state.missile_capacity,state.selected_item,state.active_projectiles,state.room_kills,state.room_quota,state.event_flags.decode_u16(0),state.movement_type,state.room_state,state.boss_flags[0],state.active_bombs,state.max_health,state.save_station,state.save_slot,state.save_writes,state.area,state.supers]
		for field in range(values.size()):
			var expected: int=f[field].hex_to_int() if field==2 else int(f[field])
			if not check(values[field]==expected,"State mismatch at tick %d column %d" % [tick+1,field]):return
		if state.state==8:
			rooms[state.room]=true
			if state.room==0x99bd and state.room_kills>=5 and state.missiles==5:pirates=true
		await replay_tick(state)
	if not check(state.state==8 and state.room==0x9d19 and state.area==1 and state.health>0 and state.items==0x1004 and pirates and rooms.has(0x9ad9) and rooms.has(0x9cb3),"Incomplete Big Pink approach"):return
	if not check(FileAccess.get_sha256(ROM)==before and FileAccess.get_sha256(directory.path_join("seed.srm"))==seed_hash,"Source changed"):return
	var report := {"frames":inputs.size()/2,"columns_compared_per_tick":25,"state_trace_matches":true,"rooms":rooms.keys(),"final_room":state.room,"health":state.health,"green_pirates_defeated_with_ammo_recovered":pirates,"rom_unchanged":true,"source_sram_unchanged":true,"seed_sha256":seed_hash,"whole_campaign_verified":false,"spore_spawn_verified":false,"raster_comparison_performed":false}
	report=finish_report(report)
	var output := FileAccess.open("res://docs/qa/%s_route.json" % report_prefix,FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"  ")+"\n")
	output.close()
	core.close()
	core=null
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	print("PINK_GODOT_OK: ",inputs.size()/2," ticks, 25 fields identical; Big Pink reached; Spore Spawn pending")
	quit()
