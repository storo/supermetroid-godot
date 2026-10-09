extends Node2D
class_name NativeCoreRenderer

const SHADER = preload("res://shaders/native_tiles.gdshader")
const MODE7_SHADER = preload("res://shaders/native_mode7.gdshader")
const DEPTHS := [[2,2,2,2],[4,4,2,0],[4,4,0,0],[8,4,0,0],[8,2,0,0],[4,2,0,0],[4,0,0,0],[0,0,0,0]]
const SIZES := [[8,16],[8,32],[8,64],[16,32],[16,64],[32,64],[16,32],[16,32]]
var enhanced := true
var batches: Array[MultiMeshInstance2D] = []
var vram_texture: ImageTexture
var palette_texture: ImageTexture
var previous_palette := PackedByteArray()
var draw_counts := PackedInt32Array()
var unsupported_mode := -1
var mode7_nodes: Array[MeshInstance2D] = []
var sprite_batches := [1,3,6,9]
var background_batches := [[5,8],[4,7],[0,2],[0,0]]

func _ready() -> void:
	vram_texture = ImageTexture.create_from_image(Image.create(256,256,false,Image.FORMAT_R8))
	palette_texture = ImageTexture.create_from_image(Image.create(256,1,false,Image.FORMAT_RGB8))
	draw_counts.resize(12)
	for index in range(12):
		var node := MultiMeshInstance2D.new()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_2D
		mm.use_custom_data = true
		var quad := QuadMesh.new()
		quad.size = Vector2(8,8)
		mm.mesh = quad
		mm.instance_count = 2400
		mm.visible_instance_count = 0
		node.multimesh = mm
		var material := ShaderMaterial.new()
		material.shader = SHADER
		material.set_shader_parameter("vram_tex",vram_texture)
		material.set_shader_parameter("palette_tex",palette_texture)
		node.material = material
		node.z_index = index
		add_child(node)
		batches.append(node)
	for index in range(3):
		var node := MeshInstance2D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(256,224)
		node.mesh = quad
		node.position = Vector2(128,112)
		node.z_index = [2,0,4][index]
		var material := ShaderMaterial.new()
		material.shader = MODE7_SHADER
		material.set_shader_parameter("vram_tex",vram_texture)
		material.set_shader_parameter("palette_tex",palette_texture)
		material.set_shader_parameter("layer",0 if index==0 else 1)
		material.set_shader_parameter("priority",1 if index==2 else 0)
		node.material = material
		add_child(node)
		mode7_nodes.append(node)

func present(snapshot: Dictionary) -> void:
	if snapshot.is_empty():
		visible = false
		return
	visible = not snapshot.forced_blank
	var data: PackedByteArray = snapshot.vram
	vram_texture.update(Image.create_from_data(256,256,false,Image.FORMAT_R8,data))
	var palette: PackedByteArray = snapshot.palette
	if palette != previous_palette:
		var rgb := PackedByteArray()
		rgb.resize(768)
		for i in range(256):
			var value := palette.decode_u16(i*2)
			rgb[i*3] = int(round((value & 31)*255.0/31.0))
			rgb[i*3+1] = int(round(((value>>5)&31)*255.0/31.0))
			rgb[i*3+2] = int(round(((value>>10)&31)*255.0/31.0))
		palette_texture.update(Image.create_from_data(256,1,false,Image.FORMAT_RGB8,rgb))
		previous_palette = palette
	draw_counts.fill(0)
	var mode: int = snapshot.mode
	unsupported_mode = mode if mode in [5,6] else -1
	for node in mode7_nodes: node.visible = false
	sprite_batches = [1,3,6,9]
	background_batches = [[5,8],[4,7],[0,2],[0,0]]
	if mode == 0:
		sprite_batches = [2,5,8,11]
		background_batches = [[7,10],[6,9],[1,4],[0,3]]
	elif mode in [2,3,4]:
		sprite_batches = [1,3,5,7]
		background_batches = [[2,6],[0,4],[0,0],[0,0]]
	elif mode == 1 and snapshot.bg3priority:
		background_batches = [[4,7],[3,6],[0,9],[0,0]]
		sprite_batches = [1,2,5,8]
	elif mode == 7:
		sprite_batches = [1,3,5,6]
		var matrix: Array = snapshot.mode7
		var transform := Vector4(matrix[0],matrix[1],matrix[2],matrix[3])
		var center_scroll := Vector4(matrix[4],matrix[5],matrix[6],matrix[7])
		for index in range(3):
			var node := mode7_nodes[index]
			node.visible = snapshot.backgrounds[0 if index==0 else 1].enabled and (index==0 or (snapshot.mode7_flags&16)!=0)
			node.material.set_shader_parameter("matrix",transform)
			node.material.set_shader_parameter("center_scroll",center_scroll)
			node.material.set_shader_parameter("flags",snapshot.mode7_flags)
			node.material.set_shader_parameter("brightness",float(snapshot.brightness)/15.0)
			node.material.set_shader_parameter("enhanced",enhanced)
	if unsupported_mode < 0:
		for layer in range(4):
			if snapshot.backgrounds[layer].enabled and DEPTHS[mode][layer] > 0:
				background(snapshot.backgrounds[layer],layer,mode,data)
	if snapshot.obj_enabled: sprites(snapshot)
	for i in range(12):
		batches[i].multimesh.visible_instance_count = draw_counts[i]
		batches[i].material.set_shader_parameter("brightness",float(snapshot.brightness)/15.0)
		batches[i].material.set_shader_parameter("enhanced",enhanced)

func tile(batch: int, position: Vector2, address: int, palette: int, depth: int, flip: int) -> void:
	var index := draw_counts[batch]
	if index >= batches[batch].multimesh.instance_count:
		return
	var mm := batches[batch].multimesh
	mm.set_instance_transform_2d(index,Transform2D(0,position+Vector2(4,4)))
	mm.set_instance_custom_data(index,Color(address & 65535,palette,depth,flip))
	draw_counts[batch] += 1

func background(bg: Dictionary, layer: int, mode: int, data: PackedByteArray) -> void:
	var depth: int = DEPTHS[mode][layer]
	var scroll: Vector2i = Vector2i(bg.scroll)
	var cell_size := 16 if bg.big else 8
	for row in range(29):
		for column in range(33):
			var x := (scroll.x & ~7) + column*8
			var y := (scroll.y & ~7) + row*8
			var tx := int(x/cell_size)
			var ty := int(y/cell_size)
			var map_address: int = bg.map + (ty & 31)*32 + (tx & 31)
			if bg.wide and tx & 32:
				map_address += 0x400
			if bg.high and ty & 32:
				map_address += 0x800 if bg.wide else 0x400
			var word := data.decode_u16((map_address & 0x7fff)*2)
			var number := word & 0x3ff
			var flip := ((word>>14)&1)|(((word>>15)&1)<<1)
			if bg.big:
				if bool(x & 8) != bool(word & 0x4000): number += 1
				if bool(y & 8) != bool(word & 0x8000): number += 16
			var palette := (word>>10)&7
			if mode == 0: palette += layer*8
			var priority := 1 if word & 0x2000 else 0
			var batch: int = background_batches[layer][priority]
			var address: int = bg.tiles*2 + (number & 0x3ff)*depth*8
			tile(batch,Vector2(column*8-(scroll.x&7),row*8-(scroll.y&7)),address,palette*(1<<depth) if depth<8 else 0,depth,flip)

func sprites(snapshot: Dictionary) -> void:
	var oam: PackedByteArray = snapshot.oam
	var sizes: Array = SIZES[snapshot.obj_size]
	# Earlier OAM entries win overlaps; add them last inside each priority batch.
	for index in range(127,-1,-1):
		var high: int = (oam[512+int(index/4)] >> ((index&3)*2))&3
		var x: int = oam[index*4] | ((high&1)<<8)
		if x >= 256: x -= 512
		var y: int = oam[index*4+1]
		var size: int = sizes[(high>>1)&1]
		if y >= 224 and y < 256-size: continue
		if y >= 256-size: y -= 256
		if x <= -size or x >= 256: continue
		var number: int = oam[index*4+2]
		var attr: int = oam[index*4+3]
		var base: int = snapshot.obj_base2 if attr&1 else snapshot.obj_base1
		var palette := 128+((attr>>1)&7)*16
		var flip := (attr>>6)&3
		var batch: int = sprite_batches[(attr>>4)&3]
		for row in range(int(size/8)):
			for column in range(int(size/8)):
				var sx := int(size/8)-1-column if flip&1 else column
				var sy := int(size/8)-1-row if flip&2 else row
				var used := (((number>>4)+sy)<<4) | (((number&15)+sx)&15)
				tile(batch,Vector2(x+column*8,y+row*8),(base+used*16)*2,palette,4,flip)
