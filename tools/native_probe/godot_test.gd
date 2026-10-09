extends SceneTree

const ROM := "res://rom_src/Super Metroid (Japan, USA) (En,Ja).sfc"
const SAVE := "user://native_extension_test.srm"
var core: RefCounted

func _initialize() -> void:
	call_deferred("run_test")

func require(condition: bool, detail: String) -> void:
	if not condition:
		push_error("NATIVE_EXTENSION_FAILED: " + detail)
		if core:
			core.close()
		quit(1)
		assert(false, detail)

func run_test() -> void:
	var extension = load("res://native/sm_native.gdextension")
	require(extension != null and ClassDB.class_exists("SmNativeCore"), "Extension registration")
	core = ClassDB.instantiate("SmNativeCore")
	var hash_before := FileAccess.get_sha256(ROM)
	if FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	require(core.boot(ROM, SAVE), "Boot: " + core.get_error())
	var second: RefCounted = ClassDB.instantiate("SmNativeCore")
	require(not second.boot(ROM, SAVE), "Single owner restriction")
	second = null
	var gameplay := 0
	var movement := 0
	var audible := 0
	var reached_ceres := false
	var saw_ceres_split := false
	var previous := Vector2.ZERO
	var snapshot: Dictionary = core.get_snapshot()
	for frame in range(18000):
		var joy := 0x1080 if frame % 60 < 2 else 0
		if snapshot.state == 8:
			gameplay += 1
			joy = 0x100 if gameplay % 240 < 120 else 0x200
			if gameplay % 90 < 20:
				joy |= 0x80
			if gameplay % 30 < 5:
				joy |= 0x40
		require(core.step(joy), "Tick %d: %s" % [frame, core.get_error()])
		snapshot = core.get_snapshot()
		require(snapshot.vram.size() == 65536 and snapshot.palette.size() == 512 and snapshot.oam.size() == 544, "Drawing data sizes")
		require(snapshot.raster.size() == 262144, "Per-line drawing packet size")
		require(snapshot.backgrounds.size() == 4, "Background descriptors")
		require(snapshot.active_bombs == 0, "Fresh Ceres route has no active bombs")
		require(snapshot.mode7.size() == 8 and snapshot.has("obj_enabled") and snapshot.has("bg3priority"), "Mode 7 and layer descriptors")
		if snapshot.state == 8:
			if snapshot.position != previous:
				movement += 1
			previous = snapshot.position
			if snapshot.room == 0xdf45:
				reached_ceres = true
				if snapshot.raster[0] == 1 and snapshot.raster[31*1024] == 7:
					saw_ceres_split = true
		if frame % 30 == 0:
			var audio: PackedVector2Array = core.get_audio()
			require(audio.size() == 534, "Audio packet size")
			for sample in audio:
				if sample != Vector2.ZERO:
					audible += 1
					break
		if frame % 600 == 0:
			print("NATIVE_EXTENSION_FRAME %d state=%d room=%04x" % [frame, snapshot.state, snapshot.room])
			await process_frame
	require(gameplay > 300 and movement > 60 and audible > 10 and reached_ceres, "Ceres gameplay, movement and audio evidence")
	require(saw_ceres_split, "Ceres HUD and Mode 7 captured on separate scanlines")
	require(snapshot.cpu_opcodes == 0 and snapshot.spc_opcodes == 0, "No CPU/SPC opcode execution")
	core.close()
	require(core.get_snapshot().is_empty(), "Closed core has no drawing data")
	require(not core.step(0), "Closed core rejects ticks")
	require(core.boot(ROM, SAVE), "Reboot: " + core.get_error())
	for frame in range(360):
		require(core.step(0), "Reboot tick")
	core.close()
	core = null
	require(FileAccess.get_sha256(ROM) == hash_before, "ROM stayed intact")
	if FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	print("NATIVE_EXTENSION_OK: registered GDExtension, 18000 C ticks, %d gameplay ticks, Ceres movement/audio, VRAM/CGRAM/OAM packets, single ownership, close/reboot, intact ROM; full campaign pending" % gameplay)
	quit()
