extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func require(condition: bool,detail: String) -> void:
	if not condition:
		push_error("CAMPAIGN_MENU_FAILED: "+detail)
		quit(1)
		assert(false,detail)

func native_button(node: Node) -> Button:
	if node is Button and node.text.begins_with("JUGAR DESDE CERES"):return node
	for child in node.get_children():
		var found := native_button(child)
		if found:return found
	return null

func run() -> void:
	require("--native-core-ui-test" in OS.get_cmdline_user_args(),"Dedicated test SRAM required")
	change_scene_to_file("res://scenes/main.tscn")
	await scene_changed
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png("res://docs/qa/native_campaign_menu.png")
	var button := native_button(current_scene)
	require(button!=null,"Campaign button visible with ROM and native build")
	button.pressed.emit()
	await scene_changed
	for i in range(30):await physics_frame
	require(current_scene.core!=null and current_scene.core.get_state().frame>=10,"Native campaign running from title menu")
	var event := InputEventKey.new()
	event.pressed=true
	event.keycode=KEY_F10
	current_scene._unhandled_key_input(event)
	await scene_changed
	require(current_scene.scene_file_path=="res://scenes/main.tscn","F10 returned to main menu")
	button=native_button(current_scene)
	button.pressed.emit()
	await scene_changed
	for i in range(10):await physics_frame
	require(current_scene.core!=null and not current_scene.core.get_state().is_empty(),"Core can reopen after ownership cleanup")
	print("CAMPAIGN_MENU_OK: title launches native campaign, F10 returns, core reopens; dedicated test SRAM")
	quit()
