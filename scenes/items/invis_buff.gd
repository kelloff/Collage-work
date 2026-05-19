extends Area2D

@onready var sprite: Sprite2D = $Sprite2D

@export var duration: float = 5.0

var player_in_range := false
var _outline_vis := InteractionOutline.new()

func _ready() -> void:
	add_to_group("tutorial_pickup")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	var mat := PickupBuffCommon.setup_sprite(sprite)
	if mat:
		_outline_vis.adopt_existing(mat)
	_outline_vis.set_both(false)

func _process(_delta: float) -> void:
	if GameState.has_method("is_world_input_blocked") and GameState.is_world_input_blocked():
		return
	if player_in_range and Input.is_action_just_pressed("interact"):
		if TutorialManager.is_active():
			if TutorialManager.try_lesson_then("buff", Callable(self, "_do_pickup")):
				return
		_do_pickup()

func _do_pickup() -> void:
	var inventory := get_tree().get_first_node_in_group("inventory")
	if inventory == null:
		return
	var icon: Texture2D = sprite.texture if sprite else null
	if icon == null:
		return
	if inventory.add_item("invis", icon, duration):
		queue_free()

func use(player: Node) -> void:
	if player and player.has_method("apply_invis_buff"):
		player.apply_invis_buff(duration)

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		player_in_range = true
		_outline_vis.set_both(true)

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		player_in_range = false
		_outline_vis.set_both(false)

func set_outline(enabled: bool) -> void:
	_outline_vis.set_outline(enabled)

func set_highlight(enabled: bool) -> void:
	_outline_vis.set_highlight(enabled)

func refresh_interaction_highlight() -> void:
	_outline_vis.refresh_from_player_in_range(player_in_range)
