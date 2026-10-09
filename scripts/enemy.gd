class_name NativeEnemy
extends CharacterBody2D

var record: Dictionary = {}
var player: NativeSamus
var origin := Vector2.ZERO
var health := 15
var damage_amount := 5
var direction := 1.0
var time := 0.0
var frozen := 0.0
var enhanced := true
var sprite: Sprite2D
var active := true
var skree_diving := false
var texture_original: Texture2D
var texture_enhanced: Texture2D

func configure(info: Dictionary, spawn: Dictionary, target: NativeSamus) -> void:
	record = info
	player = target
	position = Vector2(spawn.x,spawn.y)
	origin = position
	health = int(record.health)
	damage_amount = int(record.damage)
	direction = -1.0 if int(spawn.parameter1)&1 else 1.0

func _ready() -> void:
	collision_layer = 4
	collision_mask = 1
	var shape := RectangleShape2D.new()
	shape.size = Vector2(maxf(8,record.width*2),maxf(6,record.height*2))
	var collision := CollisionShape2D.new()
	collision.shape = shape
	add_child(collision)
	sprite = Sprite2D.new()
	texture_original = load("res://assets/extracted/objects/%s_original.png"%record.animation)
	texture_enhanced = load("res://assets/extracted/objects/%s_enhanced.png"%record.animation)
	sprite.hframes = record.frames
	add_child(sprite)
	set_enhanced(enhanced)

func set_enhanced(value: bool) -> void:
	enhanced = value
	if not sprite: return
	sprite.material=load("res://assets/remastered/sprite_lighting.tres") if value else null
	sprite.texture = texture_enhanced if value else texture_original
	sprite.scale = Vector2.ONE*(0.25 if value else 1.0)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func _physics_process(delta: float) -> void:
	if not active: return
	time += delta
	frozen = maxf(0,frozen-delta)
	if frozen>0:
		sprite.modulate = Color(0.4,0.8,1.0)
		return
	sprite.modulate = Color.WHITE
	sprite.frame = int(time*8)%int(record.frames)
	sprite.flip_h = direction<0
	match record.animation:
		"zoomer":
			velocity.x = direction*30
			velocity.y = minf(velocity.y+500*delta,250)
			if is_on_wall(): direction*=-1
			if is_on_floor():
				var q := PhysicsRayQueryParameters2D.create(position+Vector2(direction*14,0),position+Vector2(direction*14,18),1)
				if get_world_2d().direct_space_state.intersect_ray(q).is_empty(): direction*=-1
		"ripper":
			velocity = Vector2(direction*42,0)
			if is_on_wall(): direction*=-1
		"skree":
			if not skree_diving and absf(player.position.x-position.x)<70: skree_diving=true
			velocity = Vector2(direction*20,240) if skree_diving else Vector2.ZERO
			if is_on_floor() and skree_diving: queue_free()
	move_and_slide()
	if player.position.distance_to(position)<float(record.width)+10: player.damage(damage_amount,position)

func hit(amount: int, ice: bool = false) -> bool:
	if is_queued_for_deletion(): return false
	if ice and frozen<=0:
		frozen=2.0
		return false
	health-=amount
	if health<=0:
		queue_free()
		return true
	return false

func contains_hit(p: Vector2) -> bool:
	return Rect2(position-Vector2(record.width,record.height),Vector2(record.width*2,record.height*2)).grow(2).has_point(p)
