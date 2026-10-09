extends Control

const Renderer = preload("res://scripts/native_raster_renderer.gd")
const InputSetup = preload("res://scripts/input_setup.gd")
const ROM := "res://rom_src/Super Metroid (Japan, USA) (En,Ja).sfc"
var core: RefCounted
var extension_resource: Resource
var renderer: Node2D
var audio_player: AudioStreamPlayer
var audio_playback: AudioStreamGeneratorPlayback
var status: Label
var enhanced := true
var paused := false
var snapshot: Dictionary = {}
var capture_mode := false
var frame := 0

func _ready() -> void:
	InputSetup.install()
	capture_mode = "--native-core-capture" in OS.get_cmdline_user_args()
	extension_resource = load("res://native/sm_native.gdextension")
	if extension_resource == null or not ClassDB.class_exists("SmNativeCore"):
		push_error("Native extension has not been built")
		get_tree().quit(1)
		return
	core = ClassDB.instantiate("SmNativeCore")
	var save := "user://native_campaign_capture.srm" if capture_mode else "user://native_campaign.srm"
	if capture_mode and FileAccess.file_exists(save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	if not core.boot(ROM,save):
		push_error(core.get_error())
		get_tree().quit(1)
		return
	var title := Label.new()
	title.text = "SUPER METROID"
	title.position = Vector2(36,20)
	title.add_theme_font_size_override("font_size",26)
	add_child(title)
	status = Label.new()
	status.position = Vector2(36,57)
	add_child(status)
	var clip := Control.new()
	clip.position = Vector2(256,96)
	clip.size = Vector2(256,224)
	clip.scale = Vector2(3,3)
	clip.clip_contents = true
	add_child(clip)
	renderer = Renderer.new()
	clip.add_child(renderer)
	var help := Label.new()
	help.text = "A/D mover · Espacio saltar · J disparar · Enter iniciar · F1 comparar gráficos · Esc pausar"
	help.position = Vector2(36,775)
	add_child(help)
	if capture_mode:
		# Reach Ceres using the reference's own menu/intro flow, without RAM edits.
		for tick in range(9000):
			if not core.step(0x1080 if tick%60<2 else 0):
				push_error(core.get_error())
				get_tree().quit(1)
				return
			snapshot = core.get_snapshot()
			if snapshot.state == 8 and snapshot.room == 0xdf45:
				break
		if snapshot.get("state",-1) != 8:
			push_error("Capture did not reach Ceres")
			get_tree().quit(1)
			return
		for tick in range(180):
			if not core.step(0):
				push_error(core.get_error())
				get_tree().quit(1)
				return
		snapshot = core.get_snapshot()
		print("NATIVE_RENDER_STATE mode=%d brightness=%d position=%s backgrounds=%s" % [snapshot.mode,snapshot.brightness,snapshot.position,str(snapshot.backgrounds)])
		paused = true
		renderer.present(snapshot)
		call_deferred("capture_views")
	else:
		audio_player = AudioStreamPlayer.new()
		var generator := AudioStreamGenerator.new()
		generator.mix_rate = 32040
		generator.buffer_length = 0.12
		audio_player.stream = generator
		add_child(audio_player)
		audio_player.play()
		audio_playback = audio_player.get_stream_playback()

func joypad() -> int:
	var joy := 0
	if Input.is_action_pressed("right"): joy |= 0x100
	if Input.is_action_pressed("left"): joy |= 0x200
	if Input.is_action_pressed("up"): joy |= 0x800
	if Input.is_action_pressed("down"): joy |= 0x400
	if Input.is_action_pressed("jump"): joy |= 0x80
	if Input.is_action_pressed("fire"): joy |= 0x40
	if Input.is_action_pressed("run"): joy |= 0x8000
	if Input.is_action_pressed("aim_up"): joy |= 0x10
	if Input.is_action_pressed("aim_down"): joy |= 0x20
	if Input.is_key_pressed(KEY_K): joy |= 0x2000
	if Input.is_key_pressed(KEY_ENTER): joy |= 0x1000
	return joy

func _physics_process(_delta: float) -> void:
	if core == null or paused: return
	if not core.step(joypad()):
		paused = true
		status.text = core.get_error()
		return
	snapshot = core.get_snapshot()
	renderer.present(snapshot)
	status.text = "Arte %s · %s" % ["mejorado" if enhanced else "original", "Ceres" if snapshot.area==6 else "Zebes"]
	if audio_playback and audio_playback.get_frames_available() >= 534:
		audio_playback.push_buffer(core.get_audio())
	frame += 1

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F1:
			enhanced = not enhanced
			renderer.enhanced = enhanced
			renderer.present(snapshot)
		elif event.keycode == KEY_ESCAPE:
			paused = not paused
			if audio_player: audio_player.stream_paused = paused

func capture_views() -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://docs/qa/native_ceres_enhanced.png")
	renderer.enhanced = false
	renderer.present(snapshot)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://docs/qa/native_ceres_original.png")
	print("NATIVE_CORE_CAPTURE_OK: Ceres reached through original C menu/intro; Godot draws tile/sprite packets")
	core.close()
	core = null
	var save := "user://native_campaign_capture.srm"
	if FileAccess.file_exists(save): DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	get_tree().quit()

func _exit_tree() -> void:
	if audio_player:
		audio_player.stop()
		audio_player.stream = null
	if core:
		core.close()
		core = null
	extension_resource = null
