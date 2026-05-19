extends Node2D

const DROP_OCCUPY_RADIUS := 14.0
const DROP_RING_STEP := 18.0

@onready var area: Area2D = $InteractionArea

@export var sprite_path: NodePath = NodePath("Sprite2D")
@onready var sprite_node: CanvasItem = get_node_or_null(sprite_path) as CanvasItem

@export_range(0.0, 1.0) var drop_chance: float = 0.12
@export_range(0, 3) var drops_per_open: int = 1
@export_range(0.0, 1.0) var extra_drop_chance: float = 0.0
@export var speed_buff_scene: PackedScene = preload("res://scenes/items/speed_buff.tscn")
@export var invis_buff_scene: PackedScene = preload("res://scenes/items/invis_buff.tscn")
@export var heal_buff_scene: PackedScene = preload("res://scenes/items/heal_buff.tscn")
@export var drop_offset: Vector2 = Vector2(0, 16)
@export var tutorial_step: String = ""

@export var force_nearest_filter: bool = true
@export var snap_to_pixel_grid: bool = true
@export var set_alpha_cutoff: bool = false
@export var alpha_cutoff_value: float = 0.5

var player_in_range := false
var opened := false
var _outline_vis := InteractionOutline.new()
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.randomize()

	if tutorial_step != "":
		add_to_group("tutorial_target")

	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)

	if snap_to_pixel_grid:
		_snap_tree_to_pixels(self)

	_setup_outline()
	_outline_vis.set_both(false)

func _setup_outline() -> void:
	if sprite_node == null:
		push_warning("Chest: sprite_node is null")
		return
	if force_nearest_filter:
		sprite_node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var cutoff := alpha_cutoff_value if set_alpha_cutoff else 0.01
	_outline_vis.setup(sprite_node, cutoff)

func _process(_delta: float) -> void:
	if opened:
		return
	if GameState.has_method("is_world_input_blocked") and GameState.is_world_input_blocked():
		return

	if player_in_range and Input.is_action_just_pressed("interact"):
		if TutorialManager.is_active():
			if TutorialManager.try_lesson_then("chest", Callable(self, "open_chest")):
				return
		open_chest()

func open_chest() -> void:
	opened = true
	player_in_range = false
	_outline_vis.set_both(false)

	var drop_count := _roll_drop_count(
		TutorialManager.is_active() and tutorial_step in ["chest_1", "chest_2", "chest_3"]
	)
	if drop_count > 0:
		_spawn_drops(drop_count)
	if TutorialManager.is_active():
		TutorialManager.notify_chest_opened(tutorial_step)

func _roll_drop_count(force_one: bool) -> int:
	if force_one:
		return mini(drops_per_open, 1)
	var count := 0
	if rng.randf() <= drop_chance:
		count = 1
	if drops_per_open > 1 and extra_drop_chance > 0.0:
		for i in range(1, drops_per_open):
			if rng.randf() <= extra_drop_chance:
				count += 1
	return count

func _spawn_drops(count: int) -> void:
	var scenes: Array[PackedScene] = []
	if speed_buff_scene:
		scenes.append(speed_buff_scene)
	if invis_buff_scene:
		scenes.append(invis_buff_scene)
	if heal_buff_scene:
		scenes.append(heal_buff_scene)
	if scenes.is_empty():
		return

	var base_pos: Vector2 = global_position + drop_offset
	var positions: Array[Vector2] = _compute_drop_positions(base_pos, count)
	for i in range(count):
		var scene: PackedScene = scenes[rng.randi_range(0, scenes.size() - 1)]
		var item := scene.instantiate()
		get_tree().current_scene.add_child(item)
		if item is Node2D:
			item.global_position = positions[i]

func _on_body_entered(body: Node) -> void:
	if opened:
		return
	if body.is_in_group("player"):
		player_in_range = true
		_outline_vis.set_both(true)

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player") and player_in_range:
		player_in_range = false
		_outline_vis.set_both(false)

func set_outline(enabled: bool) -> void:
	_outline_vis.set_outline(enabled)

func set_highlight(enabled: bool) -> void:
	_outline_vis.set_highlight(enabled)

func refresh_interaction_highlight() -> void:
	if opened:
		_outline_vis.set_both(false)
		return
	_outline_vis.refresh_from_player_in_range(player_in_range)

func _snap_tree_to_pixels(n: Node) -> void:
	if n is Node2D:
		n.position = n.position.round()
	for ch in n.get_children():
		_snap_tree_to_pixels(ch)

func _compute_drop_positions(base: Vector2, count: int) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var occupied: Array[Vector2] = []
	for n in get_tree().get_nodes_in_group("tutorial_pickup"):
		if n is Node2D and is_instance_valid(n):
			occupied.append(n.global_position)
	var offsets: Array[Vector2] = [
		Vector2.ZERO,
		Vector2(DROP_RING_STEP, 0), Vector2(-DROP_RING_STEP, 0),
		Vector2(0, DROP_RING_STEP), Vector2(0, -DROP_RING_STEP),
		Vector2(DROP_RING_STEP, DROP_RING_STEP), Vector2(-DROP_RING_STEP, DROP_RING_STEP),
		Vector2(DROP_RING_STEP, -DROP_RING_STEP), Vector2(-DROP_RING_STEP, -DROP_RING_STEP),
		Vector2(DROP_RING_STEP * 2, 0), Vector2(-DROP_RING_STEP * 2, 0),
		Vector2(0, DROP_RING_STEP * 2),
	]
	for i in range(count):
		var placed := false
		for off in offsets:
			var pos: Vector2 = base + off
			var free := true
			for o in occupied:
				if pos.distance_to(o) < DROP_OCCUPY_RADIUS:
					free = false
					break
			if free:
				result.append(pos)
				occupied.append(pos)
				placed = true
				break
		if not placed:
			var fallback: Vector2 = base + Vector2(DROP_RING_STEP * (i + 1), 0)
			result.append(fallback)
			occupied.append(fallback)
	return result
