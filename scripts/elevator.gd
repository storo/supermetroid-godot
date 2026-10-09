class_name NativeElevator
extends Node2D

# Native adaptation of $A3:94E6-962E, checked against snesrev/sm sm_a3.c.
# Copyright (c) 2023 snesrev, (c) 2021 elzo_d. MIT: docs/licenses/snesrev-sm.txt.
signal departed(door_index: int)
signal finished
signal started

enum Phase { IDLE, LEAVING, EXIT_DELAY, WAITING, ENTERING }
var phase := Phase.IDLE
var player: NativeSamus
var room: NativeRoom
var home := Vector2.ZERO
var entry_y := 0.0
var direction := 1
var active := true
var enhanced := true
var animation_ticks := 0
var delay_ticks := 0
var exit_door := -1
var sprite: Sprite2D
var definition: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/extracted/objects/elevator.json"))

func configure(spawn: Dictionary, target: NativeSamus, native_room: NativeRoom) -> void:
	position=Vector2(spawn.x,spawn.y)
	home=position
	entry_y=float(spawn.parameter2)
	direction=-1 if int(spawn.parameter1)!=0 else 1
	player=target
	room=native_room
	for door in room.data.doors:
		if door.get("kind","")=="elevator": exit_door=int(door.index)

func _ready() -> void:
	z_index=8
	var body := StaticBody2D.new()
	body.collision_layer=1
	body.collision_mask=0
	var shape := RectangleShape2D.new()
	shape.size=Vector2(32,8)
	var collision := CollisionShape2D.new()
	collision.shape=shape
	collision.position=Vector2(0,-2)
	body.add_child(collision)
	add_child(body)
	sprite=Sprite2D.new()
	sprite.hframes=2
	sprite.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(sprite)
	set_enhanced(enhanced)

func set_enhanced(value: bool) -> void:
	enhanced=value
	if not sprite: return
	sprite.texture=load("res://assets/extracted/objects/elevator_%s.png"%("enhanced" if value else "original"))
	sprite.scale=Vector2.ONE*(0.25 if value else 1.0)
	sprite.material=load("res://assets/remastered/sprite_lighting.tres") if value else null

func is_riding() -> bool:
	return phase!=Phase.IDLE

func can_depart() -> bool:
	var half_height := 7 if player.morphing else (12 if player.crouching else 20)
	return phase==Phase.IDLE and exit_door>=0 and absf(player.position.x-position.x)<=16 and absf(player.position.y+half_height-(position.y-6))<=8

func begin_departure() -> bool:
	if not can_depart(): return false
	if player.morphing:
		player.set_morph(false)
		if player.morphing: return false
	player.crouching=false
	player.collider.shape=player.stand_shape
	phase=Phase.LEAVING
	attach_player()
	started.emit()
	return true

func begin_arrival() -> void:
	position.y=entry_y
	phase=Phase.ENTERING
	attach_player()

func attach_player() -> void:
	player.set_elevator_pose(true)
	player.controls_enabled=false
	player.position=position-Vector2(0,float(definition.samus_offset_y))
	player.velocity=Vector2.ZERO

func _physics_process(delta: float) -> void:
	if not active: return
	animation_ticks+=1
	sprite.frame=(animation_ticks/int(definition.frame_ticks))%2
	if phase==Phase.IDLE or phase==Phase.WAITING: return
	if phase==Phase.ENTERING:
		position.y=move_toward(position.y,home.y,float(definition.speed)*delta)
		attach_player()
		if is_equal_approx(position.y,home.y):
			phase=Phase.IDLE
			player.set_elevator_pose(false)
			finished.emit()
		return
	position.y+=direction*float(definition.speed)*delta
	attach_player()
	if phase==Phase.EXIT_DELAY:
		delay_ticks-=1
		if delay_ticks<=0: request_transition()
		return
	var leading_edge := player.position+Vector2(0,direction*20)
	for offset_x in [-5,5]:
		var cell := Vector2i(floor((leading_edge.x+offset_x)/16),floor(leading_edge.y/16))
		if cell.x<0 or cell.y<0 or cell.x>=room.width or cell.y>=room.height: continue
		var index := cell.y*room.width+cell.x
		if int(room.state.blocks[index])>>12==9 and (int(room.state.bts[index])&127)==exit_door:
			if direction>0:
				phase=Phase.EXIT_DELAY
				delay_ticks=int(definition.down_transition_delay_ticks)
			else: request_transition()
			return

func request_transition() -> void:
	phase=Phase.WAITING
	departed.emit(exit_door)
