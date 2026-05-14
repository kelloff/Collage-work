# invis_buff.gd
extends Area2D

@onready var sprite: Sprite2D = $Sprite2D

@export var duration: float = 4.0

var player_in_range := false
var outline_material: ShaderMaterial

func _ready() -> void:
	add_to_group("tutorial_pickup")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	outline_material = ShaderMaterial.new()
	if ResourceLoader.exists("res://shaders/outline.gdshader"):
		outline_material.shader = load("res://shaders/outline.gdshader")
		sprite.material = outline_material

	set_outline(false)
	set_highlight(false)

func _process(_delta: float) -> void:
	if GameState.has_method("is_world_input_blocked") and GameState.is_world_input_blocked():
		return
	if player_in_range and Input.is_action_just_pressed("interact"):
		if TutorialManager.is_active() and TutorialManager.get_current_step() == "pickup":
			TutorialManager.try_interact_step("pickup", Callable(self, "_do_pickup"))
			return
		_do_pickup()

func _do_pickup() -> void:
	var inventory := get_tree().get_first_node_in_group("inventory")
	if inventory == null:
		push_error("invis_buff: inventory not found (add Inventory to group 'inventory')")
		return

	var icon: Texture2D = sprite.texture
	if inventory.add_item("invis", icon, duration, 0.0):
		queue_free()

# Вызывается из инвентаря/слота при использовании
func use(player: Node) -> void:
	if player and player.has_method("apply_invisibility"):
		player.apply_invisibility(duration)

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
