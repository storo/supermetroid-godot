extends Control

var enhanced := true
var exterior := true
var camera_position := Vector2.ZERO
var time := 0.0
var background: Texture2D
var motes: Array = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	background = load("res://assets/remastered/crateria_backdrop.png")
	var rng := RandomNumberGenerator.new()
	rng.seed=92013
	for i in range(65): motes.append(Vector3(rng.randf(),rng.randf(),rng.randf_range(0.2,1.0)))

func _process(delta: float) -> void:
	time += delta
	queue_redraw()

func _draw() -> void:
	if not enhanced: return
	var viewport := get_viewport_rect().size
	if exterior and background:
		var offset := fmod(camera_position.x*0.12,viewport.x*0.2)
		draw_texture_rect(background,Rect2(-offset,-viewport.y*0.12,viewport.x*1.2,viewport.y*1.12),false,Color(0.65,0.75,0.82))
	else:
		draw_rect(Rect2(Vector2.ZERO,viewport),Color(0.025,0.045,0.065))
		for i in range(12):
			var x := i*viewport.x/10-fmod(camera_position.x*0.05,viewport.x/10)
			draw_line(Vector2(x,0),Vector2(x-50,viewport.y),Color(0.1,0.18,0.2,0.05),40,true)
	for i in range(motes.size()):
		var m: Vector3=motes[i]
		var p := Vector2(fposmod(m.x*viewport.x+sin(time*0.2+i)*20-camera_position.x*0.15,viewport.x),fposmod(m.y*viewport.y-time*5*m.z,viewport.y))
		var a := (0.12+sin(time+i)*0.06)*m.z
		draw_circle(p,4*m.z,Color(0.2,0.9,0.65,a*0.15))
		draw_circle(p,1.2*m.z,Color(0.3,1,0.7,a))
	if exterior:
		for i in range(80):
			var x := fposmod(i*79.0-time*90,viewport.x)
			var y := fposmod(i*117.0+time*450,viewport.y)
			draw_line(Vector2(x,y),Vector2(x-3,y+10),Color(0.4,0.7,0.85,0.075),1,true)
