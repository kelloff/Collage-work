extends Node2D
class_name Lever

@onready var sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")
@onready var area: Area2D = get_node_or_null("InteractionArea")

var is_on: bool = true
var player_in_range: bool = false
var _outline_vis := InteractionOutline.new()

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

	if sprite:
		_outline_vis.setup(sprite)
	_outline_vis.set_both(false)

	# восстановим из БД
	_restore_from_db()
	_update_visual()

	# зарегистрируем связи (если нужно)
	register_links()

	# применим к дверям состояние рычага при старте
	_apply_linked_doors()

func _process(_delta: float) -> void:
	if GameState.has_method("is_world_input_blocked") and GameState.is_world_input_blocked():
		return
	if player_in_range and Input.is_action_just_pressed("interact"):
		if TutorialManager.is_active():
			if TutorialManager.try_lesson_then("lever", Callable(self, "toggle")):
				return
		toggle()

# ---------- SAVE/LOAD ----------
func _restore_from_db() -> void:
	is_on = true
	if lever_id > 0 and DbManager.has_method("get_lever_state"):
		var state = DbManager.get_lever_state(lever_id) # 1 = down, 0 = up
		if state != null:
			is_on = (int(state) == 0) # up => on
# ------------------------------

func _write_state_to_db() -> void:
	if lever_id > 0 and DbManager.has_method("set_lever_state"):
		DbManager.set_lever_state(lever_id, not is_on) # is_down

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
			if DbManager.has_method("link_lever_to_computer"):
				DbManager.link_lever_to_computer(lever_id, comp_id)

	for did in linked_doors:
		if typeof(did) == TYPE_INT and did > 0:
			if DbManager.has_method("link_lever_to_door"):
				DbManager.link_lever_to_door(lever_id, did)

func _apply_linked_doors() -> void:
	# Несколько рычагов на одну дверь: открыть только когда ВСЕ связанные рычаги
	# в нужном положении (та же логика, что DbManager.is_door_accessible).
	var seen: Dictionary = {}
	for raw_id in linked_doors:
		var door_id := int(raw_id)
		if door_id <= 0 or seen.has(door_id):
			continue
		seen[door_id] = true
		_sync_linked_door(door_id)


func _sync_linked_door(door_id: int) -> void:
	var should_open := _door_should_be_open_by_levers(door_id)
	for d in get_tree().get_nodes_in_group("doors"):
		if d is Door and int(d.door_id) == door_id:
			if should_open:
				d.open(true)
			else:
				d.close(true)


func _door_should_be_open_by_levers(door_id: int) -> bool:
	if door_id <= 0:
		return false
	if DbManager.has_method("is_door_accessible"):
		var all_satisfied := DbManager.is_door_accessible(door_id)
		return all_satisfied if open_doors_on_down else not all_satisfied
	# Fallback: только этот рычаг (если БД недоступна)
	return (not is_on) if open_doors_on_down else is_on

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
