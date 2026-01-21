extends Node2D

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var area: Area2D = $InteractionArea

var is_on: bool = true
var player_in_range: bool = false
var outline_material: ShaderMaterial

@export var lever_id: int = 0
@export var linked_computers: Array[int] = []

func _enter_tree() -> void:
	if not is_in_group("levers"):
		add_to_group("levers")

func _ready() -> void:
	if area:
		area.body_entered.connect(_on_body_entered)
		area.body_exited.connect(_on_body_exited)

	# Начальное состояние: рычаг поднят (is_on = true), значит is_down = false
	is_on = true
	sprite.animation = "up"
	sprite.frame = 0
	sprite.stop()

	outline_material = ShaderMaterial.new()
	if ResourceLoader.exists("res://shaders/outline.gdshader"):
		outline_material.shader = load("res://shaders/outline.gdshader")
		sprite.material = outline_material

	set_outline(false)
	set_highlight(false)

	if lever_id > 0:
		DbMeneger.set_lever_state(lever_id, not is_on)
	else:
		push_warning("Lever '%s' has lever_id = 0 — установи в инспекторе" % name)

func register_links() -> void:
	if lever_id == 0:
		push_warning("Lever '%s' has lever_id = 0 — не могу зарегистрировать связи" % name)
		return
	for comp_id in linked_computers:
		if typeof(comp_id) == TYPE_INT and comp_id > 0:
			DbMeneger.link_lever_to_computer(lever_id, comp_id)
		else:
			push_warning("Lever '%s': некорректный ID компьютера: %s" % [name, str(comp_id)])

func _process(_delta: float) -> void:
	if player_in_range and Input.is_action_just_pressed("interact"):
		toggle()

func toggle() -> void:
	is_on = not is_on
	sprite.animation = "up" if is_on else "down"
	sprite.frame = 0
	sprite.stop()

	if lever_id > 0:
		DbMeneger.set_lever_state(lever_id, not is_on)
		print("Lever toggled: %s (lever_id=%d) → is_down=%d" % [name, lever_id, int(not is_on)])
	else:
		push_warning("Lever '%s': toggle без lever_id" % name)

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
