class_name NativeRoom
extends Node2D

var data: Dictionary = {}
var state: Dictionary = {}
var width := 0
var height := 0
var enhanced := true
var atlas: Texture2D
var atlas_original: Texture2D
var atlas_enhanced: Texture2D
var collision_root: Node2D
var removed: Dictionary = {}
var opened_doors: Dictionary = {}
var door_caps: Array = []
var door_hits: Dictionary = {}
var exploration := false
var camera: Camera2D
var collision_rects := 0
var slope_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/extracted/slopes.json"))

func configure(room_id: String, state_index: int = 0) -> bool:
	var file := FileAccess.open("res://assets/extracted/rooms/%s.json"%room_id,FileAccess.READ)
	if file == null: return false
	data = JSON.parse_string(file.get_as_text())
	state = data.states[clampi(state_index,0,data.states.size()-1)]
	width = int(data.width)
	height = int(data.height)
	atlas_original = load("res://assets/extracted/tilesets/%02d_original.png"%int(state.tileset))
	atlas_enhanced = load("res://assets/extracted/tilesets/%02d_enhanced.png"%int(state.tileset))
	atlas = atlas_enhanced if enhanced else atlas_original
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	configure_door_caps()
	build_collision()
	return true

func configure_door_caps() -> void:
	for plm in state.plms:
		var code: int = str(plm.id).hex_to_int()
		if code<0xC842 or code>0xC8B4: continue
		var color := "blue"
		var group_start := 0xC8A2
		if code<0xC85A: color="grey";group_start=0xC842
		elif code<0xC872: color="yellow";group_start=0xC85A
		elif code<0xC88A: color="green";group_start=0xC872
		elif code<0xC8A2: color="red";group_start=0xC88A
		var direction := (code-group_start)/6
		var rect := Rect2(Vector2(plm.x,plm.y)*16,Vector2(16,64) if direction<2 else Vector2(64,16))
		var index := -1
		for y in range(maxi(0,int(plm.y)-1),mini(height,int(plm.y)+5)):
			for x in range(maxi(0,int(plm.x)-1),mini(width,int(plm.x)+5)):
				if block_at(Vector2i(x,y))>>12==9 and rect.grow(17).has_point(Vector2(x,y)*16+Vector2(8,8)):
					index=int(state.bts[y*width+x])&127
		if index>=0: door_caps.append({"rect":rect,"index":index,"color":color,"condition":(int(plm.argument)>>10)&31,"ready":false})

func unlock_door(cap: Dictionary, weapon: String) -> bool:
	var index: int=cap.index
	if opened_doors.has(index): return true
	var allowed: bool=exploration or cap.color=="blue"
	if cap.color=="red" and weapon in ["missile","super"]:
		door_hits[index]=int(door_hits.get(index,0))+1
		allowed=weapon=="super" or int(door_hits[index])>=5
	elif cap.color=="green": allowed=exploration or weapon=="super"
	elif cap.color=="yellow": allowed=exploration or weapon=="power_bomb"
	elif cap.color=="grey": allowed=exploration or bool(cap.get("ready",false))
	if not allowed: return false
	opened_doors[index]=true
	var rect: Rect2=cap.rect
	for y in range(int(rect.position.y/16),int(rect.end.y/16)):
		for x in range(int(rect.position.x/16),int(rect.end.x/16)):
			removed[y*width+x]=true
	call_deferred("build_collision")
	queue_redraw()
	return true

func set_enhanced(value: bool) -> void:
	enhanced = value
	atlas = atlas_enhanced if enhanced else atlas_original
	queue_redraw()

func block_at(cell: Vector2i) -> int:
	if cell.x<0 or cell.y<0 or cell.x>=width or cell.y>=height: return 0x8000
	var idx := cell.y*width+cell.x
	return 0 if removed.has(idx) else int(state.blocks[idx])

func resolve_type(cell: Vector2i, depth: int = 0) -> int:
	if depth>8: return 8
	var block := block_at(cell)
	var kind := block>>12
	if (kind==5 or kind==13) and cell.x>=0 and cell.y>=0 and cell.x<width and cell.y<height:
		var value := int(state.bts[cell.y*width+cell.x])
		if value==0: return 0
		if value>=128: value -= 256
		return resolve_type(cell+Vector2i(value,0) if kind==5 else cell+Vector2i(0,value),depth+1)
	return kind

func solid(cell: Vector2i) -> bool:
	var kind := resolve_type(cell)
	if kind==9 and door_is_open(cell): return false
	return kind in [8,9,10,11,12,14,15]

func door_is_open(cell: Vector2i) -> bool:
	if cell.x<0 or cell.y<0 or cell.x>=width or cell.y>=height: return false
	return opened_doors.has(int(state.bts[cell.y*width+cell.x])&127)

func build_collision() -> void:
	if collision_root:
		remove_child(collision_root)
		collision_root.queue_free()
	collision_root = Node2D.new()
	collision_root.name = "NativeCollisions"
	add_child(collision_root)
	collision_rects = 0
	for y in range(height):
		var x := 0
		while x<width:
			if solid(Vector2i(x,y)):
				var start := x
				while x<width and solid(Vector2i(x,y)): x+=1
				add_rectangle(Rect2(start*16,y*16,(x-start)*16,16))
			else:
				if resolve_type(Vector2i(x,y))==1: add_slope(Vector2i(x,y))
				x+=1
	# Room edges prevent leaving the world outside authored doors.
	add_rectangle(Rect2(-32,-32,32,height*16+64))
	add_rectangle(Rect2(width*16,-32,32,height*16+64))
	add_rectangle(Rect2(0,height*16,width*16,32))

func add_rectangle(rect: Rect2) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 2
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	var collision := CollisionShape2D.new()
	collision.shape = shape
	body.position = rect.get_center()
	body.add_child(collision)
	collision_root.add_child(body)
	collision_rects+=1

func add_slope(cell: Vector2i) -> void:
	var bts := int(state.bts[cell.y*width+cell.x])
	var shape_id := bts&31
	if shape_id<5:
		var quadrants: Array = slope_data.square[shape_id]
		for i in range(4):
			if int(quadrants[i])==0: continue
			var x := i%2
			var y := i/2
			if bts&0x40: x=1-x
			if bts&0x80: y=1-y
			add_rectangle(Rect2(Vector2(cell)*16+Vector2(x,y)*8,Vector2(8,8)))
		return
	var heights: Array = slope_data.heights[shape_id]
	var body := StaticBody2D.new()
	body.collision_layer=1
	body.collision_mask=2
	body.position=Vector2(cell)*16
	# Convex strips avoid degenerate concave polygons at empty slope endpoints.
	for x in range(16):
		var y0 := clampf(float(heights[x]),0,16)
		var y1 := clampf(float(heights[mini(x+1,15)]),0,16)
		if y0>=16 and y1>=16: continue
		var points := PackedVector2Array()
		for point in [Vector2(x,y0),Vector2(x+1,y1),Vector2(x+1,16),Vector2(x,16)]:
			if not points.has(point): points.append(point)
		if points.size()<3: continue
		for i in range(points.size()):
			if bts&0x40: points[i].x=16-points[i].x
			if bts&0x80: points[i].y=16-points[i].y
		var shape := ConvexPolygonShape2D.new()
		shape.points=points
		var collision := CollisionShape2D.new()
		collision.shape=shape
		body.add_child(collision)
	collision_root.add_child(body)

func point_solid(p: Vector2) -> bool:
	var cell := Vector2i(floor(p.x/16),floor(p.y/16))
	if solid(cell): return true
	if resolve_type(cell)!=1: return false
	var bts := int(state.bts[cell.y*width+cell.x])
	var local := Vector2i(fposmod(p.x,16),fposmod(p.y,16))
	if bts&0x40: local.x=15-local.x
	if bts&0x80: local.y=15-local.y
	var shape_id := bts&31
	if shape_id<5: return int(slope_data.square[shape_id][(local.y/8)*2+local.x/8])!=0
	return local.y>=int(slope_data.heights[shape_id][local.x])

func find_spawn(preferred: Vector2 = Vector2(-1,-1)) -> Vector2:
	if preferred.x>=0 and is_spawn_clear(preferred): return preferred
	var center := Vector2(width*8,height*8) if preferred.x<0 else preferred
	# Find an authored floor with sufficient room for standing Samus.
	var best := Vector2(width*8,40)
	var score := INF
	for y in range(3,height):
		for x in range(1,width-1):
			if solid(Vector2i(x,y)) and not solid(Vector2i(x,y-1)):
				var p := Vector2(x*16+8,y*16-21)
				if is_spawn_clear(p):
					var distance := p.distance_squared_to(center)
					if distance<score:
						score=distance
						best=p
	if score==INF:
		for y in range(2,height-1):
			for x in range(1,width-1):
				var p := Vector2(x*16+8,y*16+8)
				var distance := p.distance_squared_to(center)
				if distance<score and is_spawn_clear(p):
					score=distance
					best=p
	return best

func is_spawn_clear(p: Vector2) -> bool:
	for offset in [Vector2(-5,-19),Vector2(5,-19),Vector2(-5,19),Vector2(5,19)]:
		var c := Vector2i((p+offset)/16)
		if point_solid(p+offset): return false
	return true

func hit_block(p: Vector2, weapon: String) -> Dictionary:
	for cap in door_caps:
		if cap.rect.has_point(p) and not opened_doors.has(cap.index):
			var unlocked := unlock_door(cap,weapon)
			return {"stop":true,"door":cap.index,"unlocked":unlocked}
	var cell := Vector2i(floor(p.x/16),floor(p.y/16))
	if cell.x<0 or cell.y<0 or cell.x>=width or cell.y>=height: return {"stop":true}
	var idx := cell.y*width+cell.x
	var kind := resolve_type(cell)
	if kind==9:
		var door_idx := int(state.bts[idx])&127
		if door_idx<data.doors.size() and data.doors[door_idx].get("kind","") in ["elevator","elevator_trigger"]:
			return {"stop":true}
		for cap in door_caps:
			if int(cap.index)==door_idx and not unlock_door(cap,weapon): return {"stop":true}
		if not opened_doors.has(door_idx):
			opened_doors[door_idx] = true
			call_deferred("build_collision")
			queue_redraw()
		return {"stop":true,"door":door_idx}
	var can_break := (kind in [11,12] and weapon in ["beam","missile","charge","bomb"]) or (kind==15 and weapon=="bomb")
	if can_break:
		removed[idx] = true
		call_deferred("build_collision")
		queue_redraw()
		return {"stop":true,"broken":true}
	return {"stop":point_solid(p)}

func door_near(p: Vector2) -> int:
	for y in range(maxi(0,int(p.y/16)-2),mini(height,int(p.y/16)+3)):
		for x in range(maxi(0,int(p.x/16)-1),mini(width,int(p.x/16)+2)):
			var c := Vector2i(x,y)
			if resolve_type(c)==9 and door_is_open(c):
				var index := int(state.bts[y*width+x])&127
				if index<data.doors.size() and data.doors[index].get("kind","")=="normal": return index
	return -1

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if not atlas or not camera: return
	var viewport_size := get_viewport_rect().size/camera.zoom
	var center := camera.get_screen_center_position()
	var begin := Vector2i((center-viewport_size/2)/16)-Vector2i(2,2)
	var end := Vector2i((center+viewport_size/2)/16)+Vector2i(3,3)
	var tile_size := 64 if enhanced else 16
	for y in range(maxi(0,begin.y),mini(height,end.y)):
		for x in range(maxi(0,begin.x),mini(width,end.x)):
			var idx := y*width+x
			if removed.has(idx): continue
			var word := int(state.blocks[idx])
			if word>>12==9 and door_is_open(Vector2i(x,y)): continue
			var n := word&1023
			var rect := Rect2(x*16,y*16,16,16)
			if word&0x400:
				rect.position.x+=16
				rect.size.x=-16
			if word&0x800:
				rect.position.y+=16
				rect.size.y=-16
			draw_texture_rect_region(atlas,rect,Rect2((n%32)*tile_size,(n/32)*tile_size,tile_size,tile_size))
