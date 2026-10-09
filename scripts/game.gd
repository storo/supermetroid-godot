extends Node2D

const InputSetup = preload("res://scripts/input_setup.gd")
const Atmosphere = preload("res://scripts/atmosphere.gd")
const Effects = preload("res://scripts/effects.gd")
const WorldMap = preload("res://scripts/world_map.gd")
const AREAS := ["CRATERIA","BRINSTAR","NORFAIR","WRECKED SHIP","MARIDIA","TOURIAN","CERES"]
const ITEM_NAMES := ["ENERGY TANK","MISSILES","SUPER MISSILES","POWER BOMBS","BOMBS","CHARGE BEAM","ICE BEAM","HI-JUMP BOOTS","SPEED BOOSTER","WAVE BEAM","SPAZER","SPRING BALL","VARIA SUIT","GRAVITY SUIT","X-RAY SCOPE","PLASMA BEAM","GRAPPLE BEAM","SPACE JUMP","SCREW ATTACK","MORPH BALL","RESERVE TANK"]
const ABILITY_KEYS := {4:"bombs",5:"charge",6:"ice",7:"hi_jump",8:"speed",9:"wave",10:"spazer",11:"spring",12:"varia",13:"gravity",14:"xray",15:"plasma",16:"grapple",17:"space_jump",18:"screw",19:"morph",20:"reserve"}

var room: NativeRoom
var samus: NativeSamus
var camera: Camera2D
var effects: Node2D
var atmosphere: Control
var hud: Control
var overlay: Control
var energy_label: Label
var ammo_label: Label
var room_label: Label
var art_label: Label
var toast_label: Label
var minimap: Control
var catalog: Array = []
var enemy_catalog: Dictionary = {}
var enemy_lasers: Array = []
var enemies: Array = []
var elevators: Array[NativeElevator] = []
var elevator_fade: ColorRect
var item_nodes: Array = []
var item_textures: Dictionary = {}
var game_time := 0.0
var items: Array = []
var collected: Dictionary = {}
var discovered: Dictionary = {}
var room_changes: Dictionary = {}
var current_id := "91F8"
var enhanced := true
var playing := false
var has_started := false
var exploration := false
var transition_cooldown := 0.0
var overlay_kind := ""
var toast_timer := 0.0
var ship: Sprite2D
var post_material: ShaderMaterial
var room_list: ItemList
var current_catalog: Array = []
var selected_state := 0
var progression := NativeProgression.new()
var enemies_killed := 0
var save_path := "user://savegame.json"
var sound_player: AudioStreamPlayer
var sound_bank: Dictionary = {}

func _exit_tree() -> void:
	if is_instance_valid(sound_player):
		sound_player.stop()
		sound_player.stream=null

func finish_test() -> void:
	set_playing(false)
	sound_player.stop()
	sound_player.stream=null
	# Let the audio mixer retire the last playback before the process exits.
	await get_tree().create_timer(0.15).timeout
	get_tree().quit()

func _ready() -> void:
	InputSetup.install()
	catalog = JSON.parse_string(FileAccess.get_file_as_string("res://assets/extracted/room_catalog.json"))
	enemy_catalog = JSON.parse_string(FileAccess.get_file_as_string("res://assets/extracted/objects/catalog.json"))
	create_world()
	create_hud()
	load_room("91F8",Vector2(1152,1080))
	show_title()
	if "--smoke-test" in OS.get_cmdline_user_args(): call_deferred("run_smoke_test")
	if "--capture" in OS.get_cmdline_user_args(): call_deferred("capture_preview")
	if "--room-audit" in OS.get_cmdline_user_args(): call_deferred("run_room_audit")
	if "--progression-test" in OS.get_cmdline_user_args(): call_deferred("run_progression_test")
	if "--pirate-test" in OS.get_cmdline_user_args(): call_deferred("run_pirate_test")
	if "--pirate-capture" in OS.get_cmdline_user_args(): call_deferred("capture_pirates")
	if "--elevator-test" in OS.get_cmdline_user_args(): call_deferred("run_elevator_test")
	if "--elevator-capture" in OS.get_cmdline_user_args(): call_deferred("capture_elevator")
	if "--elevator-morph-test" in OS.get_cmdline_user_args(): call_deferred("run_elevator_morph_test")

func create_world() -> void:
	var background_layer := CanvasLayer.new()
	background_layer.layer = -10
	add_child(background_layer)
	atmosphere = Atmosphere.new()
	atmosphere.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background_layer.add_child(atmosphere)
	samus = NativeSamus.new()
	samus.name = "Samus"
	samus.z_index = 10
	add_child(samus)
	samus.fired.connect(spawn_projectile)
	samus.bomb_dropped.connect(drop_bomb)
	samus.injured.connect(func():
		play_sound("hurt")
		if samus.health<=0: show_death())
	camera = Camera2D.new()
	camera.zoom = Vector2(3.5,3.5)
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 8
	camera.limit_smoothed = true
	add_child(camera)
	effects = Effects.new()
	effects.z_index = 20
	add_child(effects)
	var post_layer := CanvasLayer.new()
	post_layer.layer = 2
	add_child(post_layer)
	var post := ColorRect.new()
	post.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	post_material = ShaderMaterial.new()
	post_material.shader = load("res://shaders/postprocess.gdshader")
	post.material = post_material
	post_layer.add_child(post)
	var fade_layer := CanvasLayer.new()
	fade_layer.layer=5
	add_child(fade_layer)
	elevator_fade=ColorRect.new()
	elevator_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	elevator_fade.color=Color(0,0,0,0)
	elevator_fade.mouse_filter=Control.MOUSE_FILTER_IGNORE
	fade_layer.add_child(elevator_fade)
	sound_player = AudioStreamPlayer.new()
	sound_player.playback_type=AudioServer.PLAYBACK_TYPE_STREAM
	add_child(sound_player)
	for type in ["beam","missile","pickup","hurt","door","bomb"]: sound_bank[type] = make_sound(type)

func load_room(room_id: String, preferred: Vector2 = Vector2(-1,-1), state_index: int = -1) -> void:
	if not FileAccess.file_exists("res://assets/extracted/rooms/%s.json"%room_id):
		notify("Sala aún no importada: %s"%room_id)
		return
	if room:
		room_changes[current_id] = {"removed":room.removed.duplicate(),"doors":room.opened_doors.duplicate()}
		remove_child(room)
		room.queue_free()
	for enemy in enemies:
		if is_instance_valid(enemy):
			remove_child(enemy)
			enemy.queue_free()
	enemies.clear()
	for elevator in elevators:
		remove_child(elevator)
		elevator.queue_free()
	elevators.clear()
	samus.set_elevator_pose(false)
	elevator_fade.color=Color(0,0,0,0)
	for node in item_nodes:
		if is_instance_valid(node):
			remove_child(node)
			node.queue_free()
	item_nodes.clear()
	items.clear()
	if ship:
		remove_child(ship)
		ship.queue_free()
		ship = null
	effects.projectiles.clear()
	effects.bombs.clear()
	enemy_lasers.clear()
	current_id = room_id
	if state_index<0:
		var room_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/extracted/rooms/%s.json"%room_id))
		state_index = progression.select_state(room_data,samus.abilities,samus.max_missiles)
	selected_state = state_index
	enemies_killed = 0
	room = NativeRoom.new()
	room.name = "Room_"+room_id
	room.enhanced = enhanced
	room.exploration = exploration
	room.camera = camera
	add_child(room)
	room.configure(room_id,state_index)
	if room_changes.has(room_id):
		room.removed = restore_int_keys(room_changes[room_id].removed)
		room.opened_doors = restore_int_keys(room_changes[room_id].doors)
		room.build_collision()
	if room_id=="91F8": create_ship()
	samus.position = room.find_spawn(preferred)
	samus.velocity = Vector2.ZERO
	samus.invulnerability = 0.5
	samus.set_enhanced(enhanced)
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = room.width*16
	camera.limit_bottom = room.height*16
	camera.position = samus.position+Vector2(0,50)
	camera.reset_smoothing()
	discovered[room_id] = true
	transition_cooldown = 1.0
	atmosphere.exterior = int(room.data.area)==0 and int(room.state.tileset) in [0,1]
	for spawn in room.state.enemies:
		var id: String = spawn.id
		if id=="D73F":
			var elevator := NativeElevator.new()
			elevator.configure(spawn,samus,room)
			elevator.enhanced=enhanced
			elevator.active=playing
			elevator.departed.connect(func(index: int): call_deferred("enter_elevator",room_id,index))
			elevator.finished.connect(func(): samus.controls_enabled=playing)
			elevator.started.connect(func():
				effects.projectiles.clear()
				effects.bombs.clear()
				play_sound("door"))
			add_child(elevator)
			elevators.append(elevator)
			continue
		if not enemy_catalog.has(id) or not enemy_catalog[id].runtime_supported: continue
		var enemy: NativeEnemy = NativePirate.new() if str(enemy_catalog[id].animation).begins_with("pirate_") else NativeEnemy.new()
		enemy.configure(enemy_catalog[id],spawn,samus)
		enemy.enhanced = enhanced
		enemy.active = playing
		if enemy is NativePirate:
			enemy.laser_fired.connect(spawn_enemy_laser)
			enemy.player_projectiles=effects.projectiles
		add_child(enemy)
		enemies.append(enemy)
	item_textures.clear()
	for kind in range(4,21):
		item_textures[kind] = {"original":load("res://assets/extracted/items/%02d/%02d_original.png"%[int(room.state.tileset),kind]),"enhanced":load("res://assets/extracted/items/%02d/%02d_enhanced.png"%[int(room.state.tileset),kind])}
	for plm in room.state.plms:
		var code: int = str(plm.id).hex_to_int()
		if code<0xEED7 or code>0xEFCF: continue
		var item: int = ((code-0xEED7)/4)%21
		var key := "%s:%d"%[room_id,int(plm.argument)&0xff]
		if collected.has(key): continue
		items.append({"p":Vector2(plm.x*16+8,plm.y*16+8),"type":item,"key":key,"hidden":code>=0xEF7F})
	refresh_hud()
	refresh_grey_doors()
	if has_started: notify(format_room_name(room.data.name))

func refresh_grey_doors() -> void:
	for cap in room.door_caps:
		if cap.color=="grey":
			cap.ready = progression.grey_door_ready(int(cap.condition),int(room.data.area),enemies_killed,int(room.state.get("enemy_death_quota",0)))

func restore_int_keys(source: Dictionary) -> Dictionary:
	var result := {}
	for key in source: result[int(str(key))]=source[key]
	return result

func spawn_enemy_laser(origin: Vector2, direction: int, damage: int, speed: int) -> void:
	enemy_lasers.append({"p":origin,"direction":direction,"damage":damage,"speed":speed,"ticks":0})
	effects.enemy_lasers=enemy_lasers

func is_on_elevator() -> bool:
	for elevator in elevators:
		if elevator.is_riding(): return true
	return false

func enter_elevator(source_id: String, index: int) -> void:
	if current_id!=source_id or index<0 or index>=room.data.doors.size(): return
	var door: Dictionary=room.data.doors[index]
	if door.get("kind","")!="elevator": return
	var arrival_x := int(door.screen_x)*256+128
	load_room(door.destination,Vector2(arrival_x,int(door.screen_y)*256+128))
	if elevators.is_empty():
		samus.controls_enabled=playing
		return
	var destination: NativeElevator=elevators[0]
	for elevator in elevators:
		if absf(elevator.home.x-arrival_x)<absf(destination.home.x-arrival_x): destination=elevator
	destination.begin_arrival()
	camera.position=samus.position+Vector2(0,50)
	camera.reset_smoothing()
	elevator_fade.color=Color(0,0,0,1)

func create_ship() -> void:
	ship = Sprite2D.new()
	ship.position = Vector2(1152,1144)
	ship.z_index = 4
	ship.material=load("res://assets/remastered/sprite_lighting.tres") if enhanced else null
	ship.texture = load("res://assets/extracted/objects/ship_%s.png"%("enhanced" if enhanced else "original"))
	ship.scale = Vector2.ONE*(0.25 if enhanced else 1.0)
	ship.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(ship)
	room.add_rectangle(Rect2(1100,1101,104,8))

func _physics_process(delta: float) -> void:
	if not playing or not room: return
	for elevator in elevators:
		if elevator.can_depart() and Input.is_action_just_pressed("up" if elevator.direction<0 else "down"):
			elevator.begin_departure()
	refresh_grey_doors()
	transition_cooldown = maxf(0,transition_cooldown-delta)
	for i in range(enemy_lasers.size()-1,-1,-1):
		var laser: Dictionary=enemy_lasers[i]
		laser.ticks+=1
		if laser.ticks>=6:
			var step := Vector2(int(laser.direction)*float(laser.speed)*delta,0)
			var player_bounds := Rect2(samus.position-Vector2(6,7 if samus.morphing else (12 if samus.crouching else 20)),Vector2(12,14 if samus.morphing else (24 if samus.crouching else 40)))
			var sweep := Rect2(Vector2(minf(laser.p.x,laser.p.x+step.x)-16,laser.p.y-4),Vector2(absf(step.x)+32,8))
			laser.p+=step
			if sweep.intersects(player_bounds) and samus.invulnerability<=0:
				samus.damage(int(laser.damage),laser.p)
				enemy_lasers.remove_at(i)
				continue
		var offset: Vector2=(laser.p-camera.get_screen_center_position()).abs()
		var half_view := get_viewport_rect().size/camera.zoom/2
		if offset.x>half_view.x+32 or offset.y>half_view.y+32 or laser.ticks>360:
			enemy_lasers.remove_at(i)
	for i in range(effects.projectiles.size()-1,-1,-1):
		var bullet: Dictionary = effects.projectiles[i]
		bullet.life -= delta
		var previous: Vector2 = bullet.p
		var step: Vector2 = bullet.dir*bullet.speed*delta
		var stop := false
		for sample in range(1,ceili(step.length()/3.0)+1):
			var p: Vector2 = previous+step*minf(1.0,sample*3.0/maxf(step.length(),0.01))
			for li in range(enemy_lasers.size()-1,-1,-1):
				if Rect2(enemy_lasers[li].p-Vector2(16,4),Vector2(32,8)).grow(2).has_point(p):
					effects.burst(p,Color("ffc576"),6)
					enemy_lasers.remove_at(li)
					stop=true
					break
			if stop: break
			for enemy in enemies:
				if not is_instance_valid(enemy) or enemy.is_queued_for_deletion(): continue
				if enemy.contains_hit(p):
					var killed: bool = enemy.hit(100 if bullet.missile else (60 if bullet.charge>0.5 else 20),samus.abilities.get("ice",false) and not bullet.missile)
					if killed:
						enemies_killed += 1
						effects.burst(enemy.position,Color("7decb3"),20)
						samus.health = mini(samus.max_health,samus.health+5)
					stop = true
					break
			if stop: break
			var weapon := "missile" if bullet.missile else ("charge" if bullet.charge>0.5 else "beam")
			for item in items:
				if item.hidden and item.p.distance_to(p)<12: item.hidden=false
			var result := room.hit_block(p,weapon)
			if result.stop:
				if result.has("door"): play_sound("door")
				effects.burst(p,Color("c0fdbb"),6)
				stop=true
				break
		bullet.p += step
		if stop or bullet.life<=0: effects.projectiles.remove_at(i)
	for i in range(effects.bombs.size()-1,-1,-1):
		var bomb: Dictionary = effects.bombs[i]
		bomb.time += delta
		if bomb.time>0.9:
			effects.burst(bomb.p,Color("dcacff"),30)
			play_sound("bomb")
			for oy in range(-2,3):
				for ox in range(-2,3): room.hit_block(bomb.p+Vector2(ox,oy)*16,"bomb")
			for enemy in enemies:
				if is_instance_valid(enemy) and not enemy.is_queued_for_deletion() and enemy.position.distance_to(bomb.p)<36:
					if enemy.hit(30): enemies_killed += 1
			if samus.morphing and samus.position.distance_to(bomb.p)<30: samus.velocity.y = -260
			effects.bombs.remove_at(i)
	for i in range(items.size()-1,-1,-1):
		if not items[i].hidden and samus.position.distance_to(items[i].p)<23:
			collect_item(items[i])
			items.remove_at(i)
	if transition_cooldown<=0 and not is_on_elevator():
		var door_index := room.door_near(samus.position)
		if door_index>=0 and door_index<room.data.doors.size():
			transition_cooldown=1
			call_deferred("enter_door",door_index)
	var cell := Vector2i(samus.position/16)
	if not is_on_elevator() and room.resolve_type(cell)==10: samus.damage(8,samus.position+Vector2(0,1))
	if not is_on_elevator() and samus.position.y>room.height*16+30:
		samus.damage(20,samus.position+Vector2(0,1))
		samus.position = room.find_spawn()

func enter_door(index: int) -> void:
	var door: Dictionary = room.data.doors[index]
	if door.get("kind","")=="elevator_trigger":
		return
	var dir := int(door.direction)&3
	var p := Vector2(door.cap_x*16+8,door.cap_y*16+32)
	if dir==0: p.x+=32
	elif dir==1: p.x-=32
	elif dir==2: p.y+=40
	else: p.y-=40
	load_room(door.destination,p)

func _process(delta: float) -> void:
	if not room: return
	if playing:
		game_time+=delta
		elevator_fade.color=Color(0,0,0,maxf(0,elevator_fade.color.a-delta*2))
		camera.position = samus.position+Vector2(samus.facing*12,50)
		atmosphere.camera_position = camera.get_screen_center_position()
	toast_timer = maxf(0,toast_timer-delta)
	if toast_label: toast_label.visible = toast_timer>0
	if energy_label: refresh_hud()
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("fullscreen"):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif event.is_action_pressed("art"):
		set_enhanced(not enhanced)
	elif event.is_action_pressed("pause"):
		if playing: show_pause()
		elif has_started: resume_game()
	elif event.is_action_pressed("map") and has_started:
		if overlay_kind=="map": resume_game()
		else: show_map()
	elif event.is_action_pressed("catalog"): show_catalog()
	elif event.is_action_pressed("save") and has_started: save_game()
	elif event.is_action_pressed("load"): load_game()
	elif event.is_action_pressed("restart") and overlay_kind=="death": new_game()

func spawn_projectile(origin: Vector2, direction: Vector2, missile: bool, charge: float) -> void:
	effects.projectiles.append({"p":origin,"dir":direction,"missile":missile,"charge":charge,"speed":360 if missile else 600,"life":1.0})
	play_sound("missile" if missile else "beam")

func drop_bomb(origin: Vector2) -> void:
	if effects.bombs.size()<3: effects.bombs.append({"p":origin,"time":0.0})

func collect_item(item: Dictionary) -> void:
	collected[item.key]=true
	var kind: int=item.type
	match kind:
		0:
			samus.max_health+=100
			samus.health=samus.max_health
		1:
			samus.max_missiles+=5
			samus.missiles=samus.max_missiles
		2: samus.abilities["super_missiles"]=true
		3: samus.abilities["power_bombs"]=true
		_:
			if ABILITY_KEYS.has(kind): samus.abilities[ABILITY_KEYS[kind]]=true
	play_sound("pickup")
	effects.burst(item.p,Color("f7db89"),24)
	notify(ITEM_NAMES[kind])

func set_enhanced(value: bool) -> void:
	enhanced=value
	room.set_enhanced(value)
	samus.set_enhanced(value)
	atmosphere.enhanced=value
	effects.enhanced=value
	post_material.set_shader_parameter("enhanced",value)
	for enemy in enemies:
		if is_instance_valid(enemy): enemy.set_enhanced(value)
	for elevator in elevators: elevator.set_enhanced(value)
	if ship:
		ship.material=load("res://assets/remastered/sprite_lighting.tres") if value else null
		ship.texture=load("res://assets/extracted/objects/ship_%s.png"%("enhanced" if value else "original"))
		ship.scale=Vector2.ONE*(0.25 if value else 1.0)
	notify("Arte mejorado" if value else "Assets originales de la ROM")

func new_game() -> void:
	progression.reset()
	collected.clear()
	discovered.clear()
	room_changes.clear()
	if room:
		room.removed.clear()
		room.opened_doors.clear()
	samus.abilities.clear()
	samus.max_health=99
	samus.health=99
	samus.max_missiles=0
	samus.missiles=0
	samus.morphing=false
	samus.crouching=false
	samus.collider.shape=samus.stand_shape
	exploration=false
	has_started=true
	load_room("91F8",Vector2(1152,1080))
	resume_game()
	notify("ZEBES · CRATERIA")

func set_playing(value: bool) -> void:
	playing=value
	samus.controls_enabled=value and not is_on_elevator()
	for elevator in elevators: elevator.active=value
	for enemy in enemies:
		if is_instance_valid(enemy): enemy.active=value
	hud.visible=has_started

func resume_game() -> void:
	if not has_started:
		new_game()
		return
	clear_overlay()
	set_playing(true)

func save_game() -> void:
	if is_on_elevator():
		notify("Espera a que termine el viaje para guardar")
		return
	room_changes[current_id]={"removed":room.removed,"doors":room.opened_doors}
	var data := {"version":2,"rom_sha256":"12b77c4bc9c1832cee8881244659065ee1d84c70c3d29e6eaf92e6798cc2ca72", "room":current_id,"state":selected_state,"position":[samus.position.x,samus.position.y],"health":samus.health,"max_health":samus.max_health,"missiles":samus.missiles,"max_missiles":samus.max_missiles,"abilities":samus.abilities,"collected":collected,"discovered":discovered,"changes":room_changes,"exploration":exploration,"progression":progression.serialize()}
	var file := FileAccess.open(save_path,FileAccess.WRITE)
	if not file:
		notify("No se pudo guardar la partida")
		return
	file.store_string(JSON.stringify(data))
	notify("Partida guardada · F9 para cargar")

func load_game() -> void:
	if not FileAccess.file_exists(save_path):
		notify("Todavía no hay una partida guardada")
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if not data is Dictionary or int(data.get("version",0)) not in [1,2]:
		notify("Partida incompatible")
		return
	collected=data.collected
	discovered=data.discovered
	room_changes=data.changes
	if room:
		# Avoid overwriting loaded room state with the current room when changing scenes.
		room.removed=restore_int_keys(room_changes.get(current_id,{}).get("removed",{}))
		room.opened_doors=restore_int_keys(room_changes.get(current_id,{}).get("doors",{}))
	samus.health=data.health
	samus.max_health=data.max_health
	samus.missiles=data.missiles
	samus.max_missiles=data.max_missiles
	samus.abilities=data.abilities
	progression.restore(data.get("progression",{}))
	samus.morphing=false
	samus.collider.shape=samus.stand_shape
	exploration=data.get("exploration",false)
	has_started=true
	load_room(data.room,Vector2(data.position[0],data.position[1]),data.get("state",0))
	# Enemies respawn on load; their death quota starts again with the population.
	refresh_grey_doors()
	resume_game()
	notify("Partida cargada")

func _draw() -> void:
	if not room: return
	var tex: Texture2D=room.atlas
	var tile_size:=64 if enhanced else 16
	for item in items:
		if item.hidden: continue
		var p: Vector2=item.p
		if enhanced:
			for i in range(3,0,-1): draw_circle(p,5+i*4,Color(0.7,0.95,0.5,0.025))
		var frame_index := int(game_time*15)%2
		if int(item.type)<4:
			var tile:=0x4A+int(item.type)*2+frame_index
			draw_texture_rect_region(tex,Rect2(p-Vector2(8,8),Vector2(16,16)),Rect2((tile%32)*tile_size,(tile/32)*tile_size,tile_size,tile_size))
		else:
			var texture: Texture2D=item_textures[int(item.type)]["enhanced" if enhanced else "original"]
			draw_texture_rect_region(texture,Rect2(p-Vector2(8,8),Vector2(16,16)),Rect2(frame_index*tile_size,0,tile_size,tile_size))

func notify(message: String) -> void:
	if toast_label:
		toast_label.text=message
		toast_timer=3

func format_room_name(value: String) -> String:
	var regex:=RegEx.new()
	regex.compile("([a-z])([A-Z])")
	return regex.sub(value,"$1 $2",true).to_upper()

func make_sound(kind: String) -> AudioStreamWAV:
	var rate:=22050
	var length:=0.1
	var frequency:=650.0
	match kind:
		"missile": frequency=140;length=0.15
		"pickup": frequency=880;length=0.4
		"hurt": frequency=90;length=0.15
		"door": frequency=280;length=0.2
		"bomb": frequency=70;length=0.2
	var bytes:=PackedByteArray()
	bytes.resize(int(rate*length)*2)
	for i in range(int(rate*length)):
		var t:=float(i)/rate
		var envelope:=pow(1.0-t/length,2)
		var f:=frequency*(1.0+(-0.7 if kind in ["beam","missile"] else 0.2)*t/length)
		var wave:=sin(TAU*f*t)*envelope*0.18
		bytes.encode_s16(i*2,int(wave*32767))
	var stream:=AudioStreamWAV.new()
	stream.format=AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate=rate
	stream.data=bytes
	return stream

func play_sound(kind: String) -> void:
	if sound_bank.has(kind):
		sound_player.stream=sound_bank[kind]
		sound_player.play()

func create_hud() -> void:
	var ui_layer:=CanvasLayer.new()
	ui_layer.layer=10
	add_child(ui_layer)
	hud=Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter=Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(hud)
	var top:=PanelContainer.new()
	top.position=Vector2(30,25)
	top.custom_minimum_size=Vector2(1220,74)
	top.add_theme_stylebox_override("panel",panel_style(Color(0.02,0.045,0.06,0.86)))
	hud.add_child(top)
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",30)
	top.add_child(row)
	var energy_box:=VBoxContainer.new()
	row.add_child(energy_box)
	energy_box.add_child(label("ENERGY",11,Color("83b1a6")))
	energy_label=label("099",27,Color("e4f3d4"))
	energy_box.add_child(energy_label)
	var ammo_box:=VBoxContainer.new()
	row.add_child(ammo_box)
	ammo_box.add_child(label("MISSILES",11,Color("83b1a6")))
	ammo_label=label("00 / 00",24,Color("c0dec7"))
	ammo_box.add_child(ammo_label)
	var divider:=VSeparator.new()
	row.add_child(divider)
	var room_box:=VBoxContainer.new()
	room_box.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	row.add_child(room_box)
	room_box.add_child(label("ZEBES",11,Color("83b1a6")))
	room_label=label("CRATERIA / LANDING SITE",17,Color("dce6df"))
	room_box.add_child(room_label)
	art_label=label("ARTE MEJORADO · F1",11,Color("83b1a6"))
	art_label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	row.add_child(art_label)
	var hints:=label("A / D   MOVER      ESPACIO   SALTAR      J   DISPARAR      C   MORPH      TAB   MAPA      ESC   PAUSA",12,Color("9bb6ad"))
	hints.position=Vector2(30,761)
	hud.add_child(hints)
	toast_label=label("",19,Color("e0f4c1"))
	toast_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	toast_label.position=Vector2(230,685)
	toast_label.size=Vector2(820,35)
	toast_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	hud.add_child(toast_label)
	overlay=Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(overlay)

func refresh_hud() -> void:
	energy_label.text="%03d"%samus.health
	ammo_label.text="%02d / %02d"%[samus.missiles,samus.max_missiles]
	room_label.text="%s / %s"%[AREAS[clampi(int(room.data.area),0,6)],format_room_name(room.data.name)]
	art_label.text="ARTE MEJORADO · F1" if enhanced else "ARTE ORIGINAL · F1"

func label(text: String, font_size: int, color: Color = Color.WHITE) -> Label:
	var node:=Label.new()
	node.text=text
	node.add_theme_font_size_override("font_size",font_size)
	node.add_theme_color_override("font_color",color)
	return node

func panel_style(color: Color) -> StyleBoxFlat:
	var style:=StyleBoxFlat.new()
	style.bg_color=color
	style.border_color=Color(0.35,0.64,0.52,0.28)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left=22
	style.content_margin_right=22
	style.content_margin_top=14
	style.content_margin_bottom=14
	return style

func button(text: String, callback: Callable, primary: bool = false) -> Button:
	var node:=Button.new()
	node.text=text
	node.custom_minimum_size=Vector2(310,49)
	node.alignment=HORIZONTAL_ALIGNMENT_LEFT
	node.add_theme_font_size_override("font_size",17)
	var base:=Color("b5d99a") if primary else Color(0.02,0.06,0.07,0.7)
	node.add_theme_stylebox_override("normal",panel_style(base))
	node.add_theme_stylebox_override("hover",panel_style(Color("d6ebbd") if primary else Color(0.09,0.20,0.18,0.9)))
	node.add_theme_stylebox_override("pressed",panel_style(Color("89b66d") if primary else Color(0.1,0.27,0.22,0.95)))
	node.add_theme_color_override("font_color",Color("14281b") if primary else Color("dbece2"))
	node.add_theme_color_override("font_hover_color",Color("14281b") if primary else Color.WHITE)
	node.pressed.connect(callback)
	return node

func clear_overlay() -> void:
	for child in overlay.get_children():
		overlay.remove_child(child)
		child.queue_free()
	overlay.visible=false
	overlay_kind=""

func overlay_shell(kind: String) -> VBoxContainer:
	clear_overlay()
	set_playing(false)
	overlay_kind=kind
	overlay.visible=true
	var shade:=ColorRect.new()
	shade.color=Color(0.015,0.028,0.035,0.91 if kind in ["catalog","map"] else 0.73)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(shade)
	var panel:=PanelContainer.new()
	panel.position=Vector2(330,145)
	panel.custom_minimum_size=Vector2(620,500)
	panel.add_theme_stylebox_override("panel",panel_style(Color(0.025,0.05,0.06,0.96)))
	overlay.add_child(panel)
	var box:=VBoxContainer.new()
	box.add_theme_constant_override("separation",12)
	panel.add_child(box)
	return box

func show_title() -> void:
	clear_overlay()
	set_playing(false)
	overlay_kind="title"
	overlay.visible=true
	var gradient:=ColorRect.new()
	gradient.color=Color(0.015,0.03,0.04,0.65)
	gradient.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(gradient)
	var box:=VBoxContainer.new()
	box.position=Vector2(92,130)
	box.custom_minimum_size=Vector2(500,0)
	box.add_theme_constant_override("separation",10)
	overlay.add_child(box)
	box.add_child(label("PLANETA ZEBES  /  RECONSTRUCCIÓN EN DESARROLLO",12,Color("9ecab9")))
	box.add_child(label("SUPER",39,Color("dff0d5")))
	var title:=label("METROID",83,Color("e7f2db"))
	title.add_theme_constant_override("outline_size",2)
	title.add_theme_color_override("font_outline_color",Color("163229"))
	box.add_child(title)
	box.add_child(label("VOLVER A ZEBES",16,Color("a6c8b8")))
	var gap:=Control.new()
	gap.custom_minimum_size.y=30
	box.add_child(gap)
	box.add_child(button("NUEVA PARTIDA   →",new_game,true))
	var continue_button:=button("CONTINUAR",load_game)
	continue_button.disabled=not FileAccess.file_exists(save_path)
	box.add_child(continue_button)
	box.add_child(button("EXPLORAR SALAS",show_catalog))
	box.add_child(button("CONTROLES",show_controls))
	var footer:=label("CRATERIA · ARTE EXTRAÍDO DE TU ROM Y MEJORADO\nVersión jugable en construcción. Historia y jefes todavía pendientes.",13,Color("94afa3"))
	footer.position=Vector2(92,727)
	overlay.add_child(footer)

func show_pause() -> void:
	var box:=overlay_shell("pause")
	box.add_child(label("PAUSA",30,Color("d7eccd")))
	box.add_child(label(format_room_name(room.data.name),14,Color("92b5a6")))
	box.add_child(button("VOLVER AL JUEGO",resume_game,true))
	box.add_child(button("MAPA",show_map))
	box.add_child(button("GUARDAR PARTIDA · F5",save_game))
	box.add_child(button("CARGAR PARTIDA · F9",load_game))
	box.add_child(button("CONTROLES",show_controls))
	box.add_child(button("MENÚ PRINCIPAL",show_title))

func show_controls() -> void:
	var box:=overlay_shell("controls")
	box.add_child(label("CONTROLES",29,Color("d7eccd")))
	box.add_child(label("A / D o flechas       Mover\nEspacio / Z            Saltar · soltar acorta el salto\nJ / X                        Disparar · mantener para cargar\nK                             Misiles\nShift                        Correr\nW / Q / E                 Apuntar arriba / diagonal arriba / abajo\nS                             Agacharse\nC                             Morph Ball (requiere el objeto)\nB                             Bomba (requiere el objeto)\nTab                          Mapa\nF1                            Comparar arte original / mejorado\nF4                            Explorar salas\nF5 / F9                     Guardar / cargar\nF11                          Pantalla completa",17,Color("bdd3c7")))
	box.add_child(label("Mando: stick · A salto · X disparo · B misil · Y morph\nPara saltar en la pared: pulsa salto alejándote de ella.",13,Color("91b5a3")))
	box.add_child(button("VOLVER",resume_game if has_started else show_title,true))

func show_death() -> void:
	var box:=overlay_shell("death")
	box.add_child(label("SEÑAL PERDIDA",33,Color("e8c6a3")))
	box.add_child(label("La energía del traje se agotó.",18,Color("bdd3c7")))
	box.add_child(button("CARGAR PARTIDA",load_game,true))
	box.add_child(button("NUEVA PARTIDA · R",new_game))
	box.add_child(button("MENÚ PRINCIPAL",show_title))

func show_map() -> void:
	clear_overlay()
	set_playing(false)
	overlay_kind="map"
	overlay.visible=true
	var shade:=ColorRect.new()
	shade.color=Color(0.015,0.028,0.035,0.96)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(shade)
	var title:=label("MAPA / "+AREAS[int(room.data.area)],28,Color("cce6c0"))
	title.position=Vector2(70,50)
	overlay.add_child(title)
	var map:=WorldMap.new()
	map.catalog=catalog
	map.current_id=current_id
	map.discovered=discovered
	map.area=int(room.data.area)
	map.exploration=exploration
	map.position=Vector2(200,145)
	map.size=Vector2(830,480)
	map.selected.connect(func(id: String): load_room(id);resume_game())
	overlay.add_child(map)
	var note:=label("Salas descubiertas: %d · Tab para volver"%discovered.size(),15,Color("94b5a8"))
	note.position=Vector2(70,720)
	overlay.add_child(note)
	var back:=button("VOLVER",resume_game,true)
	back.position=Vector2(900,710)
	overlay.add_child(back)

func show_catalog() -> void:
	clear_overlay()
	set_playing(false)
	overlay_kind="catalog"
	overlay.visible=true
	var shade:=ColorRect.new()
	shade.color=Color(0.016,0.03,0.038,0.97)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(shade)
	var title:=label("EXPLORAR ZEBES",31,Color("d7eccd"))
	title.position=Vector2(70,45)
	overlay.add_child(title)
	var description:=label("Visor de las salas originales. Los eventos, jefes y algunos obstáculos todavía no están reconstruidos.",15,Color("94b5a8"))
	description.position=Vector2(70,94)
	overlay.add_child(description)
	var filter:=LineEdit.new()
	filter.placeholder_text="Buscar sala o dirección ROM…"
	filter.position=Vector2(70,138)
	filter.size=Vector2(610,42)
	filter.add_theme_font_size_override("font_size",17)
	overlay.add_child(filter)
	room_list=ItemList.new()
	room_list.position=Vector2(70,197)
	room_list.size=Vector2(610,483)
	room_list.add_theme_font_size_override("font_size",16)
	room_list.add_theme_constant_override("v_separation",10)
	room_list.add_theme_stylebox_override("panel",panel_style(Color(0.035,0.07,0.074,0.9)))
	overlay.add_child(room_list)
	var details:=VBoxContainer.new()
	details.position=Vector2(740,200)
	details.custom_minimum_size=Vector2(420,0)
	details.add_theme_constant_override("separation",20)
	overlay.add_child(details)
	details.add_child(label("SALAS ORIGINALES",13,Color("91b6a5")))
	details.add_child(label("%d SALAS / 7 ÁREAS"%catalog.size(),26,Color("d7eccd")))
	var info:=label("Selecciona una sala para explorar.\n\nLa exploración habilita Morph Ball, bombas,\nmisiles y salto alto para revisar los mapas.\n\nUsa F1 para comparar el arte de la ROM\ncon su versión mejorada.",17,Color("b7d0c3"))
	details.add_child(info)
	var go:=button("ENTRAR A LA SALA   →",func():
		var selection:=room_list.get_selected_items()
		if selection.is_empty(): return
		var entry: Dictionary=current_catalog[selection[0]]
		exploration=true
		has_started=true
		samus.abilities.merge({"morph":true,"bombs":true,"charge":true,"hi_jump":true,"ice":true},true)
		samus.max_missiles=maxi(30,samus.max_missiles)
		samus.missiles=samus.max_missiles
		samus.health=samus.max_health
		load_room(entry.id)
		resume_game(),true)
	details.add_child(go)
	details.add_child(button("VOLVER",resume_game if has_started else show_title))
	filter.text_changed.connect(func(value: String): fill_catalog(value))
	room_list.item_selected.connect(func(index: int):
		var entry: Dictionary=current_catalog[index]
		info.text="%s\n\nÁrea: %s\nTamaño original: %d × %d bloques\nDirección ROM: $8F:%s\nPuertas: %d\n\nLa exploración habilita equipo básico\npara revisar la geometría original."%[format_room_name(entry.name),AREAS[int(entry.area)],entry.width,entry.height,entry.id,entry.doors.size()])
	room_list.item_activated.connect(func(_index: int): go.pressed.emit())
	fill_catalog("")

func fill_catalog(filter_text: String) -> void:
	room_list.clear()
	current_catalog.clear()
	for entry in catalog:
		if filter_text.is_empty() or filter_text.to_lower() in (str(entry.name)+str(entry.id)+AREAS[int(entry.area)]).to_lower():
			current_catalog.append(entry)
			room_list.add_item("%s   ·   %s"%[entry.id,format_room_name(entry.name)])
	if room_list.item_count>0: room_list.select(0)

func capture_preview() -> void:
	await get_tree().create_timer(0.6).timeout
	DisplayServer.window_set_size(Vector2i(1280,800))
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://docs/qa/title.png")
	new_game()
	await get_tree().create_timer(1.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://docs/qa/crateria.png")
	set_enhanced(false)
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://docs/qa/crateria_original.png")
	set_enhanced(true)
	show_catalog()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://docs/qa/catalog.png")
	resume_game()
	load_room("9E9F")
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://docs/qa/morph_ball_room.png")
	show_map()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://docs/qa/map.png")
	print("CAPTURE_OK")
	call_deferred("finish_test")

func run_smoke_test() -> void:
	save_path="user://smoke_savegame.json"
	new_game()
	await get_tree().physics_frame
	assert(room.width==144 and room.height==80)
	assert(samus.health==99)
	var initial_x:=samus.position.x
	Input.action_press("right")
	for i in range(45): await get_tree().physics_frame
	Input.action_release("right")
	assert(samus.position.x>initial_x+30,"Native movement failed")
	for i in range(180):
		if samus.is_on_floor(): break
		await get_tree().physics_frame
	assert(samus.is_on_floor(),"Player did not land")
	Input.action_press("jump")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("jump")
	assert(samus.velocity.y<0,"Jump failed")
	spawn_projectile(samus.position,Vector2.RIGHT,false,0)
	assert(effects.projectiles.size()>0,"Beam creation failed")
	samus.abilities["morph"]=true
	samus.set_morph(true)
	assert(samus.morphing,"Morph failed")
	load_room("9E9F")
	assert(room.data.name=="MorphBall")
	set_enhanced(false)
	assert(not room.enhanced)
	set_enhanced(true)
	var saved_position:=samus.position
	save_game()
	samus.health=1
	load_game()
	assert(samus.health==99,"Health persistence failed")
	assert(samus.position.distance_to(saved_position)<1,"Position persistence failed")
	assert(samus.abilities.get("morph",false),"Ability persistence failed")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	# Validate all imported state geometry, BTS arrays and doors without assuming AI parity.
	var checked:=0
	for entry in catalog:
		var parsed: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/extracted/rooms/%s.json"%entry.id))
		for state_data in parsed.states:
			assert(state_data.blocks.size()>=entry.width*entry.height)
			assert(state_data.bts.size()==state_data.blocks.size())
			assert(state_data.tileset>=0 and state_data.tileset<29)
			checked+=1
	print("SMOKE_OK: native movement, jump, projectile, morph, room switching, art toggle, save/load; %d room states verified"%checked)
	call_deferred("finish_test")


func run_room_audit() -> void:
	set_playing(false)
	var total:=0
	var state_total:=0
	for entry in catalog:
		var parsed: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/extracted/rooms/%s.json"%entry.id))
		for state_index in range(parsed.states.size()):
			load_room(entry.id,Vector2(-1,-1),state_index)
			await get_tree().physics_frame
			await get_tree().process_frame
			assert(room.data.id==entry.id)
			assert(room.width==entry.width and room.height==entry.height)
			assert(room.is_spawn_clear(samus.position),"Invalid spawn in "+entry.id+" state "+str(state_index))
			state_total+=1
		total+=1
		if total%30==0: print("ROOM_AUDIT_PROGRESS ",total,"/",catalog.size())
	print("ROOM_AUDIT_OK: ",total," original rooms and ",state_total," states instantiated with native collision, art and a clear spawn")
	call_deferred("finish_test")

func run_progression_test() -> void:
	set_playing(false)
	var logic := NativeProgression.new()
	var landing: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/extracted/rooms/91F8.json"))
	var morph: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/extracted/rooms/9E9F.json"))
	var pit: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/extracted/rooms/975C.json"))
	assert(logic.select_state(landing,{},0)==0)
	assert(logic.select_state(morph,{"morph":true},5)==0,"Morph pickup must not awaken Zebes")
	assert(logic.select_state(pit,{"morph":true},0)==0)
	assert(logic.select_state(pit,{},5)==0)
	assert(logic.select_state(pit,{"morph":true},5)==1,"Check maximum missiles, even when ammo is empty")
	assert(int(pit.states[1].enemy_death_quota)==5)
	assert(not logic.grey_door_ready(3,0,4,5))
	assert(not logic.has_event(0))
	assert(logic.grey_door_ready(3,0,5,5))
	assert(logic.has_event(0))
	assert(logic.select_state(morph,{},0)==1)
	assert(logic.select_state(landing,{},0)==1)
	assert(logic.select_state(landing,{"power_bombs":true},0)==2)
	logic.mark_event(14)
	assert(logic.select_state(landing,{"power_bombs":true},0)==3,"Original check order must win")
	logic.mark_boss(1,1)
	assert(logic.has_boss(1,1) and not logic.has_boss(0,1),"Boss flags must be scoped to area")
	assert(logic.grey_door_ready(0,1,0,0))
	assert(not logic.grey_door_ready(0,0,0,0))
	assert(not logic.grey_door_ready(4,1,99,0))
	assert(not logic.grey_door_ready(5,1,99,0),"Unimplemented statue must stay locked")
	var restored := NativeProgression.new()
	restored.restore(JSON.parse_string(JSON.stringify(logic.serialize())))
	assert(restored.has_event(14) and restored.has_boss(1,1))
	var checked := 0
	for entry in catalog:
		var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/extracted/rooms/%s.json"%entry.id))
		logic.reset()
		assert(logic.select_state(parsed,{},0)==int(parsed.default_state))
		for check in parsed.state_checks:
			logic.reset()
			var abilities := {}
			var max_ammo := 0
			match str(check.kind):
				"event": logic.mark_event(int(check.argument))
				"boss": logic.mark_boss(int(parsed.area),int(check.argument))
				"main_boss": logic.mark_boss(int(parsed.area),1)
				"morph_missiles": abilities["morph"]=true; max_ammo=5
				"power_bombs": abilities["power_bombs"]=true
				_: assert(false,"Unexpected selector "+str(check.kind))
			assert(logic.select_state(parsed,abilities,max_ammo)==int(check.state),"Conditional selection failed in "+entry.id)
			checked+=1
	save_path="user://progression_test.json"
	new_game()
	samus.abilities["morph"]=true
	samus.max_missiles=5
	samus.missiles=0
	load_room("975C")
	assert(selected_state==1)
	var quota_caps := 0
	for cap in room.door_caps:
		if cap.color=="grey" and int(cap.condition)==3:
			quota_caps+=1
			assert(not cap.ready and not room.unlock_door(cap,"beam"))
	assert(quota_caps==2,"Pit must have two enemy-quota doors")
	enemies_killed=5
	refresh_grey_doors()
	assert(progression.has_event(0))
	for cap in room.door_caps:
		if cap.color=="grey" and int(cap.condition)==3:
			assert(cap.ready and room.unlock_door(cap,"beam"))
	progression.mark_boss(1,1)
	load_room("9E9F")
	assert(selected_state==1 and room.state.address=="8F9ECB")
	save_game()
	progression.reset()
	load_game()
	assert(progression.has_event(0) and progression.has_boss(1,1))
	assert(selected_state==1)
	new_game()
	assert(not progression.has_event(0) and not progression.has_boss(1,1))
	assert(selected_state==0)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	print("PROGRESSION_OK: ",catalog.size()," defaults, ",checked," ROM predicates, priority, area boss flags, death quota, save/load and new game reset")
	call_deferred("finish_test")

func run_pirate_test() -> void:
	new_game()
	samus.abilities["morph"]=true
	samus.max_missiles=5
	load_room("975C")
	assert(selected_state==1 and enemies.size()==5,"All five original Pit pirates must spawn")
	assert(enemies_killed==0 and not progression.has_event(0))
	samus.controls_enabled=false
	samus.position=Vector2(400,112)
	samus.invulnerability=1000
	for i in range(110): await get_tree().physics_frame
	var lasers := 0
	for enemy in enemies:
		assert(enemy is NativePirate and not enemy.sequence_fault)
		assert(enemy.ai_ticks>100 and not enemy.current_hitboxes().is_empty())
		lasers+=enemy.lasers_emitted
	assert(lasers>=3,"Pirates must execute original laser attack instructions")
	for enemy in enemies: enemy.active=false
	enemy_lasers.clear()
	samus.invulnerability=0
	var previous_health := samus.health
	spawn_enemy_laser(samus.position,-1,15,120)
	for i in range(9): await get_tree().physics_frame
	assert(samus.health==previous_health-15,"Enemy laser must damage Samus")
	assert(enemy_lasers.is_empty(),"Contact must consume the laser")
	samus.invulnerability=1000
	spawn_enemy_laser(samus.position+Vector2(80,0),-1,15,120)
	spawn_projectile(samus.position+Vector2(55,0),Vector2.RIGHT,false,0)
	for i in range(3): await get_tree().physics_frame
	assert(enemy_lasers.is_empty(),"Samus must be able to shoot pirate lasers")
	for target in enemies:
		assert(is_instance_valid(target) and not target.is_queued_for_deletion())
		var target_box: Rect2=target.current_hitboxes()[0]
		var origin := target_box.get_center()-Vector2(5,0)
		spawn_projectile(origin,Vector2.RIGHT,false,0)
		for i in range(3): await get_tree().physics_frame
		assert(not is_instance_valid(target) or target.is_queued_for_deletion(),"Beam must hit original compound pirate hitboxes")
		if enemies_killed<5: assert(not progression.has_event(0),"Zebes must wait for all five pirate deaths")
	assert(enemies_killed==5 and progression.has_event(0))
	for cap in room.door_caps:
		if cap.color=="grey": assert(cap.ready and room.unlock_door(cap,"beam"))
	load_room("9E9F")
	assert(selected_state==1,"Combat event must select awakened Morph Ball room")
	print("PIRATE_OK: five Pit pirates, ROM animation/attack streams, ",lasers," laser emissions, laser damage, beam hitboxes, five actual deaths and Zebes awake transition")
	call_deferred("finish_test")

func capture_pirates() -> void:
	new_game()
	samus.abilities["morph"]=true
	samus.max_missiles=5
	load_room("975C",Vector2(400,110))
	samus.controls_enabled=false
	samus.invulnerability=1000
	camera.zoom=Vector2(1.5,1.5)
	for i in range(95): await get_tree().physics_frame
	set_playing(false)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://docs/qa/pit_pirates.png")
	set_enhanced(false)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://docs/qa/pit_pirates_original.png")
	print("PIRATE_CAPTURE_OK")
	call_deferred("finish_test")

func run_elevator_test() -> void:
	save_path="user://elevator_test.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	new_game()
	load_room("97B5",Vector2(128,136))
	for i in range(3): await get_tree().physics_frame
	assert(elevators.size()==1 and elevators[0].can_depart())
	var platform: NativeElevator=elevators[0]
	assert(platform.direction==1 and platform.home==Vector2(128,162))
	assert(float(platform.definition.speed)==90 and int(platform.definition.down_transition_delay_ticks)==48)
	Input.action_press("up")
	for i in range(2): await get_tree().physics_frame
	Input.action_release("up")
	assert(not is_on_elevator(),"Wrong direction must not activate elevator")
	spawn_projectile(samus.position,Vector2.RIGHT,false,0)
	Input.action_press("down")
	for i in range(2): await get_tree().physics_frame
	Input.action_release("down")
	assert(is_on_elevator() and not samus.controls_enabled)
	assert(samus.elevator_pose and samus.current_animation=="front")
	assert(effects.projectiles.is_empty(),"Departure must clear player projectiles")
	var paused_position := platform.position
	set_playing(false)
	for i in range(4): await get_tree().physics_frame
	assert(platform.position==paused_position,"Pause must suspend elevator movement")
	set_playing(true)
	assert(not samus.controls_enabled,"Resume must retain controls lock while travelling")
	set_enhanced(false)
	assert(samus.current_animation=="front" and samus.sprite.texture.get_size()==Vector2(64,64))
	set_enhanced(true)
	assert(samus.current_animation=="front" and samus.sprite.texture.get_size()==Vector2(256,256))
	save_game()
	assert(not FileAccess.file_exists(save_path),"In-flight save must not create a stranded player save")
	for i in range(800):
		await get_tree().physics_frame
		if current_id=="9E9F" and not is_on_elevator(): break
	assert(current_id=="9E9F" and not is_on_elevator(),"Down elevator must arrive at Morph Ball room")
	assert(samus.controls_enabled and samus.position.distance_to(Vector2(1408,680))<2)
	assert(elevators[0].position==Vector2(1408,706))
	print("ELEVATOR_TEST_PROGRESS: arrived in Brinstar")
	assert(not samus.abilities.get("morph",false),"Transit must not grant exploration equipment")
	set_enhanced(false)
	assert(not elevators[0].enhanced and elevators[0].sprite.texture.get_size()==Vector2(128,64))
	set_enhanced(true)
	save_game()
	assert(FileAccess.file_exists(save_path))
	load_game()
	for i in range(2): await get_tree().physics_frame
	assert(elevators.size()==1 and not is_on_elevator() and samus.controls_enabled)
	# Returning after collecting Morph Ball must also work from ball form.
	samus.abilities["morph"]=true
	samus.set_morph(true)
	assert(samus.morphing)
	for i in range(2): await get_tree().physics_frame
	Input.action_press("up")
	for i in range(2): await get_tree().physics_frame
	Input.action_release("up")
	assert(is_on_elevator() and elevators[0].direction==-1)
	assert(not samus.morphing and samus.elevator_pose)
	for i in range(800):
		await get_tree().physics_frame
		if current_id=="97B5" and not is_on_elevator(): break
	assert(current_id=="97B5" and not is_on_elevator(),"Return elevator must arrive at Crateria")
	assert(samus.controls_enabled and samus.position.distance_to(Vector2(128,136))<2)
	print("ELEVATOR_TEST_PROGRESS: returned to Crateria")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	# All fourteen endpoints: sprites, source parameters and destination linkage.
	set_playing(false)
	var endpoints := 0
	for entry in catalog:
		var parsed: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/extracted/rooms/%s.json"%entry.id))
		for spawn in parsed.states[0].enemies:
			if spawn.id!="D73F": continue
			load_room(entry.id)
			assert(elevators.size()==1)
			var lift: NativeElevator=elevators[0]
			assert(lift.home==Vector2(spawn.x,spawn.y) and lift.entry_y==float(spawn.parameter2))
			assert(lift.exit_door>=0)
			var exit: Dictionary=parsed.doors[lift.exit_door]
			var destination: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/extracted/rooms/%s.json"%exit.destination))
			var reciprocal := false
			for dest_spawn in destination.states[0].enemies:
				if dest_spawn.id=="D73F":
					assert(int(dest_spawn.x)==int(exit.screen_x)*256+128)
					assert(int(dest_spawn.parameter1)!=int(spawn.parameter1))
					for dest_door in destination.doors:
						if dest_door.get("kind","")=="elevator" and dest_door.destination==entry.id: reciprocal=true
			assert(reciprocal)
			# Advance the remaining links in deterministic native 60 Hz steps.
			# The first pair above uses real input and the engine's physics loop.
			samus.position=lift.position-Vector2(0,float(lift.definition.samus_offset_y))
			lift.active=true
			assert(lift.begin_departure())
			for tick in range(1600):
				if lift.phase==NativeElevator.Phase.WAITING: break
				lift._physics_process(1.0/60.0)
			assert(lift.phase==NativeElevator.Phase.WAITING,"Missing exit trigger in "+entry.id)
			await get_tree().process_frame
			await get_tree().process_frame
			assert(current_id==exit.destination,"Incorrect elevator destination from "+entry.id)
			var arriving: NativeElevator=elevators[0]
			assert(arriving.phase==NativeElevator.Phase.ENTERING)
			arriving.active=true
			for tick in range(1600):
				if not arriving.is_riding(): break
				arriving._physics_process(1.0/60.0)
			assert(not arriving.is_riding() and arriving.position==arriving.home)
			assert(samus.position==arriving.home-Vector2(0,float(arriving.definition.samus_offset_y)))
			arriving.active=false
			endpoints+=1
	assert(endpoints==14)
	print("ELEVATOR_OK: actual Crateria-Brinstar round trip, 90 px/s, 48-tick down delay, input direction, pause/control lock, save after arrival and 14 endpoint transits in deterministic native ticks")
	call_deferred("finish_test")

func capture_elevator() -> void:
	new_game()
	load_room("97B5",Vector2(128,136))
	for i in range(5): await get_tree().physics_frame
	set_playing(false)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://docs/qa/elevator_crateria.png")
	set_playing(true)
	elevators[0].begin_departure()
	var transit_captured := false
	for i in range(800):
		await get_tree().physics_frame
		if current_id=="9E9F" and is_on_elevator() and elevators[0].position.y>300 and not transit_captured:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://docs/qa/elevator_transit.png")
			transit_captured=true
		if current_id=="9E9F" and not is_on_elevator(): break
	assert(current_id=="9E9F" and not is_on_elevator() and transit_captured)
	set_playing(false)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://docs/qa/elevator_brinstar.png")
	print("ELEVATOR_CAPTURE_OK")
	call_deferred("finish_test")

func run_elevator_morph_test() -> void:
	new_game()
	samus.abilities["morph"]=true
	load_room("9E9F",Vector2(1408,680))
	for i in range(4): await get_tree().physics_frame
	samus.set_morph(true)
	for i in range(4): await get_tree().physics_frame
	assert(samus.morphing and elevators[0].can_depart())
	assert(samus.can_stand(),"Floor contact must permit unrolling on elevator at "+str(samus.position))
	var ceiling := StaticBody2D.new()
	ceiling.position=samus.position+Vector2(0,-25)
	ceiling.collision_layer=1
	var shape := RectangleShape2D.new()
	shape.size=Vector2(24,4)
	var ceiling_collision := CollisionShape2D.new()
	ceiling_collision.shape=shape
	ceiling.add_child(ceiling_collision)
	add_child(ceiling)
	for i in range(2): await get_tree().physics_frame
	assert(not samus.can_stand(),"Real ceiling must still prevent unrolling")
	samus.set_morph(false)
	assert(samus.morphing)
	remove_child(ceiling)
	ceiling.queue_free()
	for i in range(2): await get_tree().physics_frame
	assert(samus.can_stand())
	Input.action_press("up")
	for i in range(2): await get_tree().physics_frame
	Input.action_release("up")
	assert(is_on_elevator() and not samus.morphing and samus.elevator_pose)
	print("ELEVATOR_MORPH_OK: floor contact allows unrolling, real ceiling blocks it, and ball form can board")
	call_deferred("finish_test")
