@tool
extends StaticBody2D
class_name Door

signal opened_by_system
signal closed_by_system

@export_enum("vertical", "horizontal") var orientation: String = "vertical"
@onready var sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")
@onready var door_collision: CollisionShape2D = get_node_or_null("CollisionShape2D")
@onready var player_collision: CollisionShape2D = get_node_or_null("PlayerCollision")
@onready var area: Area2D = get_node_or_null("Area2D")
@onready var maniac_trigger: Area2D = get_node_or_null("ManiacTrigger")
@onready var nav_link: NavigationLink2D = get_node_or_null("NavigationLink2D")
@onready var nav_a: Marker2D = get_node_or_null("A")
@onready var nav_b: Marker2D = get_node_or_null("B")
@onready var maniac_collision: CollisionShape2D = get_node_or_null("ManiacCollision")

@export var navigation_layers_mask: int = 1
@export var offset: float = 40

@export var door_id: int = 0

var is_open: bool = false
var player_in_range: bool = false
var outline_material: ShaderMaterial
var _maniacs_inside: int = 0
var _opened_by_maniac: bool = false
var _orig_collision_layer: int = 0
var _orig_collision_mask: int = 0
var _maniacs_exceptions: Array[Node] = []

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

func _update_hint_for_state() -> void:
	if not player_in_range:
		return
	if DbManager.is_door_accessible(door_id):
		_show_hint("E — открыть дверь")
	else:
		_show_hint("❌ Дверь заблокирована")

func _enter_tree() -> void:
	if not is_in_group("doors"):
		add_to_group("doors")

func _ready() -> void:
	# Логика, которая нужна и в редакторе, и в игре
	_ensure_nav_nodes()
	_place_markers_by_orientation()
	_apply_navigation_link()

	# Всё, что ниже, выполняем только в игре, чтобы не спамить ошибками в редакторе
	if Engine.is_editor_hint():
		return

	_orig_collision_layer = collision_layer
	_orig_collision_mask = collision_mask

	if sprite == null:
		push_error("Door '%s': node 'AnimatedSprite2D' NOT FOUND." % name)
	if door_collision == null and player_collision == null:
		push_error("Door '%s': node 'CollisionShape2D' OR 'PlayerCollision' NOT FOUND." % name)
	if area == null:
		push_error("Door '%s': node 'Area2D' NOT FOUND." % name)

	# Безопасное значение маски навигации
	if navigation_layers_mask == 0:
		navigation_layers_mask = 1

	if maniac_trigger:
		maniac_trigger.body_entered.connect(_on_maniac_entered)
		maniac_trigger.body_exited.connect(_on_maniac_exited)
	if area:
		area.body_entered.connect(_on_body_entered)
		area.body_exited.connect(_on_body_exited)

	_restore_from_db()

func _process(_delta: float) -> void:
	if player_in_range and Input.is_action_just_pressed("interact"):
		try_toggle_by_player()

func _ensure_nav_nodes() -> void:
	if nav_a == null:
		nav_a = Marker2D.new()
		nav_a.name = "A"
		add_child(nav_a)
		nav_a.position = Vector2(-offset, 0)
	if nav_b == null:
		nav_b = Marker2D.new()
		nav_b.name = "B"
		add_child(nav_b)
		nav_b.position = Vector2(offset, 0)
	if nav_link == null:
		nav_link = NavigationLink2D.new()
		nav_link.name = "NavigationLink2D"
		add_child(nav_link)
		nav_link.enabled = false
		if navigation_layers_mask == 0:
			navigation_layers_mask = 1
		nav_link.navigation_layers = navigation_layers_mask
	if nav_a and nav_b and nav_link:
		nav_link.start_position = nav_a.global_position
		nav_link.end_position = nav_b.global_position

func _place_markers_by_orientation() -> void:
	# Меняем местами логику, чтобы:
	# - "horizontal" — проход слева-направо (маркеры по бокам),
	# - "vertical"   — проход снизу-вверх (маркеры сверху/снизу).
	if orientation == "horizontal":
		nav_a.position = Vector2(-offset, 0)
		nav_b.position = Vector2(offset, 0)
	else:
		nav_a.position = Vector2(0, -offset)
		nav_b.position = Vector2(0, offset)
	_apply_navigation_link()

func _restore_from_db() -> void:
	if door_id > 0 and DbManager.has_method("get_door_state"):
		var st = DbManager.get_door_state(door_id)
		if st != null:
			is_open = bool(st)
			_apply_visuals()
	else:
		is_open = false
		_apply_visuals()

func _write_state_to_db() -> void:
	if door_id > 0 and DbManager.has_method("set_door_state"):
		DbManager.set_door_state(door_id, is_open)

func _apply_visuals() -> void:
	if sprite:
		sprite.animation = "open" if is_open else "closed"
		sprite.frame = 0
		sprite.stop()

	# Коллизии:
	# - Если дверь открыл маньяк: игрок ДОЛЖЕН оставаться заблокированным.
	#   Поэтому мы НЕ отключаем коллизии двери для всех — а делаем
	#   исключение конкретно для маньяка через collision exceptions.
	# - Если дверь открыл игрок/система: отключаем коллизии полностью.
	var collisions_disabled: bool = is_open and (not _opened_by_maniac)
	_set_collision_shapes_recursive(self, collisions_disabled)

	_apply_navigation_link()

func _is_descendant_of(node: Node, ancestor: Node) -> bool:
	if node == null or ancestor == null:
		return false
	var p: Node = node
	while p != null:
		if p == ancestor:
			return true
		p = p.get_parent()
	return false

func _set_collision_shapes_recursive(root: Node, open_state: bool) -> void:
	# Отключаем ЛЮБЫЕ объекты коллизий, которые могут блокировать движение,
	# кроме коллизий внутри Area2D и ManiacTrigger (иначе ломаем взаимодействия).
	for c in root.get_children():
		# В Godot 4 `Area2D` (и вообще некоторые Physics-узлы) не имеют свойства `disabled`,
		# поэтому отключаем именно формы столкновений.
		if c is CollisionShape2D or c is CollisionPolygon2D:
			if _is_descendant_of(c, area) or _is_descendant_of(c, maniac_trigger):
				continue
			if c is CollisionShape2D:
				(c as CollisionShape2D).disabled = open_state
			else:
				(c as CollisionPolygon2D).disabled = open_state
		_set_collision_shapes_recursive(c, open_state)

func try_toggle_by_player() -> void:
	if not DbManager.is_door_accessible(door_id):
		_show_hint("❌ Дверь заблокирована", 1.5)
		return
	toggle(false)

func toggle(by_system: bool = false) -> void:
	if not DbManager.is_door_accessible(door_id):
		_show_hint("❌ Дверь заблокирована", 1.5)
		return
	# Если маньяк уже за/у двери (в ManiacTrigger), игрок не должен
	# иметь возможность закрыть дверь “прямо перед носом”.
	if not by_system and is_open and _is_maniac_nearby_in_trigger():
		_show_hint("Маньяк не даст закрыть дверь", 1.2)
		return
	# Если игрок находится внутри коллизии самой двери — закрывать нельзя,
	# чтобы не получать "застревание" в коллизиях.
	if not by_system and is_open and _is_player_inside_door_collision_shape():
		_show_hint("Выйди из двери", 1.2)
		return
	is_open = not is_open
	_opened_by_maniac = by_system and is_open
	_apply_visuals()
	_write_state_to_db()
	if by_system:
		if is_open: emit_signal("opened_by_system")
		else: emit_signal("closed_by_system")
	_update_hint_for_state()

	# Если дверь закрылась (не важно: игроком или системой),
	# нужно снять collision-exception, иначе маньяк сможет пройти
	# через уже закрытую дверь.
	if not is_open:
		_clear_maniac_collision_exceptions()
		# Если маньяк прямо сейчас в триггере двери, ему нужно
		# переоткрыть дверь после того, как игрок закрыл её у носа.
		_try_reopen_for_maniacs_inside()

func open(by_system: bool = false) -> void:
	if is_open: return
	is_open = true
	_opened_by_maniac = by_system
	_apply_visuals()
	_write_state_to_db()
	if by_system: emit_signal("opened_by_system")
	_update_hint_for_state()
	for m in get_tree().get_nodes_in_group("maniac"):
		if m.has_method("refresh_navigation"):
			m.refresh_navigation()

	# Когда дверь открыта обычным способом, исключения для маньяков не нужны.
	_clear_maniac_collision_exceptions()

func close(by_system: bool = false) -> void:
	if not is_open: return
	# Те же ограничения для принудительного close(false), если вдруг
	# какой-то код вызывает его не через toggle.
	if not by_system and _is_maniac_nearby_in_trigger():
		_show_hint("Маньяк не даст закрыть дверь", 1.2)
		return
	if not by_system and _is_player_inside_door_collision_shape():
		_show_hint("Выйди из двери", 1.2)
		return
	is_open = false
	_opened_by_maniac = false
	_apply_visuals()
	_write_state_to_db()
	_clear_maniac_collision_exceptions()
	_try_reopen_for_maniacs_inside()
	if by_system: emit_signal("closed_by_system")
	_update_hint_for_state()

func _is_maniac_nearby_in_trigger() -> bool:
	# Быстрая проверка по счетчику
	if _maniacs_inside > 0:
		return true
	if maniac_trigger == null:
		return false
	# На случай, если счетчик рассинхронился из-за тайминга.
	var bodies: Array[Node2D] = maniac_trigger.get_overlapping_bodies()
	for b in bodies:
		if b == null:
			continue
		if b.is_in_group("maniac"):
			return true
	return false

func _get_player_node() -> Node:
	# Берём первый найденный игрок (обычно в сцене один).
	for p in get_tree().get_nodes_in_group("player"):
		if p == null:
			continue
		return p
	return null

func _is_player_inside_door_collision_shape() -> bool:
	# Проверяем именно коллизию "тела двери", а не Area2D интеракшена.
	if door_collision == null:
		return false
	var p: Node = _get_player_node()
	if p == null:
		return false
	var sh: Shape2D = door_collision.shape
	if sh == null:
		return false

	# Переводим позицию игрока в локальные координаты CollisionShape2D.
	var lp: Vector2 = door_collision.to_local(p.global_position)
	var eps: float = 1.0

	if sh is RectangleShape2D:
		var rect_sh := sh as RectangleShape2D
		var half: Vector2 = rect_sh.size * 0.5
		return abs(lp.x) <= half.x + eps and abs(lp.y) <= half.y + eps

	# На случай других форм — пока не поддерживаем.
	return false

func _clear_maniac_collision_exceptions() -> void:
	# Снимаем исключения collision для любых маньяков,
	# которые получали “проход” через открытую дверь.
	for m in _maniacs_exceptions:
		if m == null:
			continue
		if m is CollisionObject2D and has_method("remove_collision_exception_with"):
			remove_collision_exception_with(m)
	_maniacs_exceptions.clear()

func _try_reopen_for_maniacs_inside() -> void:
	# Если дверь снова открывать не надо — выходим.
	if is_open:
		return
	if maniac_trigger == null:
		return

	var bodies: Array[Node2D] = maniac_trigger.get_overlapping_bodies()
	for b in bodies:
		if b == null:
			continue
		if not b.is_in_group("maniac"):
			continue
		if not b.has_method("can_open_door_from_trigger"):
			continue
		if b.can_open_door_from_trigger(self):
			open_for_maniac(b)
			return

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		player_in_range = true
		set_outline(true)
		set_highlight(true)
		_update_hint_for_state()

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		player_in_range = false
		set_outline(false)
		set_highlight(false)
		_hide_hint()

func open_for_maniac(maniac_body: Node) -> void:
	# Для маньяка открываем дверь и запоминаем причину.
	_opened_by_maniac = true
	open(true)
	# NavigationLink2D включится в _apply_navigation_link()

	# Гарантируем, что навигационные маркеры есть.
	if nav_a == null or nav_b == null:
		return

	if maniac_body == null:
		return

	# Задаём цель только тому маньяку, который активировал дверь,
	# чтобы он не залипал у порога.
	if not maniac_body.has_method("set_door_exit_target"):
		return

	var a_pos: Vector2 = nav_a.global_position
	var b_pos: Vector2 = nav_b.global_position
	var from_pos: Vector2 = maniac_body.global_position

	var dist_a: float = from_pos.distance_to(a_pos)
	var dist_b: float = from_pos.distance_to(b_pos)
	var exit_point: Vector2 = b_pos if dist_a < dist_b else a_pos

	# Чуть смещаемся внутрь комнаты от края двери.
	var dir: Vector2 = exit_point - from_pos
	if dir.length() > 0.001:
		dir = dir.normalized()
	exit_point = exit_point + dir * 16.0

	# true = используем chase_speed, чтобы быстрее "протолкнуться" внутрь.
	maniac_body.set_door_exit_target(exit_point, true)

	# Делаем исключение столкновения: маньяк сможет пройти, а игрок — нет.
	# Это полностью решает проблему "игрок тоже проходит", не требуя
	# менять collision layers у персонажей.
	if maniac_body is CollisionObject2D:
		if not _maniacs_exceptions.has(maniac_body):
			_maniacs_exceptions.append(maniac_body)
		add_collision_exception_with(maniac_body)

func close_after_maniac(delay := 1.2) -> void:
	await get_tree().create_timer(delay).timeout
	if is_open and _opened_by_maniac and _maniacs_inside <= 0:
		close()

func set_outline(enabled: bool) -> void:
	if outline_material:
		outline_material.set_shader_parameter("enabled", enabled)

func set_highlight(enabled: bool) -> void:
	if outline_material:
		outline_material.set_shader_parameter("highlight", enabled)

func _apply_navigation_link() -> void:
	if nav_link == null: return
	nav_link.enabled = is_open
	nav_link.navigation_layers = navigation_layers_mask
	if nav_a and nav_b:
		nav_link.start_position = nav_a.global_position
		nav_link.end_position = nav_b.global_position
	call_deferred("_apply_navigation_link_deferred")

func _apply_navigation_link_deferred() -> void:
	if nav_link and nav_a and nav_b:
		nav_link.start_position = nav_a.global_position
		nav_link.end_position = nav_b.global_position

func _on_maniac_entered(body: Node) -> void:
	if body.is_in_group("maniac"):
		_maniacs_inside += 1
		# Открываем дверь из триггера ТОЛЬКО если маньяк уже
		# действительно хочет идти через эту дверь в погоне.
		if body.has_method("can_open_door_from_trigger"):
			var can_open: bool = body.can_open_door_from_trigger(self)
			print(
				"[Door] trigger enter:",
				name,
				" by maniac:",
				body.name,
				" can_open:",
				can_open
			)
			if can_open:
				open_for_maniac(body)

func _on_maniac_exited(body: Node) -> void:
	if body.is_in_group("maniac"):
		_maniacs_inside = max(_maniacs_inside - 1, 0)
		if body in _maniacs_exceptions:
			_maniacs_exceptions.erase(body)
		if body is CollisionObject2D and has_method("remove_collision_exception_with"):
			remove_collision_exception_with(body)
		if _maniacs_inside <= 0 and _opened_by_maniac:
			close_after_maniac(1.2)

# --- Navigation2D helpers ---
func _get_navigation2d():
	var root = get_tree().get_current_scene()
	if root == null: return null
	var nav = root.get_node_or_null("Navigation2D")
	if nav: return nav
	return _find_navigation2d_recursive(root)

func _find_navigation2d_recursive(node):
	if node == null: return null
	if node.get_class() == "Navigation2D": return node
	for child in node.get_children():
		var found = _find_navigation2d_recursive(child)
		if found: return found
	return null
