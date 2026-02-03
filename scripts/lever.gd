extends Node2D
class_name Lever

@onready var sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")
@onready var area: Area2D = get_node_or_null("InteractionArea")

var is_on: bool = true
var player_in_range: bool = false
var outline_material: ShaderMaterial

@export var lever_id: int = 0
@export var linked_computers: Array[int] = []
@export var linked_doors: Array[int] = []
@export var open_doors_on_down: bool = true

func _enter_tree() -> void:
	if not is_in_group("levers"):
		add_to_group("levers")

func _ready() -> void:
	if area:
		area.body_entered.connect(_on_body_entered)
		area.body_exited.connect(_on_body_exited)

	if sprite == null:
		push_error("Lever '%s': node 'AnimatedSprite2D' NOT FOUND. Проверь имя узла!" % name)

	# outline
	if sprite:
		outline_material = ShaderMaterial.new()
		if ResourceLoader.exists("res://shaders/outline.gdshader"):
			outline_material.shader = load("res://shaders/outline.gdshader")
			sprite.material = outline_material
		set_outline(false)
		set_highlight(false)

	# восстановим из БД
	_restore_from_db()
	_update_visual()

	# зарегистрируем связи (если нужно)
	register_links()

	# применим к дверям состояние рычага при старте
	_apply_linked_doors()

func _process(_delta: float) -> void:
	if player_in_range and Input.is_action_just_pressed("interact"):
		toggle()

# ---------- SAVE/LOAD ----------
func _restore_from_db() -> void:
	is_on = true
	if lever_id > 0 and DbMeneger.has_method("get_lever_state"):
		var state = DbMeneger.get_lever_state(lever_id) # 1 = down, 0 = up
		if state != null:
			is_on = (int(state) == 0) # up => on
# ------------------------------

func _write_state_to_db() -> void:
	if lever_id > 0 and DbMeneger.has_method("set_lever_state"):
		DbMeneger.set_lever_state(lever_id, not is_on) # is_down

func _update_visual() -> void:
	if not sprite:
		return
	sprite.animation = ("up" if is_on else "down")
	sprite.frame = 0
	sprite.stop()

func toggle() -> void:
	is_on = not is_on
	_update_visual()
	_write_state_to_db()

	# ждём кадр (без таймера)
	await get_tree().process_frame

	_apply_linked_doors()

func register_links() -> void:
	if lever_id <= 0:
		return

	for comp_id in linked_computers:
		if typeof(comp_id) == TYPE_INT and comp_id > 0:
			if DbMeneger.has_method("link_lever_to_computer"):
				DbMeneger.link_lever_to_computer(lever_id, comp_id)

	for did in linked_doors:
		if typeof(did) == TYPE_INT and did > 0:
			if DbMeneger.has_method("link_lever_to_door"):
				DbMeneger.link_lever_to_door(lever_id, did)

func _apply_linked_doors() -> void:
	var should_open := ((not is_on) if open_doors_on_down else is_on)

	for d in get_tree().get_nodes_in_group("doors"):
		# берём только двери
		if not (d is Door):
			continue
		if int(d.door_id) in linked_doors:
			if should_open:
				d.open(true)
			else:
				d.close(true)

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
