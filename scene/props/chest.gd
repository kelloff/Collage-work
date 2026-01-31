extends Node2D

@onready var area: Area2D = $InteractionArea

# Вариант 1: если Sprite2D
@onready var sprite: Sprite2D = $Sprite2D
# Вариант 2: если AnimatedSprite2D (тогда закомментируй строку выше и раскомментируй ниже)
#@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

@export var drop_chance: float = 0.10
@export var speed_buff_scene: PackedScene
@export var invis_buff_scene: PackedScene
@export var drop_offset: Vector2 = Vector2(0, 16)

var player_in_range: bool = false
var opened: bool = false
var outline_material: ShaderMaterial
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.randomize()

	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)

	# --- Outline как у рычага ---
	outline_material = ShaderMaterial.new()
	if ResourceLoader.exists("res://shaders/outline.gdshader"):
		outline_material.shader = load("res://shaders/outline.gdshader")
		sprite.material = outline_material

	set_outline(false)
	set_highlight(false)

func _process(_delta: float) -> void:
	if opened:
		return
	if player_in_range and Input.is_action_just_pressed("interact"):
		open_chest()

func open_chest() -> void:
	opened = true
	set_outline(false)
	set_highlight(false)

	if rng.randf() <= drop_chance:
		_spawn_random_drop()

func _spawn_random_drop() -> void:
	var pick := rng.randi_range(0, 1)
	var scene: PackedScene = speed_buff_scene if pick == 0 else invis_buff_scene

	if scene == null:
		push_error("Chest: не назначены сцены баффов!")
		return

	var item := scene.instantiate() as Node2D
	get_tree().current_scene.add_child(item)
	item.global_position = global_position + drop_offset

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player") and not opened:
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
