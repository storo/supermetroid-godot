class_name NativePirate
extends NativeEnemy

# Native adaptation of bank $B2 routines, checked against snesrev/sm sm_b2.c.
# Copyright (c) 2023 snesrev, (c) 2021 elzo_d. MIT: docs/licenses/snesrev-sm.txt.

signal laser_fired(origin: Vector2, direction: int, damage: int, speed: int)

var script_data: Dictionary = {}
var parameter1 := 0
var parameter2 := 0
var instruction := 0
var instruction_ticks := 1
var loop_timer := 0
var ai_function := 0x804B
var wall_direction := 0
var jump_angle := 0
var jump_center := Vector2.ZERO
var jump_end_right := 190
var jump_end_left := 66
var jump_angle_step := 2
var player_projectiles: Array = []
var sequence_fault := false
var lasers_emitted := 0
var ai_ticks := 0
var all_scripts: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/extracted/objects/pirate_scripts.json"))

func configure(info: Dictionary, spawn: Dictionary, target: NativeSamus) -> void:
	super.configure(info,spawn,target)
	parameter1 = int(spawn.parameter1)
	parameter2 = int(spawn.parameter2)
	script_data = all_scripts[str(record.animation)]
	if record.animation=="pirate_walking":
		instruction = 0xFBE6 if parameter1&1 else 0xFB64
	else:
		instruction = 0xEDAC if parameter1&1 else 0xED36
		ai_function = 0xF0C8 if parameter1&1 else 0xF034
		if not parameter1&0x8000:
			jump_end_right=192
			jump_end_left=64
			jump_angle_step=4
		position.x = snapped_wall_x(int(position.x))
		origin=position

func _ready() -> void:
	super._ready()
	advance_instructions()

func set_instruction(address: int) -> void:
	instruction=address
	instruction_ticks=1

func snapped_wall_x(x: int) -> int:
	return (x&0xFFF8) if (x&15)<11 else (x&0xFFF0)+16

func _physics_process(delta: float) -> void:
	if not active or sequence_fault or is_queued_for_deletion(): return
	frozen=maxf(0,frozen-delta)
	if frozen>0:
		sprite.modulate=Color(0.4,0.8,1.0)
		return
	sprite.modulate=Color.WHITE
	ai_ticks+=1
	# Game ticks are 60 Hz; instruction times and movement retain ROM units.
	run_ai()
	if record.animation=="pirate_walking" and parameter1&0x8000:
		for bullet in player_projectiles:
			var p: Vector2=bullet.p
			if absf(p.x-position.x)<32 and absf(p.y-position.y)<32:
				set_instruction(0xFB58 if position.x<player.position.x else 0xFB4C)
				break
	instruction_ticks-=1
	if instruction_ticks<=0: advance_instructions()
	var player_box := Rect2(player.position-Vector2(6,7 if player.morphing else (12 if player.crouching else 20)),Vector2(12,14 if player.morphing else (24 if player.crouching else 40)))
	for bounds in current_hitboxes():
		if bounds.intersects(player_box):
			player.damage(damage_amount,position)
			break

func run_ai() -> void:
	match ai_function:
		0xFD44,0xFDCE:
			if absf(player.position.y-position.y)<16:
				set_instruction(0xFC0E if player.position.x>=position.x else 0xFB8C)
			else:
				var ground := move_and_collide(Vector2(0,1))
				if ground:
					var left := ai_function==0xFD44
					var ahead := transform.translated(Vector2(-17 if left else 16,0))
					var has_floor := test_move(ahead,Vector2(0,1))
					var collided := false
					if has_floor:
						collided = move_and_collide(Vector2(-14337.0/65536.0 if left else 14336.0/65536.0,0)) != null
					if not has_floor or collided or (position.x<origin.x-parameter2 if left else position.x>=origin.x+parameter2):
						set_instruction(0xFBC6 if left else 0xFC48)
		0xF034:
			if absf(player.position.y-position.y)<32: set_instruction(0xED80)
		0xF0C8:
			if absf(player.position.y-position.y)<32: set_instruction(0xECC0)
		0xF050,0xF0E4:
			position.x=jump_center.x+sine_multiply(jump_angle,parameter2>>1)
			position.y=jump_center.y-sine_multiply((jump_angle+192)&255,parameter2>>2)
			jump_angle=(jump_angle+(-jump_angle_step if ai_function==0xF050 else jump_angle_step))&255
			if jump_angle==(jump_end_right if ai_function==0xF050 else jump_end_left):
				position.x=snapped_wall_x(int(position.x))
				set_instruction(0xEDA4 if ai_function==0xF050 else 0xECE4)

func sine_multiply(angle: int, amplitude: int) -> int:
	var index := (angle+128)&255
	var magnitude := (int(all_scripts.sine_8bit[index&127])*(amplitude&255))>>8
	return -magnitude if index&128 else magnitude

func fire_laser(dir: int, offset_y: int) -> void:
	lasers_emitted+=1
	laser_fired.emit(position+Vector2(dir*24,-offset_y),dir,damage_amount,120 if parameter1&0x8000 else 240)

func advance_instructions() -> void:
	for _step in range(64):
		if not script_data.nodes.has(str(instruction)):
			sequence_fault=true
			push_error("Missing pirate instruction %04X in %s"%[instruction,record.animation])
			return
		var node: Dictionary=script_data.nodes[str(instruction)]
		var arg := int(node.get("argument",0))
		var address := instruction
		instruction=int(node.next)
		match str(node.op):
			"frame":
				sprite.frame=int(node.frame)
				instruction_ticks=int(node.ticks)
				return
			"function": ai_function=arg
			"goto": instruction=arg
			"timer": loop_timer=arg
			"loop":
				loop_timer-=1
				if loop_timer>0: instruction=arg
			"sleep":
				instruction=address
				instruction_ticks=1
				return
			"wait":
				instruction_ticks=arg
				return
			"laser_left": fire_laser(-1,signed_word(arg) if node.has("argument") else 16)
			"laser_right": fire_laser(1,signed_word(arg) if node.has("argument") else 16)
			"choose_walk":
				if absf(player.position.y-position.y)<16:
					instruction=0xFC0E if player.position.x>=position.x else 0xFB8C
				else: instruction=0xFB64 if player.position.x>=position.x else 0xFBE6
			"prepare_left","prepare_right":
				var dir := -1 if node.op=="prepare_left" else 1
				jump_center=position+Vector2(dir*(parameter2>>1),0)
				jump_angle=192 if dir<0 else 64
			"choose_wall_left","choose_wall_right":
				wall_direction=randi()&1
				if node.op=="choose_wall_left": instruction=0xECEC if wall_direction else 0xED36
				else: instruction=0xEDF6 if wall_direction else 0xEDAC
			"move_wall_left","move_wall_right":
				if move_and_collide(Vector2(0,signed_word(arg))):
					wall_direction^=1
					if node.op=="move_wall_left": instruction=0xECEC if wall_direction else 0xED36
					else: instruction=0xEDF6 if wall_direction else 0xEDAC
			"sound": pass # Original SPC sound playback is still pending.
	sequence_fault=true
	push_error("Pirate instruction loop exceeded guard")

func signed_word(value: int) -> int:
	return value-65536 if value&0x8000 else value

func current_hitboxes() -> Array[Rect2]:
	var boxes: Array[Rect2]=[]
	for b in script_data.hitboxes[sprite.frame]:
		boxes.append(Rect2(position+Vector2(b[0],b[1]),Vector2(int(b[2])-int(b[0])+1,int(b[3])-int(b[1])+1)))
	return boxes

func contains_hit(p: Vector2) -> bool:
	for bounds in current_hitboxes():
		if bounds.grow(2).has_point(p): return true
	return false
