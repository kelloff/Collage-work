extends Node2D

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var area: Area2D = $InteractionArea

var is_on := false
var player_in_range := false
var linked_doors: Array = []

var outline_material: ShaderMaterial


func _ready():
	# Area
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)

	# Sprite initial state
	sprite.animation = "down"
	sprite.frame = 0
	sprite.stop()

	# Shader material (ОБЯЗАТЕЛЬНО новый экземпляр!)
	outline_material = ShaderMaterial.new()
	outline_material.shader = load("res://shaders/outline.gdshader")
	sprite.material = outline_material

	set_outline(false)


func _process(_delta):
	if player_in_range and Input.is_action_just_pressed("interact"):
		toggle()


func toggle():
	is_on = !is_on

	sprite.animation = is_on ? "up" : "down"
	sprite.frame = 0
	sprite.stop()

	for door in linked_doors:
		if door.has_method("on_lever_toggled"):
			door.on_lever_toggled(self, is_on)


func _on_body_entered(body):
	if body.is_in_group("player"):
		player_in_range = true
		set_outline(true)


func _on_body_exited(body):
	if body.is_in_group("player"):
		player_in_range = false
		set_outline(false)


func set_outline(enabled: bool):
	if outline_material:
		outline_material.set_shader_parameter("enabled", enabled)
