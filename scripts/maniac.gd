extends CharacterBody2D

enum State { PATROL, CHASE }

@export var speed: float = 99.0 # ~10% медленнее
@export var chase_speed: float = 117.0 # ~10% медленнее
@export var detection_radius: float = 220.0
@export var attack_range: float = 20.0
@export var acceleration: float = 900.0
@export var target_update_interval: float = 0.15
@export var rooms_group_name: String = "rooms"
@export var room_pick_attempts: int = 28
@export var room_id_meta_key: String = "room_id"
@export var room_patrol_min_time_s: float = 10.0
@export var room_patrol_max_time_s: float = 15.0
@export var door_open_attempt_max_dist_px: float = 140.0
@export var debug_collision_prints: bool = true
@export var debug_collision_cooldown: float = 0.6
@export var debug_collision_distance_to_target: float = 500
@export var stuck_move_epsilon_px: float = 1.5
@export var stuck_time_before_reset_s: float = 1.2
@export var wall_escape_distance_to_target_px: float = 6.0
@export var wall_escape_speed: float = 180.0
@export var wall_escape_cooldown_s: float = 0.35

@onready var nav_agent: NavigationAgent2D = get_node_or_null("NavigationAgent2D")
@onready var detection_area: Area2D = get_node_or_null("DetectionArea")
@onready var anim: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")
@onready var body_collision: CollisionShape2D = get_node_or_null("CollisionShape2D")

@export var door_collision_radius_scale: float = 0.78
@export var door_collision_height_scale: float = 1.0

var state: State = State.PATROL
var player: Node = null
var last_player_pos: Vector2 = Vector2.ZERO
var _target_update_time_left: float = 0.0
var _last_target_pos: Vector2 = Vector2.ZERO
var _orig_collision_mask: int = 0
var _debug_collision_timer: float = 0.0
var _last_known_player_room_id: int = -1
var _door_override_active: bool = false
var _door_exit_target: Vector2 = Vector2.ZERO

@export var door_override_reach_dist: float = 12.0

var _stuck_last_pos: Vector2 = Vector2.ZERO
var _stuck_elapsed: float = 0.0
var _wall_escape_cooldown_left: float = 0.0
var _forced_patrol_room: Area2D = null
var _room_patrol_time_left: float = 0.0
var _player_room_mismatch_time_left: float = 0.0
var _capsule_orig_radius: float = 0.0
var _capsule_orig_height: float = 0.0
var _door_collision_mode_active: bool = false

func _disable_physical_collision_with_player(p: Node) -> void:
	if p == null:
		return
	if not (p is CollisionObject2D):
		return
	var player_layer: int = (p as CollisionObject2D).collision_layer
	if player_layer == 0:
		return
	var new_mask := collision_mask & (~player_layer)
	# Если все коллизии убьём — не делаем это.
	if new_mask == 0 and _orig_collision_mask != 0:
		return
	collision_mask = new_mask

func _restore_collision_mask() -> void:
	collision_mask = _orig_collision_mask

func _set_player(p: Node) -> void:
	player = p
	if not is_instance_valid(player):
		return

	last_player_pos = player.global_position
	_last_target_pos = player.global_position
	_target_update_time_left = 0.0
	state = State.CHASE
	_disable_physical_collision_with_player(player)
	_door_override_active = false
	_set_door_collision_mode(false)

	# Подписываемся на невидимость игрока, чтобы гарантированно прервать погоню.
	# Сигналы объявлены в `player.gd`.
	if player.has_signal("became_invisible") and not player.is_connected("became_invisible", Callable(self, "_on_player_became_invisible")):
		player.became_invisible.connect(_on_player_became_invisible)
	if player.has_signal("became_visible") and not player.is_connected("became_visible", Callable(self, "_on_player_became_visible")):
		player.became_visible.connect(_on_player_became_visible)

func _ready() -> void:
	if not is_in_group("maniac"):
		add_to_group("maniac")
	if nav_agent:
		nav_agent.max_speed = speed
	_orig_collision_mask = collision_mask

	# Подготавливаем коллизию маньяка для режима "проходим через дверь".
	if body_collision and body_collision.shape is CapsuleShape2D:
		var cap := body_collision.shape as CapsuleShape2D
		# Делаем копию ресурса, чтобы не затрагивать другие инстансы маньяка.
		body_collision.shape = cap.duplicate() as CapsuleShape2D
		_capsule_store_original_values()

	if detection_area:
		detection_area.body_entered.connect(_on_detection_body_entered)
		detection_area.body_exited.connect(_on_detection_body_exited)

	_start_patrol()

func _capsule_store_original_values() -> void:
	if not body_collision or not (body_collision.shape is CapsuleShape2D):
		return
	var cap := body_collision.shape as CapsuleShape2D
	_capsule_orig_radius = cap.radius
	_capsule_orig_height = cap.height

func _set_door_collision_mode(active: bool) -> void:
	if not body_collision or not (body_collision.shape is CapsuleShape2D):
		return
	if active == _door_collision_mode_active:
		return
	_door_collision_mode_active = active

	var cap := body_collision.shape as CapsuleShape2D
	if active:
		cap.radius = _capsule_orig_radius * door_collision_radius_scale
		cap.height = _capsule_orig_height * door_collision_height_scale
	else:
		cap.radius = _capsule_orig_radius
		cap.height = _capsule_orig_height

func _physics_process(delta: float) -> void:
	if _debug_collision_timer > 0.0:
		_debug_collision_timer -= delta

	# Отладка "залипания": если позиция не меняется достаточно долго,
	# принудительно переподбираем цель/навигацию.
	if _stuck_last_pos == Vector2.ZERO:
		_stuck_last_pos = global_position
	var moved_dist: float = global_position.distance_to(_stuck_last_pos)
	if moved_dist <= stuck_move_epsilon_px:
		_stuck_elapsed += delta
	else:
		_stuck_elapsed = 0.0
		_stuck_last_pos = global_position

	if _stuck_elapsed >= stuck_time_before_reset_s:
		_stuck_elapsed = 0.0
		_stuck_last_pos = global_position
		_door_override_active = false
		_set_door_collision_mode(false)
		if nav_agent:
			if state == State.PATROL:
				_pick_new_wander_point()
			elif state == State.CHASE and player != null:
				last_player_pos = player.global_position
				nav_agent.target_position = last_player_pos

	# Таймер "патруль целевой комнаты после двери" тикает только когда
	# маньяк уже НЕ в режиме прохода через дверь (_door_override_active).
	# Иначе он может быстро истечь прямо во время проталкивания через дверь.
	if state == State.PATROL and (not _door_override_active) and _room_patrol_time_left > 0.0:
		_room_patrol_time_left -= delta
		if _room_patrol_time_left <= 0.0:
			_room_patrol_time_left = 0.0
			_forced_patrol_room = null

	match state:
		State.PATROL:
			_process_patrol(delta)
		State.CHASE:
			_process_chase(delta)

	_play_anim_by_velocity()

# ---------- PATROL / CHASE ----------

func _process_patrol(delta: float) -> void:
	if not nav_agent:
		return

	nav_agent.max_speed = speed

	# Если маньяк открыл дверь, но должен гарантированно пройти через неё —
	# удерживаем цель на точке выхода.
	if _door_override_active:
		# достигли выхода или путь закончился — возвращаемся к патрулю
		if nav_agent.is_navigation_finished() or global_position.distance_to(_door_exit_target) <= door_override_reach_dist:
			_door_override_active = false
			_set_door_collision_mode(false)
			_start_patrol()
			return
		_follow_nav_agent(delta, speed)
		return

	if nav_agent.is_navigation_finished():
		_start_patrol()
	else:
		var next_pos := nav_agent.get_next_path_position()
		# Если путь есть, но следующий шаг не найден (например, после смены
		# навлинка дверь/связность изменилась), агент может "стоять".
		# В этом случае принудительно берём новую wander-точку.
		if next_pos == Vector2.ZERO:
			_pick_new_wander_point()
		else:
			_follow_nav_agent(delta, speed)

	if _detect_visible_player():
		state = State.CHASE

func _process_chase(delta: float) -> void:
	if not is_instance_valid(player):
		player = null
		_restore_collision_mask()
		state = State.PATROL
		_start_patrol()
		return

	# если игрок невидим, ведёмся так, будто его не видим
	if "is_invisible" in player and player.is_invisible:
		player = null
		_door_override_active = false
		_set_door_collision_mode(false)
		_restore_collision_mask()
		state = State.PATROL
		_start_patrol()
		return

	# Даже если сейчас мы "не видим" игрока (закрытая дверь гасит raycast),
	# DetectionArea всё ещё считает, что игрок рядом. Поэтому обновим
	# last-known комнату/позицию, чтобы маньяк мог правильно открывать
	# двери при повторном проталкивании.
	var pl_room_id: int = _get_room_id_at_point_stable(player.global_position)
	if pl_room_id != -1:
		_last_known_player_room_id = pl_room_id
	last_player_pos = player.global_position

	if not _can_see(player):
		# потеряли из виду — идём к последней известной позиции
		_door_override_active = false
		_set_door_collision_mode(false)
		if nav_agent:
			nav_agent.target_position = last_player_pos
		if nav_agent and nav_agent.is_navigation_finished():
			state = State.PATROL
			_start_patrol()
		_follow_nav_agent(delta, speed)
		return

	# видим игрока
	var player_room_id: int = _get_room_id_at_point_stable(player.global_position)
	var current_room_id: int = _get_room_id_at_point_stable(global_position)
	if player_room_id != -1:
		_last_known_player_room_id = player_room_id
	last_player_pos = player.global_position

	if global_position.distance_to(player.global_position) <= attack_range:
		if player.has_method("take_damage"):
			player.take_damage(1, true)
		_door_override_active = false
		_set_door_collision_mode(false)
		state = State.PATROL
		_start_patrol()
		return

	# Если игрок ушёл в другую комнату, ведёмся к той комнате через дверь.
	# Это соответствует твоему требованию "он видел куда забегает игрок".
	if current_room_id != -1 and player_room_id != -1 and current_room_id != player_room_id:
		_player_room_mismatch_time_left += delta
		var door_info: Dictionary = _find_door_exit_between_rooms(current_room_id, player_room_id)
		if door_info.size() > 0:
			var door_node: Door = door_info.get("door")
			var exit_point: Vector2 = door_info.get("exit_point")
			var door_dist: float = door_info.get("dist", INF)
			if door_node != null:
				# Чтобы не “перепрыгивать” в следующую комнату,
				# когда игрок просто пробежал рядом с дверью,
				# открываем дверь только если мы уже достаточно близко к ней.
				if _player_room_mismatch_time_left < 0.35:
					pass
				elif door_dist > door_open_attempt_max_dist_px:
					# Продолжаем погоню как обычно (агент попробует
					# выйти к игроку через навигацию).
					pass
				else:
					# Открываем дверь и переводим агента на точку внутри следующей комнаты.
					door_node.open_for_maniac(self)
					set_door_exit_target(exit_point, true)
					return
	else:
		_player_room_mismatch_time_left = 0.0

	if nav_agent:
		nav_agent.max_speed = chase_speed
		_target_update_time_left -= delta
		if _target_update_time_left <= 0.0:
			_last_target_pos = player.global_position
			nav_agent.target_position = _last_target_pos
			_target_update_time_left = target_update_interval
	_follow_nav_agent(delta, chase_speed)

# ---------- Navigation ----------

func _follow_nav_agent(delta: float, spd: float) -> void:
	if not nav_agent:
		return
	var next_pos: Vector2 = nav_agent.get_next_path_position()
	if next_pos == Vector2.ZERO:
		return
	var delta_pos: Vector2 = next_pos - global_position
	if delta_pos.length() <= 0.001:
		return
	var desired_velocity: Vector2 = delta_pos.normalized() * spd
	# Плавное изменение скорости убирает "прилипание" у цели
	velocity = velocity.move_toward(desired_velocity, acceleration * delta)
	move_and_slide()

	# Анти-залипание у стен/коллизий:
	# если мы близко к следующей нав-точке и уже "почти не двигаемся" по времени,
	# делаем небольшой шаг от нормали поверхности коллизии.
	if debug_collision_prints and _wall_escape_cooldown_left > 0.0:
		_wall_escape_cooldown_left -= delta
	var collision := get_last_slide_collision()
	if collision != null:
		var dist_to_next: float = global_position.distance_to(next_pos)
		if dist_to_next <= wall_escape_distance_to_target_px and _stuck_elapsed >= stuck_time_before_reset_s * 0.7 and _wall_escape_cooldown_left <= 0.0:
			var n: Vector2 = collision.get_normal()
			if n.length() > 0.001:
				velocity = n * wall_escape_speed
				move_and_slide()
				_wall_escape_cooldown_left = wall_escape_cooldown_s

	# Отладка: если маньяк встаёт у препятствия, печатаем коллайдер.
	if debug_collision_prints and state == State.PATROL and _debug_collision_timer <= 0.0:
		var collision_dbg: KinematicCollision2D = get_last_slide_collision()
		if collision_dbg != null:
			var col_obj: Object = collision_dbg.get_collider()
			# Печатаем только когда мы близки к нав. цели — меньше мусора в консоли.
			var t: Vector2 = nav_agent.target_position
			var dist_to_target: float = global_position.distance_to(t)
			if dist_to_target <= debug_collision_distance_to_target:
				if col_obj != null:
					if col_obj is Door:
						var d: Door = col_obj as Door
						print(
							"[Maniac] collision door:", d.name,
							" door_id:", d.door_id,
							" is_open:", d.is_open,
							" at:", collision_dbg.get_position()
						)
					else:
						print("[Maniac] collision:", col_obj.name, " type:", col_obj.get_class(), " at:", collision_dbg.get_position())
				else:
					print("[Maniac] collision: null at:", collision_dbg.get_position())
				_debug_collision_timer = debug_collision_cooldown

func _start_patrol() -> void:
	_pick_new_wander_point()

func set_door_exit_target(exit_point: Vector2, use_chase_speed: bool = false) -> void:
	if not nav_agent:
		return
	_door_override_active = true
	_set_door_collision_mode(true)
	_door_exit_target = exit_point
	state = State.PATROL
	# Ставим целевую точку на выход через открытую дверь.
	var spd: float = chase_speed if use_chase_speed else speed
	nav_agent.max_speed = spd
	# Если точка выхода оказалась недостижимой (иногда бывает из-за
	# таймингов обновления NavigationLink2D или из-за небольшой ошибки
	# положения), попробуем сдвинуть её немного дальше по направлению.
	var nav_map: RID = nav_agent.get_navigation_map()
	var navigation_layers: int = 1
	var chosen_exit: Vector2 = exit_point
	if nav_map != RID():
		var dir: Vector2 = (exit_point - global_position)
		if dir.length() > 0.001:
			dir = dir.normalized()
		else:
			dir = Vector2.RIGHT

		var candidates: Array[Vector2] = [
			exit_point,
			exit_point + dir * 12.0,
			exit_point + dir * 24.0,
			exit_point + dir * 36.0
		]
		for c in candidates:
			var path: PackedVector2Array = NavigationServer2D.map_get_path(
				nav_map,
				global_position,
				c,
				true,
				navigation_layers
			)
			if path.size() > 1:
				chosen_exit = c
				break

	_door_exit_target = chosen_exit
	# Фиксируем комнату для патруля после двери.
	# Надежнее брать комнату из точки выхода (exit_point), а не из last_known,
	# потому что player мог отойти/перестать быть видимым сразу после открытия.
	var forced_room_id: int = _get_room_id_at_point_stable(chosen_exit)

	# Если выход оказался на границе полигона — пробуем сдвинуть точку
	# чуть дальше по направлению “в комнату”.
	if forced_room_id == -1:
		var dir_to_exit: Vector2 = chosen_exit - global_position
		if dir_to_exit.length() > 0.001:
			dir_to_exit = dir_to_exit.normalized()
		else:
			dir_to_exit = Vector2.RIGHT
		var tries: Array[float] = [6.0, 12.0, 18.0, 24.0]
		for d in tries:
			var id_try: int = _get_room_id_at_point_stable(chosen_exit + dir_to_exit * d)
			if id_try != -1:
				forced_room_id = id_try
				break

	if forced_room_id != -1:
		_forced_patrol_room = _get_room_area_by_id(forced_room_id)
	else:
		# fallback: используем последнюю известную комнату игрока
		if _last_known_player_room_id != -1:
			_forced_patrol_room = _get_room_area_by_id(_last_known_player_room_id)
		else:
			_forced_patrol_room = _get_room_at_point(chosen_exit)

	_room_patrol_time_left = randf_range(room_patrol_min_time_s, room_patrol_max_time_s)
	nav_agent.target_position = chosen_exit
	# На случай, если линк включился только что — принудительно перезапросим путь.
	refresh_navigation(false)

func is_targeting_door(door_node: Door) -> bool:
	# Дверь будет открываться по триггеру только если маньяк уже
	# принял решение "протиснуться" через именно эту дверь.
	if not _door_override_active:
		return false
	if door_node == null:
		return false
	if door_node.nav_a == null or door_node.nav_b == null:
		return false

	# Door.gd дополнительно смещает exit_point внутрь комнаты на ~16px,
	# поэтому даем запас по расстоянию.
	var tol: float = max(door_override_reach_dist * 3.0, 40.0)
	var a_pos: Vector2 = door_node.nav_a.global_position
	var b_pos: Vector2 = door_node.nav_b.global_position
	return _door_exit_target.distance_to(a_pos) <= tol or _door_exit_target.distance_to(b_pos) <= tol

func can_open_door_from_trigger(door_node: Door) -> bool:
	# Открываем дверь из триггера, если:
	# - маньяк не невидим для логики
	# - маньяк/игрок в разных комнатах
	# - конкретно эта дверь соединяет комнаты (room_id по маркерам A/B)
	if door_node == null:
		return false
	if door_node.nav_a == null or door_node.nav_b == null:
		return false
	if not is_instance_valid(player):
		return false
	if "is_invisible" in player and player.is_invisible:
		return false

	# Если мы уже “идём через” эту дверь — пусть триггер не мешает.
	if _door_override_active:
		var ok_override: bool = is_targeting_door(door_node)
		if debug_collision_prints:
			print("[Maniac] door trigger override:", door_node.name, " ok:", ok_override, " state:", state)
		return ok_override

	# Комнаты для маркеров двери лучше брать так же, как в _find_door_exit_between_rooms:
	# если точка на границе — пробуем смещения.
	var a_id: int = _get_room_id_at_point(door_node.nav_a.global_position)
	var b_id: int = _get_room_id_at_point(door_node.nav_b.global_position)
	if a_id == -1:
		var offs_a: Array[Vector2] = [Vector2(6, 0), Vector2(-6, 0), Vector2(0, 6), Vector2(0, -6)]
		for off in offs_a:
			var id_try: int = _get_room_id_at_point(door_node.nav_a.global_position + off)
			if id_try != -1:
				a_id = id_try
				break
	if b_id == -1:
		var offs_b: Array[Vector2] = [Vector2(6, 0), Vector2(-6, 0), Vector2(0, 6), Vector2(0, -6)]
		for off in offs_b:
			var id_try2: int = _get_room_id_at_point(door_node.nav_b.global_position + off)
			if id_try2 != -1:
				b_id = id_try2
				break
	if a_id == -1 or b_id == -1:
		return false

	# Ищем “возможную текущую комнату” маньяка и “возможную комнату игрока”
	# с небольшими оффсетами, чтобы не зависеть от того, попали ли мы в
	# точку на границе полигонов.
	var room_offsets: Array[Vector2] = [Vector2.ZERO, Vector2(6, 0), Vector2(-6, 0), Vector2(0, 6), Vector2(0, -6)]

	var current_room_candidates: Array[int] = []
	for off in room_offsets:
		var rid: int = _get_room_id_at_point(global_position + off)
		if rid != -1 and not current_room_candidates.has(rid):
			current_room_candidates.append(rid)
	# fallback
	if current_room_candidates.is_empty():
		var rid2: int = _get_room_id_at_point_stable(global_position)
		if rid2 != -1:
			current_room_candidates.append(rid2)

	var player_room_candidates: Array[int] = []
	if _last_known_player_room_id != -1 and not player_room_candidates.has(_last_known_player_room_id):
		player_room_candidates.append(_last_known_player_room_id)
	for off in room_offsets:
		var ridp: int = _get_room_id_at_point(player.global_position + off)
		if ridp != -1 and not player_room_candidates.has(ridp):
			player_room_candidates.append(ridp)

	if current_room_candidates.is_empty() or player_room_candidates.is_empty():
		return false

	for cur_id in current_room_candidates:
		for pl_id in player_room_candidates:
			if cur_id == pl_id:
				continue
			var connects: bool = (a_id == cur_id and b_id == pl_id) or (b_id == cur_id and a_id == pl_id)
			if connects:
				return true

	return false

func _find_door_exit_between_rooms(from_room_id: int, to_room_id: int) -> Dictionary:
	var best: Dictionary = {}
	var best_dist: float = INF

	for door in get_tree().get_nodes_in_group("doors"):
		if not (door is Door):
			continue
		var door_node: Door = door as Door
		if door_node.nav_a == null or door_node.nav_b == null:
			continue

		var a_pos: Vector2 = door_node.nav_a.global_position
		var b_pos: Vector2 = door_node.nav_b.global_position

		var a_id: int = _get_room_id_at_point(a_pos)
		var b_id: int = _get_room_id_at_point(b_pos)

		# Если маркеры A/B лежат прямо на границе RoomArea2D,
		# point-in-polygon может вернуть -1. Тогда пробуем небольшой смещённый поиск.
		if a_id == -1:
			var offs: Array[Vector2] = [Vector2(6, 0), Vector2(-6, 0), Vector2(0, 6), Vector2(0, -6)]
			for off in offs:
				var id_try: int = _get_room_id_at_point(a_pos + off)
				if id_try != -1:
					a_id = id_try
					break
		if b_id == -1:
			var offs2: Array[Vector2] = [Vector2(6, 0), Vector2(-6, 0), Vector2(0, 6), Vector2(0, -6)]
			for off in offs2:
				var id_try2: int = _get_room_id_at_point(b_pos + off)
				if id_try2 != -1:
					b_id = id_try2
					break
		if a_id == -1 or b_id == -1:
			continue

		var connects := (a_id == from_room_id and b_id == to_room_id) or (b_id == from_room_id and a_id == to_room_id)
		if not connects:
			continue

		var entry_pos: Vector2 = a_pos if a_id == from_room_id else b_pos
		var exit_pos: Vector2 = a_pos if a_id == to_room_id else b_pos

		var dist: float = global_position.distance_to(entry_pos)
		if dist < best_dist:
			best_dist = dist
			best = {
				"door": door_node,
			"entry_pos": entry_pos,
				"exit_point": exit_pos,
			"dist": dist,
			}

	return best

func _pick_new_wander_point() -> void:
	if not nav_agent:
		return
	# Без зависимости от наличия узла Navigation2D в сцене.
	# Берём случайную точку по текущей navigation map агента.
	var nav_map: RID = nav_agent.get_navigation_map()
	if nav_map == RID():
		return
	# 1 - навигационный слой, на котором сейчас работает маньяк/линки (как у агента).
	var navigation_layers: int = 1

	# Ограничиваем выбор точек:
	# - если недавно прошли дверь и задана "целeвая комната", бродим только в ней;
	# - иначе — бродим в текущей комнате по RoomArea2D.
	var current_room: Area2D = null
	if _room_patrol_time_left > 0.0 and _forced_patrol_room != null:
		current_room = _forced_patrol_room
	else:
		current_room = _get_room_at_point(global_position)

	var max_attempts: int = room_pick_attempts
	for i in range(max_attempts):
		var rnd_point: Vector2 = NavigationServer2D.map_get_random_point(nav_map, navigation_layers, true)
		if rnd_point == Vector2.ZERO:
			continue

		if current_room != null and not _is_point_inside_room(current_room, rnd_point):
			continue

		# Важно: выбираем ТОЛЬКО достижимую точку, иначе агент может "встать".
		var path: PackedVector2Array = NavigationServer2D.map_get_path(
			nav_map,
			global_position,
			rnd_point,
			true,
			navigation_layers
		)
		if path.size() > 1:
			nav_agent.target_position = rnd_point
			return

	# fallback
	nav_agent.target_position = global_position

func _get_room_at_point(world_point: Vector2) -> Area2D:
	var rooms: Array = get_tree().get_nodes_in_group(rooms_group_name)
	for r in rooms:
		if not (r is Area2D):
			continue
		var room_area: Area2D = r as Area2D
		if _is_point_inside_room(room_area, world_point):
			return room_area
	return null

func _is_point_inside_room(room_area: Area2D, world_point: Vector2) -> bool:
	# Проверяем попадание точки в CollisionPolygon2D из комнаты.
	var polys: Array = []
	_collect_collision_polygons(room_area, polys)
	for p in polys:
		if not (p is CollisionPolygon2D):
			continue
		var cp: CollisionPolygon2D = p as CollisionPolygon2D
		var poly: PackedVector2Array = cp.polygon
		if poly.size() < 3:
			continue
		# Приводим точку в локальную систему координат конкретного CollisionPolygon2D
		var local_point: Vector2 = cp.to_local(world_point)
		if Geometry2D.is_point_in_polygon(local_point, poly):
			return true
	return false

func _get_room_id_from_area(room_area: Area2D) -> int:
	if room_area == null:
		return -1
	if not room_area.has_meta(room_id_meta_key):
		return -1
	var v: Variant = room_area.get_meta(room_id_meta_key)
	if v == null:
		return -1
	return int(v)

func _get_room_area_by_id(id: int) -> Area2D:
	if id < 0:
		return null
	var rooms: Array = get_tree().get_nodes_in_group(rooms_group_name)
	for r in rooms:
		if not (r is Area2D):
			continue
		var room_area: Area2D = r as Area2D
		if _get_room_id_from_area(room_area) == id:
			return room_area
	return null

func _get_room_id_at_point(world_point: Vector2) -> int:
	var room_area: Area2D = _get_room_at_point(world_point)
	if room_area == null:
		return -1
	return _get_room_id_from_area(room_area)

func _get_room_id_at_point_stable(world_point: Vector2) -> int:
	# RoomArea может содержать точку на границе. Тогда point-in-polygon
	# иногда возвращает -1. Для AI это критично — подстрахуем смещениями.
	var id: int = _get_room_id_at_point(world_point)
	if id != -1:
		return id
	var offs: Array[Vector2] = [Vector2(6, 0), Vector2(-6, 0), Vector2(0, 6), Vector2(0, -6)]
	for off in offs:
		var id_try: int = _get_room_id_at_point(world_point + off)
		if id_try != -1:
			return id_try
	return -1

func _collect_collision_polygons(node: Node, out: Array) -> void:
	for c in node.get_children():
		if c is CollisionPolygon2D:
			out.append(c)
		_collect_collision_polygons(c, out)

# ---------- Detection / vision ----------

func _on_detection_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_set_player(body)

func _on_detection_body_exited(body: Node) -> void:
	if body == player:
		player = null
		_restore_collision_mask()
		_door_override_active = false
		_set_door_collision_mode(false)

func _detect_visible_player() -> bool:
	if not is_instance_valid(player):
		return false
	# не видим игрока во время невидимости
	if "is_invisible" in player and player.is_invisible:
		return false
	return _can_see(player)

func _can_see(target: Node) -> bool:
	if target == null:
		return false
	# дистанция
	var to_target = target.global_position - global_position
	if to_target.length() > detection_radius:
		return false
	# луч до игрока — стены/двери должны блокировать
	var space_state = get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(global_position, target.global_position)
	var result = space_state.intersect_ray(query)
	if result.is_empty():
		return false

	var collider: Object = result.get("collider")
	if collider == null:
		return false

	# 1) Если луч уперся в закрытую дверь — видимости нет.
	var door_node: Door = null
	if collider is Door:
		door_node = collider
	elif collider is Node:
		var p := (collider as Node).get_parent()
		if p is Door:
			door_node = p as Door
	if door_node != null and not door_node.is_open:
		return false

	# 2) Если луч попал в игрока (или в дочерние коллайдеры игрока) — видим.
	if collider is Node:
		var hit_node := collider as Node
		# прямой матч
		if hit_node == target:
			return true
		# или матч по группе/родителям
		if hit_node.is_in_group("player"):
			return true
		var ancestor := hit_node.get_parent()
		while ancestor != null:
			if ancestor == target or ancestor.is_in_group("player"):
				return true
			ancestor = ancestor.get_parent()
		return false

	# 3) fallback
	return collider == target

# ---------- Navigation2D helper ----------

func _get_navigation2d():
	var root = get_tree().get_current_scene()
	if root == null:
		return null
	var nav = root.get_node_or_null("Navigation2D")
	if nav:
		return nav
	return _find_navigation2d_recursive(root)

func _find_navigation2d_recursive(node):
	if node == null:
		return null
	if node.get_class() == "Navigation2D":
		return node
	for child in node.get_children():
		var found = _find_navigation2d_recursive(child)
		if found:
			return found
	return null

# ---------- Реакция, когда игрок стал видимым рядом ----------

func on_player_revealed(p: Node) -> void:
	_set_player(p)

func _on_player_became_invisible() -> void:
	# Не преследуем игрока напрямую, но если мы уже видели, куда он заходит,
	# то продолжаем движение в последнюю известную комнату.
	var target_room_id: int = _last_known_player_room_id
	player = null
	_restore_collision_mask()
	state = State.PATROL

	if target_room_id != -1:
		var cur_room_id: int = _get_room_id_at_point(global_position)
		if cur_room_id != -1 and cur_room_id != target_room_id:
			var door_info: Dictionary = _find_door_exit_between_rooms(cur_room_id, target_room_id)
			if door_info.size() > 0:
				var door_node: Door = door_info.get("door")
				var exit_point: Vector2 = door_info.get("exit_point")
				if door_node != null:
					door_node.open_for_maniac(self)
					set_door_exit_target(exit_point, true)
					return

	_start_patrol()

func _on_player_became_visible() -> void:
	# Ничего не делаем: `player.gd` уже уведомляет маньяков напрямую через `on_player_revealed`.
	pass

# Door opens/links update are applied with defer / after physics.
# When a door becomes traversable while we're PATROLLING, we need to force
# NavigationAgent2D to re-query a path to its current target.
func refresh_navigation(repick_wander: bool = true) -> void:
	if not nav_agent:
		return

	var t: Vector2 = nav_agent.target_position
	if t == Vector2.ZERO:
		t = global_position

	# Если мы в PATROL, то цель могла стать недостижимой при закрытой двери.
	# Поэтому при открытии двери всегда надо переподобрать wander-точку.
	var should_repick := repick_wander and state == State.PATROL
	call_deferred("_refresh_navigation_deferred", should_repick, t)

func _refresh_navigation_deferred(repick_wander: bool, t: Vector2) -> void:
	if not nav_agent:
		return

	# NavigationLink changes usually take effect after the next physics frame.
	await get_tree().physics_frame
	if not nav_agent:
		return

	if repick_wander:
		# Если мы патрулируем и дверь стала доступной, но наша текущая wander-цель
		# была недостижима при закрытой двери — выбираем новую.
		_pick_new_wander_point()
		return

	# Если мы в chase/когда репик не нужен — принудительно пересобираем путь.
	nav_agent.target_position = t + Vector2(0.1, 0.0)
	nav_agent.target_position = t

# ---------- Animation ----------

func _play_anim_by_velocity() -> void:
	if anim == null:
		return
	if velocity.length() < 1.0:
		if anim.sprite_frames and anim.sprite_frames.has_animation("idle_down"):
			anim.play("idle_down")
		return
	if anim.sprite_frames and anim.sprite_frames.has_animation("walk_down"):
		anim.play("walk_down")
