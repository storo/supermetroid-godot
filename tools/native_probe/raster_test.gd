extends SceneTree

const Renderer = preload("res://scripts/native_raster_renderer.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var index := args.find("--raster-fixture")
	if index < 0 or index+1 >= args.size():
		push_error("Missing --raster-fixture directory")
		quit(1)
		return
	var directory: String = args[index+1]
	var raster := FileAccess.get_file_as_bytes(directory.path_join("frame.raster"))
	var snapshot := {
		"vram": FileAccess.get_file_as_bytes(directory.path_join("frame.vram")),
		"oam": FileAccess.get_file_as_bytes(directory.path_join("frame.oam")),
		"raster": raster,
		"obj_size": raster[87],
	}
	root.size = Vector2i(256,224)
	root.content_scale_size = Vector2i.ZERO
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var renderer := Renderer.new()
	root.add_child(renderer)
	renderer.enhanced = false
	renderer.present(snapshot)
	for frame in range(5): await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory.path_join("godot.png"))
	renderer.sprite_view.get_texture().get_image().save_png(directory.path_join("sprites.png"))
	renderer.main_view.get_texture().get_image().save_png(directory.path_join("main.png"))
	renderer.sub_view.get_texture().get_image().save_png(directory.path_join("sub.png"))
	print("RASTER_GODOT_OK: native tiles, sprites and per-line composition rendered by Godot")
	quit()
