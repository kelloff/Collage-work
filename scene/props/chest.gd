extends Node2D

@onready var area: Area2D = $InteractionArea

# --- Выбор узла со спрайтом через инспектор (лучше, чем жестко $Sprite2D) ---
@export var sprite_path: NodePath = NodePath("Sprite2D")
@onready var sprite_node: CanvasItem = get_node_or_null(sprite_path) as CanvasItem

@export var drop_chance: float = 0.10
@export var speed_buff_scene: PackedScene
@export var invis_buff_scene: PackedScene
@export var drop_offset: Vector2 = Vector2(0, 16)

# --- Визуальные фиксы для пиксель-арта ---
@export var force_nearest_filter: bool = true
@export var snap_to_pixel_grid: bool = true

# Если добавишь uniform float alpha_cutoff в outline.gdshader — это поможет PNG с “мягкими” краями
@export var set_alpha_cutoff: bool = false
@export var alpha_cutoff_value: float = 0.9

var player_in_range: bool = false
var opened: bool = false
var outline_material: ShaderMaterial
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.randomize()

	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)

	# 1) прибиваем позицию к целым пикселям (если надо)
	if snap_to_pixel_grid:
		_snap_tree_to_pixels(self)

	# 2) шейдер обводки
	_setup_outline()

	set_outline(false)
	set_highlight(false)

func _setup_outline() -> void:
	if sprite_node == null:
		push_warning("Chest: sprite_node is null. Проверь sprite_path в инспекторе (например 'Sprite2D').")
		return

	# Пиксельный фильтр (важно для PNG)
	if force_nearest_filter:
		sprite_node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	outline_material = ShaderMaterial.new()
	if ResourceLoader.exists("res://shaders/outline.gdshader"):
		outline_material.shader = load("res://shaders/outline.gdshader")
		sprite_node.material = outline_material

		# опционально: задаём порог альфы (если есть в шейдере)
		if set_alpha_cutoff:
			# если параметра нет — Godot просто выдаст предупреждение в Output, критичного нет
			outline_material.set_shader_parameter("alpha_cutoff", alpha_cutoff_value)
	else:
		push_warning("Chest: outline shader not found: res://shaders/outline.gdshader")

func _process(_delta: float) -> void:
	if opened:
		return
	if player_in_range:
		set_outline(true)
		
		_show_hint("E - открыть сундук")
		if Input.is_action_just_pressed("interact"):
			_hide_hint()
			open_chest()
	else:
		_hide_hint()
		
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

# --- полезно для пиксельной сетки ---
func _snap_tree_to_pixels(n: Node) -> void:
	# Прибиваем позиции Node2D и всех потомков к целым пикселям
	if n is Node2D:
		var nd := n as Node2D
		nd.position = Vector2(round(nd.position.x), round(nd.position.y))

	for ch in n.get_children():
		_snap_tree_to_pixels(ch)
		
# ---------------- HUD helpers ----------------
func _hud() -> Node:
	return get_tree().current_scene.get_node_or_null("HUD")

func _show_hint(text: String, duration: float = 0.0) -> void:
	var hud = _hud()
	if hud and hud.has_method("show_hint"):
		hud.show_hint(text, duration, self)

func _hide_hint() -> void:
	var hud = _hud()
	if hud and hud.has_method("hide_hint"):
		hud.hide_hint(self)
