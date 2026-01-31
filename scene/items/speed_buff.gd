extends Area2D

@onready var sprite: Sprite2D = $Sprite2D

@export var duration: float = 5.0
@export var speed_multiplier: float = 1.5

var player_in_range := false
var outline_material: ShaderMaterial

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	# outline как у рычага
	outline_material = ShaderMaterial.new()
	if ResourceLoader.exists("res://shaders/outline.gdshader"):
		outline_material.shader = load("res://shaders/outline.gdshader")
		sprite.material = outline_material

	set_outline(false)
	set_highlight(false)

func _process(_delta: float) -> void:
	if player_in_range and Input.is_action_just_pressed("interact"):
		var player := _get_player()
		if player and player.has_method("apply_speed_buff"):
			player.apply_speed_buff(speed_multiplier, duration)
		queue_free()

func _get_player() -> Node:
	for b in get_overlapping_bodies():
		if b.is_in_group("player"):
			return b
	return null

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		player_in_range = true
		set_outline(true)
		set_highlight(true)

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		player_in_range = false
		set_outline(false)
		set_highlight(false)

func set_outline(enabled: bool) -> void:
	if outline_material:
		outline_material.set_shader_parameter("enabled", enabled)

func set_highlight(enabled: bool) -> void:
	if outline_material:
		outline_material.set_shader_parameter("highlight", enabled)
