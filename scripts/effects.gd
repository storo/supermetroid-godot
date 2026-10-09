extends Node2D

var projectiles: Array = []
var bursts: Array = []
var bombs: Array = []
var enemy_lasers: Array = []
var enhanced := true
var laser_original: Texture2D = preload("res://assets/extracted/objects/pirate_laser_original.png")
var laser_enhanced: Texture2D = preload("res://assets/extracted/objects/pirate_laser_enhanced.png")

func burst(p: Vector2, color: Color, count: int = 12) -> void:
	for i in range(count):
		var angle := randf()*TAU
		bursts.append({"p":p,"v":Vector2.from_angle(angle)*randf_range(20,110),"life":randf_range(0.16,0.6),"color":color})

func _process(delta: float) -> void:
	for i in range(bursts.size()-1,-1,-1):
		var b: Dictionary = bursts[i]
		b.p+=b.v*delta
		b.life-=delta
		b.v*=pow(0.1,delta)
		if b.life<=0: bursts.remove_at(i)
	queue_redraw()

func _draw() -> void:
	for laser in enemy_lasers:
		var tick := int(laser.ticks)
		var frame := 8+tick/2 if tick<6 else (tick-6 if tick<14 else 6+(tick&1))
		var tile_size := 256 if enhanced else 64
		if enhanced: draw_circle(laser.p,18,Color(1,0.4,0.55,0.06))
		draw_texture_rect_region(laser_enhanced if enhanced else laser_original,Rect2(laser.p-Vector2(32,32),Vector2(64,64)),Rect2(frame*tile_size,0,tile_size,tile_size))
	for bullet in projectiles:
		var color := Color(1,0.45,0.2) if bullet.missile else Color(0.45,1.0,0.55)
		var radius := 2.4 if bullet.missile else 1.3+float(bullet.charge)
		if enhanced:
			for i in range(3,0,-1): draw_circle(bullet.p,radius+i*2,Color(color,0.045))
		draw_line(bullet.p-bullet.dir*(10 if bullet.missile else 6),bullet.p,color,radius*1.5,true)
		draw_circle(bullet.p,radius,Color(1,1,0.7))
	for b in bursts: draw_circle(b.p,1.0,Color(b.color,minf(b.life*3,1.0)))
	for bomb in bombs:
		var pulse := 1.0+sin(bomb.time*20)*0.25
		draw_circle(bomb.p,3*pulse,Color(0.7,0.3,1.0))
		if enhanced: draw_circle(bomb.p,8,Color(0.5,0.2,1,0.08))
