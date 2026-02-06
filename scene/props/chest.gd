extends Node2D

@onready var area: Area2D = $InteractionArea

@export var sprite_path: NodePath = NodePath("Sprite2D")
@onready var sprite_node: CanvasItem = get_node_or_null(sprite_path) as CanvasItem

@export var drop_chance: float = 0.10
@export var speed_buff_scene: PackedScene
@export var invis_buff_scene: PackedScene
@export var drop_offset: Vector2 = Vector2(0, 16)

@export var force_nearest_filter: bool = true
@export var snap_to_pixel_grid: bool = true
@export var set_alpha_cutoff: bool = false
@export var alpha_cutoff_value: float = 0.5

var player_in_range := false
var opened := false
var outline_material: ShaderMaterial
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.randomize()

	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)

	if snap_to_pixel_grid:
		_snap_tree_to_pixels(self)

	_setup_outline()

	set_outline(false)
	set_highlight(false)
	

func _setup_outline() -> void:
	if sprite_node == null:
		push_warning("Chest: sprite_node is null")
		return

	if force_nearest_filter:
		sprite_node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	outline_material = ShaderMaterial.new()
	outline_material.shader = load("res://shaders/outline.gdshader")
	sprite_node.material = outline_material

	# 🔥 ВАЖНО: принудительно
	outline_material.set_shader_parameter("alpha_cutoff", 0.01)

func _process(_delta: float) -> void:
	if opened:
		return

	if player_in_range and Input.is_action_just_pressed("interact"):
		open_chest()

func open_chest() -> void:
	opened = true
	player_in_range = false
	set_outline(false)
	set_highlight(false)

	if rng.randf() <= drop_chance:
		_spawn_random_drop()

func _spawn_random_drop() -> void:
	var scene := speed_buff_scene if rng.randi_range(0, 1) == 0 else invis_buff_scene
	if scene == null:
		return

	var item := scene.instantiate()
	get_tree().current_scene.add_child(item)
	item.global_position = global_position + drop_offset

# ---------- ВОТ ГДЕ БЫЛА ПРОБЛЕМА ----------

func _on_body_entered(body: Node) -> void:
	if opened:
		return
	if body.is_in_group("player"):
		player_in_range = true
		set_outline(true)
		set_highlight(true)
		print("ENTER:", body.name)

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player") and player_in_range:
		player_in_range = false
		set_outline(false)
		set_highlight(false)
		print("EXIT:", body.name)

# -----------------------------------------

func set_outline(enabled: bool) -> void:
	if outline_material:
		outline_material.set_shader_parameter("enabled", enabled)

func set_highlight(enabled: bool) -> void:
	if outline_material:
		outline_material.set_shader_parameter("highlight", enabled)

func _snap_tree_to_pixels(n: Node) -> void:
	if n is Node2D:
		n.position = n.position.round()
	for ch in n.get_children():
		_snap_tree_to_pixels(ch)
