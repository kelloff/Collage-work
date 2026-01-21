extends StaticBody2D

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var door_collision: CollisionShape2D = $CollisionShape2D
@onready var area: Area2D = $Area2D

var is_open: bool = false
var player_in_range: bool = false
var outline_material: ShaderMaterial

@export var door_id: int = 0


func _enter_tree() -> void:
	if not is_in_group("doors"):
		add_to_group("doors")


func _ready() -> void:
	if area:
		area.body_entered.connect(_on_body_entered)
		area.body_exited.connect(_on_body_exited)

	# Начальное состояние — дверь закрыта
	is_open = false
	sprite.animation = "closed"
	sprite.frame = 0
	sprite.stop()
	door_collision.disabled = false

	# Outline / highlight — как у рычага
	outline_material = ShaderMaterial.new()
	if ResourceLoader.exists("res://shaders/outline.gdshader"):
		outline_material.shader = load("res://shaders/outline.gdshader")
		sprite.material = outline_material

	set_outline(false)
	set_highlight(false)

	if door_id == 0:
		push_warning("Door '%s' has door_id = 0 — установи в инспекторе" % name)


func _process(_delta: float) -> void:
	if player_in_range and Input.is_action_just_pressed("interact"):
		toggle()


func toggle() -> void:
	if is_open:
		close()
	else:
		open()


func open() -> void:
	if is_open:
		return

	is_open = true
	sprite.animation = "open"
	sprite.frame = 0
	sprite.stop()
	door_collision.disabled = true

	print("Door opened:", name, "door_id =", door_id)


func close() -> void:
	if not is_open:
		return

	is_open = false
	sprite.animation = "closed"
	sprite.frame = 0
	sprite.stop()
	door_collision.disabled = false

	print("Door closed:", name, "door_id =", door_id)


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
