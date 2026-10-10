extends Node2D
class_name NativeRasterRenderer

const SPRITE_SHADER = preload("res://shaders/raster_sprite.gdshader")
const LAYER_SHADER = preload("res://shaders/raster_layers.gdshader")
const COMPOSITE_SHADER = preload("res://shaders/raster_composite.gdshader")
const CRATERIA_BACKDROP = preload("res://assets/remastered/crateria_backdrop.png")
const CERES_WALL = preload("res://assets/remastered/ceres_bg2_wall.png")
const GREEN_BG2_TILES = preload("res://assets/remastered/green_bg2_tiles.png")
const CERES_WALL_STATES := {
	0xdf8d:[0xdf9f,0xdfb9],
	0xdfd7:[0xdfe9,0xe003],
	0xe06b:[0xe07d,0xe097],
}
var enhanced := true
var remastered_backgrounds := true
var vram_texture: ImageTexture
var raster_texture: ImageTexture
var sprite_view: SubViewport
var main_view: SubViewport
var sub_view: SubViewport
var sprites: MultiMesh
var composite: ShaderMaterial
var sprite_count := 0

func viewport_pass() -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(256,224)
	viewport.disable_3d = true
	viewport.transparent_bg = true
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(viewport)
	return viewport

func material_for(shader: Shader) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("vram_tex",vram_texture)
	material.set_shader_parameter("raster_tex",raster_texture)
	return material

func rectangle(size: Vector2) -> ArrayMesh:
	# Define UVs in canvas coordinates: the top left is (0,0).
	# QuadMesh's 3D Y axis reverses these when used in a 2D canvas.
	var half := size/2.0
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(-half.x,-half.y,0),Vector3(half.x,-half.y,0),
		Vector3(half.x,half.y,0),Vector3(-half.x,half.y,0)])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0,1,2,0,2,3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh

func quad(parent: Node, material: ShaderMaterial, rank: int = 0) -> MeshInstance2D:
	var node := MeshInstance2D.new()
	node.mesh = rectangle(Vector2(256,224))
	node.position = Vector2(128,112)
	node.z_index = rank
	node.material = material
	parent.add_child(node)
	return node

func _ready() -> void:
	vram_texture = ImageTexture.create_from_image(Image.create(256,256,false,Image.FORMAT_R8))
	raster_texture = ImageTexture.create_from_image(Image.create(1024,256,false,Image.FORMAT_R8))
	sprite_view = viewport_pass()
	var sprite_node := MultiMeshInstance2D.new()
	sprites = MultiMesh.new()
	sprites.transform_format = MultiMesh.TRANSFORM_2D
	sprites.use_custom_data = true
	sprites.mesh = rectangle(Vector2(64,64))
	sprites.instance_count = 256
	sprites.visible_instance_count = 0
	sprite_node.multimesh = sprites
	sprite_node.material = material_for(SPRITE_SHADER)
	sprite_view.add_child(sprite_node)
	main_view = viewport_pass()
	sub_view = viewport_pass()
	for view in [main_view,sub_view]:
		var material := material_for(LAYER_SHADER)
		material.set_shader_parameter("sprites_tex",sprite_view.get_texture())
		material.set_shader_parameter("subscreen",view == sub_view)
		quad(view,material)
	composite = material_for(COMPOSITE_SHADER)
	composite.set_shader_parameter("main_tex",main_view.get_texture())
	composite.set_shader_parameter("sub_tex",sub_view.get_texture())
	composite.set_shader_parameter("backdrop_tex",CRATERIA_BACKDROP)
	composite.set_shader_parameter("ceres_wall_tex",CERES_WALL)
	composite.set_shader_parameter("green_bg2_tiles_tex",GREEN_BG2_TILES)
	quad(self,composite)

func present(snapshot: Dictionary) -> void:
	if snapshot.is_empty():
		visible = false
		return
	visible = true
	var vram: PackedByteArray = snapshot.vram
	var raster: PackedByteArray = snapshot.raster
	assert(vram.size() == 65536 and raster.size() == 262144)
	vram_texture.update(Image.create_from_data(256,256,false,Image.FORMAT_R8,vram))
	raster_texture.update(Image.create_from_data(1024,256,false,Image.FORMAT_R8,raster))
	composite.set_shader_parameter("enhanced",enhanced)
	# Select art by the native room and gameplay state, never by palette alone.
	# Ceres' three matching rooms share the original StatueHall BG2 library.
	# Green Brinstar uses its native BG2 tile atlas and map. Other libraries,
	# Mode 7, menus and transitions keep their own art.
	var room: int=snapshot.get("room",0)
	var kind := 1 if room==0x91f8 else 0
	if CERES_WALL_STATES.has(room) and snapshot.get("room_state",0) in CERES_WALL_STATES[room]:kind=2
	if room==0x9ad9 and snapshot.get("room_state",0)==0x9ae6:kind=3
	composite.set_shader_parameter("remastered_background_kind",kind)
	composite.set_shader_parameter("remastered_background_enabled",enhanced and remastered_backgrounds and snapshot.get("state",0)==8 and kind!=0)
	composite.set_shader_parameter("backdrop_camera",snapshot.get("camera",Vector2.ZERO))
	build_sprites(snapshot)

func build_sprites(snapshot: Dictionary) -> void:
	var oam: PackedByteArray = snapshot.oam
	var raster: PackedByteArray = snapshot.raster
	var first: int = raster[92]
	sprite_count = 0
	# Resolve OAM overlaps before testing sprite priority against background layers.
	for order in range(127,-1,-1):
		var index := (first+order)&127
		var high: int = (oam[512+int(index/4)]>>((index&3)*2))&3
		var x: int = oam[index*4]|((high&1)<<8)
		if x >= 256: x -= 512
		var y: int = oam[index*4+1]
		if x <= -64 or x >= 256: continue
		var number: int = oam[index*4+2]
		var attr: int = oam[index*4+3]
		var palette := 128+((attr>>1)&7)*16
		var flip := (attr>>6)&3
		var flags := flip|(((attr>>4)&3)<<2)|((attr&1)<<4)|(((high>>1)&1)<<5)
		for origin_y in ([y,y-256] if y>192 else [y]):
			sprites.set_instance_transform_2d(sprite_count,Transform2D(0,Vector2(x+32,origin_y+32)))
			sprites.set_instance_custom_data(sprite_count,Color(number,palette,index,flags))
			sprite_count += 1
	sprites.visible_instance_count = sprite_count
