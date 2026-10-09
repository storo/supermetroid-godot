class_name NativeSamus
extends CharacterBody2D

signal fired(origin: Vector2, direction: Vector2, missile: bool, charge: float)
signal bomb_dropped(origin: Vector2)
signal injured

var facing := 1.0
var health := 99
var max_health := 99
var missiles := 0
var max_missiles := 0
var abilities: Dictionary = {}
var enhanced := true
var morphing := false
var crouching := false
var elevator_pose := false
var controls_enabled := true
var invulnerability := 0.0
var fire_cooldown := 0.0
var charge_time := 0.0
var coyote := 0.0
var jump_buffer := 0.0
var animation_time := 0.0
var spin_jump := false
var previous_position := Vector2.ZERO
var collider: CollisionShape2D
var sprite: Sprite2D
var animations: Dictionary = {}
var frame_counts := {"idle":4,"run":10,"jump":3,"spin":8,"crouch":3,"morph":8,"aim_up":2,"aim_diagonal":1,"fall":3,"front":1}
var current_animation := ""
var physics: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/extracted/physics.json"))
var dash_speed := 0.0
var stand_shape := RectangleShape2D.new()
var crouch_shape := RectangleShape2D.new()
var ball_shape := CircleShape2D.new()

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 5.0
	floor_max_angle = deg_to_rad(55)
	stand_shape.size = Vector2(12,40)
	crouch_shape.size = Vector2(12,24)
	ball_shape.radius = 7.0
	collider = CollisionShape2D.new()
	collider.shape = stand_shape
	add_child(collider)
	sprite = Sprite2D.new()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(sprite)
	for animation in frame_counts:
		for suffix in ([""] if animation=="front" else ["","_left"]):
			var name: String=animation+suffix
			animations[name] = {
				"original":load("res://assets/extracted/samus/%s_original.png"%name),
				"enhanced":load("res://assets/extracted/samus/%s_enhanced.png"%name)}
	update_animation("idle",0)

func set_enhanced(value: bool) -> void:
	var base := current_animation.trim_suffix("_left")
	var frame_index := sprite.frame if sprite else 0
	enhanced = value
	current_animation = ""
	if animations.has(base): update_animation(base,frame_index)

func set_elevator_pose(value: bool) -> void:
	if elevator_pose==value: return
	elevator_pose=value
	update_animation("front" if value else "idle",0)
	sprite.position=Vector2(0,-5)

func set_morph(value: bool) -> void:
	if value and not abilities.get("morph",false): return
	if not value and not can_stand(): return
	var was_floor := is_on_floor()
	if value != morphing:
		position.y += 13 if value else -13
	morphing = value
	crouching = false
	collider.shape = ball_shape if morphing else stand_shape
	if was_floor: apply_floor_snap()

func can_stand() -> bool:
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = stand_shape
	# A floor contact within CharacterBody's skin must not block unrolling.
	query.transform = Transform2D(0,position-Vector2(0,(13 if morphing else 0)+safe_margin*2))
	query.collision_mask = 1
	query.exclude = [get_rid()]
	return get_world_2d().direct_space_state.intersect_shape(query,1).is_empty()

func _physics_process(delta: float) -> void:
	invulnerability = maxf(0, invulnerability-delta)
	fire_cooldown = maxf(0,fire_cooldown-delta)
	sprite.modulate.a = 0.4 if invulnerability>0 and int(invulnerability*14)%2==0 else 1.0
	if not controls_enabled:
		velocity = Vector2.ZERO
		return
	animation_time += delta
	var axis := Input.get_axis("left","right")
	var grounded := is_on_floor()
	coyote = 0.1 if grounded else maxf(0,coyote-delta)
	jump_buffer = 0.1 if Input.is_action_just_pressed("jump") else maxf(0,jump_buffer-delta)
	if Input.is_action_just_pressed("morph"): set_morph(not morphing)
	if morphing and Input.is_action_just_pressed("up"): set_morph(false)
	if grounded and not morphing:
		var want_crouch := Input.is_action_pressed("down") and absf(axis)<0.1
		if want_crouch != crouching and (want_crouch or can_stand()):
			position.y += 8 if want_crouch else -8
			crouching = want_crouch
			collider.shape = crouch_shape if crouching else stand_shape
	var movement_name := "morph" if morphing else ("run" if grounded else ("spin" if spin_jump else "jump"))
	var movement: Dictionary = physics.movement[movement_name]
	if grounded and Input.is_action_pressed("run") and absf(axis)>0.1 and not morphing:
		var dash_max: float = physics.speed_extra_max if abilities.get("speed",false) else physics.dash_extra_max
		dash_speed = move_toward(dash_speed,dash_max,float(physics.dash_acceleration)*delta)
	elif grounded:
		dash_speed = move_toward(dash_speed,0,1800*delta)
	var top_speed: float = movement.max_speed+dash_speed
	if not grounded and axis*facing>0: top_speed=maxf(top_speed,absf(velocity.x))
	if crouching: axis=0
	if absf(axis)>0.1: facing=signf(axis)
	var acceleration: float = movement.acceleration if absf(axis)>0.1 else movement.deceleration
	velocity.x=move_toward(velocity.x,axis*top_speed,acceleration*delta)
	if not grounded: velocity.y=minf(velocity.y+float(physics.gravity_air)*delta,480.0)
	else:
		spin_jump=false
		if velocity.y>0: velocity.y=0
	if jump_buffer>0:
		if coyote>0 and (not morphing or abilities.get("spring",false)):
			velocity.y = -float(physics.jump_hi if abilities.get("hi_jump",false) else physics.jump_air)
			jump_buffer = 0
			coyote = 0
			spin_jump = absf(axis)>0.2 and not morphing
		elif is_on_wall() and not morphing and not grounded:
			var normal := get_wall_normal()
			if axis*normal.x>0:
				velocity = Vector2(normal.x*185,-float(physics.jump_wall))
				facing = normal.x
				jump_buffer = 0
				spin_jump = true
		elif abilities.get("space_jump",false) and velocity.y>20 and not morphing:
			velocity.y = -float(physics.jump_air)
			jump_buffer = 0
			spin_jump = true
	if Input.is_action_just_released("jump") and velocity.y < -150:
		velocity.y = -150
	if Input.is_action_pressed("fire") and abilities.get("charge",false): charge_time += delta
	if Input.is_action_just_released("fire") and charge_time>0.6:
		shoot(false,minf(charge_time,1.5))
		charge_time = 0
	elif not Input.is_action_pressed("fire"): charge_time = 0
	if not morphing and fire_cooldown<=0:
		if Input.is_action_pressed("missile") and missiles>0:
			missiles -= 1
			shoot(true)
		elif Input.is_action_pressed("fire") and charge_time<0.6: shoot(false)
	if morphing and Input.is_action_just_pressed("bomb") and abilities.get("bombs",false):
		bomb_dropped.emit(position+Vector2(0,4))
	previous_position = position
	move_and_slide()
	animate(axis,grounded)
	queue_redraw()

func aim_direction() -> Vector2:
	if Input.is_action_pressed("up") and absf(velocity.x)<5: return Vector2.UP
	if Input.is_action_pressed("aim_up") or Input.is_action_pressed("up"): return Vector2(facing,-1).normalized()
	if Input.is_action_pressed("aim_down"): return Vector2(facing,1).normalized()
	return Vector2(facing,0)

func shoot(is_missile: bool, charge: float = 0) -> void:
	var dir := aim_direction()
	var muzzle := position+Vector2(facing*12,-5 if not crouching else -3)+dir*8
	fired.emit(muzzle,dir,is_missile,charge)
	fire_cooldown = 0.3 if is_missile else 0.13

func animate(axis: float, grounded: bool) -> void:
	var animation := "idle"
	var speed := 5.0
	if morphing:
		animation = "morph"
		speed = absf(velocity.x)/16.0
	elif crouching: animation = "crouch"
	elif not grounded:
		animation = "spin" if spin_jump and not Input.is_action_pressed("fire") else ("jump" if velocity.y<0 else "fall")
		speed = 14 if spin_jump else 5
	elif absf(axis)>0.1:
		animation = "run"
		speed = absf(velocity.x)/14.0
	elif aim_direction()==Vector2.UP: animation = "aim_up"
	elif aim_direction().y<0: animation = "aim_diagonal"
	update_animation(animation,int(animation_time*speed)%int(frame_counts[animation]))
	sprite.flip_h = false
	# OAM coordinates are centered on the original Samus anchor; morph uses a lower anchor.
	sprite.position = Vector2(0,-13 if morphing else -5)

func update_animation(animation: String, frame_index: int) -> void:
	var direction_name := animation+("_left" if facing<0 and animation!="front" else "")
	if current_animation != direction_name:
		current_animation = direction_name
		sprite.texture = animations[direction_name]["enhanced" if enhanced else "original"]
		sprite.material = load("res://assets/remastered/sprite_lighting.tres") if enhanced else null
		sprite.hframes = frame_counts[animation]
		sprite.scale = Vector2.ONE*(0.25 if enhanced else 1.0)
	sprite.frame = frame_index

func damage(amount: int, source: Vector2) -> void:
	if invulnerability>0: return
	health = maxi(0,health-amount)
	invulnerability = 1.2
	velocity = Vector2(signf(position.x-source.x)*130,-170)
	injured.emit()

func _draw() -> void:
	if enhanced:
		var p := Vector2(facing*2,-13)
		for i in range(3,0,-1): draw_circle(p,3.0+i*2,Color(0.1,1.0,0.5,0.016))
		if charge_time>0.5:
			draw_circle(Vector2(facing*14,-5),3.5+sin(animation_time*40),Color(0.4,1,0.7,0.6))
