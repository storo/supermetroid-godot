extends Control

var catalog: Array = []
var current_id := "91F8"
var discovered: Dictionary = {}
var area := 0
var exploration := false
signal selected(room_id: String)
const COLORS := [Color("71dfba"),Color("84b755"),Color("ec8352"),Color("b99ddd"),Color("62b9d4"),Color("e6c474"),Color("b3c7d3")]

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(750,470)

func _draw() -> void:
	var unit := 10.0
	var origin := Vector2(25,40)
	for room in catalog:
		if int(room.area)!=area: continue
		var rect := Rect2(origin+Vector2(room.map_x,room.map_y)*unit,Vector2(room.width/16.0,room.height/16.0)*unit)
		var known: bool = discovered.has(room.id) or exploration
		var color: Color = COLORS[clampi(area,0,6)]
		draw_rect(rect,Color(color,0.17 if known else 0.035))
		draw_rect(rect.grow(-1),Color(color,0.65 if known else 0.09),false,1)
		if room.id==current_id:
			draw_rect(rect.grow(2),Color("e5f8bd"),false,2)
			draw_circle(rect.get_center(),3,Color("edffd9"))

func _gui_input(event: InputEvent) -> void:
	if not exploration: return
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		for room in catalog:
			if int(room.area)!=area: continue
			var rect := Rect2(Vector2(25,40)+Vector2(room.map_x,room.map_y)*10,Vector2(room.width/16.0,room.height/16.0)*10)
			if rect.has_point(event.position):
				selected.emit(room.id)
				return
