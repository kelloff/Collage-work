extends CharacterBody2D

enum State { PATROL, CHASE, INVESTIGATE }

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
@export var attack_anim_duration_s: float = 0.35
@export var attack_move_speed_while_anim: float = 0.0
@export var attack_hit_frame_index: int = 11
@export var attack_recovery_s: float = 0.15

@export var hunt_ping_interval_s: float = 30.0
@export var hunt_enabled: bool = true
@export var hunt_arrival_dist_px: float = 48.0
@export var investigate_points_min: int = 4
@export var investigate_points_max: int = 8
@export var arrive_last_seen_dist_px: float = 72.0
@export var debug_intel_logs: bool = true
## Во время обследования комнаты не открывать двери «мимо хода» (навводит к порогу случайной точки).
@export var door_trigger_suppress_in_investigate: bool = true
## В погоне с прямой видимостью и вплотную к игроку — не цеплять соседние двери триггером.
@export var door_trigger_suppress_when_chasing_close_px: float = 96.0
@export var attack_swing_sfx: AudioStream
@export var footstep_sfx: AudioStream
@export var ambient_sfx: AudioStream
@export var footstep_min_interval_s: float = 0.32
@export var ambient_interval_min_s: float = 10.0
@export var ambient_interval_max_s: float = 22.0

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
## Последняя комната игрока, куда «зашли» (обновляется в погоне по видимости) — обследование вслепую.
var _committed_search_room_id: int = -1
var _intel_travel_active: bool = false
var _intel_room_id: int = -1
var _investigate_room_area: Area2D = null
var _investigate_points_remaining: int = 0
var _door_override_active: bool = false
var _door_exit_target: Vector2 = Vector2.ZERO

@export var door_override_reach_dist: float = 12.0

var _stuck_last_pos: Vector2 = Vector2.ZERO
var _stuck_elapsed: float = 0.0
var _wall_escape_cooldown_left: float = 0.0
var _forced_patrol_room: Area2D = null
var _room_patrol_time_left: float = 0.0
var _capsule_orig_radius: float = 0.0
var _capsule_orig_height: float = 0.0
var _door_collision_mode_active: bool = false
var _last_facing_dir: Vector2 = Vector2.DOWN
var _attack_anim_time_left: float = 0.0
var _attack_damage_applied: bool = false
var _is_attacking: bool = false
var _attack_recovery_left: float = 0.0
var _collision_exception_player: PhysicsBody2D = null

var _hunt_ping_accum: float = 0.0
var _footstep_cooldown: float = 0.0
var _ambient_countdown: float = 0.0
var _sfx_short: AudioStreamPlayer2D
var _sfx_ambient: AudioStreamPlayer2D

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

func _set_player_collision_passthrough(p: Node, enabled: bool) -> void:
	# Двустороннее исключение коллизии, чтобы игрок и маньяк проходили друг через друга.
	if p == null or not (p is PhysicsBody2D):
		return
	var pb := p as PhysicsBody2D
	if enabled:
		add_collision_exception_with(pb)
		pb.add_collision_exception_with(self)
		_collision_exception_player = pb
	else:
		remove_collision_exception_with(pb)
		pb.remove_collision_exception_with(self)
		if _collision_exception_player == pb:
			_collision_exception_player = null

func _reset_attack_state(start_recovery: bool = false) -> void:
	_is_attacking = false
	_attack_anim_time_left = 0.0
	_attack_damage_applied = false
	if start_recovery:
		_attack_recovery_left = max(_attack_recovery_left, attack_recovery_s)

func _set_player(p: Node) -> void:
	player = p
	if not is_instance_valid(player):
		return

	_clear_intel_travel()
	_investigate_room_area = null
	_investigate_points_remaining = 0
	last_player_pos = player.global_position
	_last_target_pos = player.global_position
	_target_update_time_left = 0.0
	state = State.CHASE
	_disable_physical_collision_with_player(player)
	_set_player_collision_passthrough(player, true)
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
	if anim:
		if not anim.is_connected("frame_changed", Callable(self, "_on_anim_frame_changed")):
			anim.frame_changed.connect(_on_anim_frame_changed)
		if not anim.is_connected("animation_finished", Callable(self, "_on_anim_finished")):
			anim.animation_finished.connect(_on_anim_finished)

	_sfx_short = AudioStreamPlayer2D.new()
	_sfx_short.name = "ManiacSfxShort"
	add_child(_sfx_short)
	_sfx_ambient = AudioStreamPlayer2D.new()
	_sfx_ambient.name = "ManiacSfxAmbient"
	_sfx_ambient.max_distance = 520.0
	add_child(_sfx_ambient)
	_reset_ambient_countdown()

	_start_patrol()

func _reset_ambient_countdown() -> void:
	_ambient_countdown = randf_range(ambient_interval_min_s, ambient_interval_max_s)

func _play_short_sfx(stream: AudioStream) -> void:
	if _sfx_short == null or stream == null:
		return
	_sfx_short.stream = stream
	_sfx_short.play()

func _resolve_hunt_player() -> Node:
	for n in get_tree().get_nodes_in_group("player"):
		if n != null and is_instance_valid(n):
			return n
	return null

func _clear_intel_travel() -> void:
	_intel_travel_active = false
	_intel_room_id = -1

## Пока идёт анимация удара, `_process_chase` не вызывается — без этого «последняя точка» не двигается вместе с игроком.
func _update_chase_memory_from_player() -> void:
	if state != State.CHASE or not is_instance_valid(player):
		return
	last_player_pos = player.global_position
	var rid: int = _get_room_id_at_point_stable(player.global_position)
	if rid != -1:
		_last_known_player_room_id = rid
		_committed_search_room_id = rid
	if nav_agent:
		nav_agent.target_position = last_player_pos

func _log_intel(tag: String, room_id: int, world_pos: Vector2) -> void:
	if not debug_intel_logs:
		return
	var rid_str: String = str(room_id) if room_id >= 0 else "?"
	print("[Maniac/intel] %s | room_id=%s | pos=(%.0f, %.0f)" % [tag, rid_str, world_pos.x, world_pos.y])

func _pick_nav_point_inside_room(room_area: Area2D) -> bool:
	if nav_agent == null or room_area == null:
		return false
	var nav_map: RID = nav_agent.get_navigation_map()
	if nav_map == RID():
		return false
	var navigation_layers: int = 1
	for _i in range(room_pick_attempts):
		var rnd_point: Vector2 = NavigationServer2D.map_get_random_point(nav_map, navigation_layers, true)
		if rnd_point == Vector2.ZERO:
			continue
		if not _is_point_inside_room(room_area, rnd_point):
			continue
		var path: PackedVector2Array = NavigationServer2D.map_get_path(
			nav_map,
			global_position,
			rnd_point,
			true,
			navigation_layers
		)
		if path.size() > 1:
			nav_agent.target_position = rnd_point
			return true
	return false

func _try_pick_intel_travel_to_room(room_id: int) -> bool:
	var area: Area2D = _get_room_area_by_id(room_id)
	if area == null:
		return false
	return _pick_nav_point_inside_room(area)

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
	if _attack_recovery_left > 0.0:
		_attack_recovery_left = max(0.0, _attack_recovery_left - delta)
	if _footstep_cooldown > 0.0:
		_footstep_cooldown = max(0.0, _footstep_cooldown - delta)
	if _attack_anim_time_left > 0.0:
		_attack_anim_time_left = max(0.0, _attack_anim_time_left - delta)
		# While attack animation is active, pause (or heavily slow) movement
		# so the player has a chance to escape after a hit.
		if attack_move_speed_while_anim <= 0.0:
			velocity = Vector2.ZERO
		else:
			if velocity.length() > attack_move_speed_while_anim:
				velocity = velocity.normalized() * attack_move_speed_while_anim
			velocity = velocity.move_toward(Vector2.ZERO, acceleration * delta)
		move_and_slide()
		_play_anim_by_velocity()
		_update_chase_memory_from_player()
		return
	elif _is_attacking:
		# Failsafe: если по какой-то причине animation_finished не пришёл
		# (переключение сцены/анимации, пауза и т.п.), не оставляем ИИ в вечной атаке.
		_reset_attack_state(true)

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
			elif state == State.INVESTIGATE and _investigate_room_area != null:
				_pick_nav_point_inside_room(_investigate_room_area)
			elif state == State.CHASE and player != null:
				last_player_pos = player.global_position
				nav_agent.target_position = last_player_pos

	# Таймер "патруль целевой комнаты после двери" тикает только когда
	# маньяк уже НЕ в режиме прохода через дверь (_door_override_active).
	# Иначе он может быстро истечь прямо во время проталкивания через дверь.
	if (state == State.PATROL or state == State.INVESTIGATE) and (not _door_override_active) and _room_patrol_time_left > 0.0:
		_room_patrol_time_left -= delta
		if _room_patrol_time_left <= 0.0:
			_room_patrol_time_left = 0.0
			_forced_patrol_room = null

	match state:
		State.PATROL:
			_process_patrol(delta)
		State.CHASE:
			_process_chase(delta)
		State.INVESTIGATE:
			_process_investigate(delta)

	_tick_maniac_ambient_sfx(delta)
	_play_anim_by_velocity()

# ---------- PATROL / CHASE ----------

func _tick_maniac_ambient_sfx(delta: float) -> void:
	if ambient_sfx == null or _sfx_ambient == null:
		return
	if state != State.PATROL and state != State.CHASE and state != State.INVESTIGATE:
		return
	if _attack_anim_time_left > 0.0 or _is_attacking:
		return
	if _door_override_active:
		return
	_ambient_countdown -= delta
	if _ambient_countdown <= 0.0:
		_reset_ambient_countdown()
		if not _sfx_ambient.playing:
			_sfx_ambient.stream = ambient_sfx
			_sfx_ambient.play()

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

	if hunt_enabled and _intel_travel_active:
		var hp_intel: Node = _resolve_hunt_player()
		if hp_intel != null and _can_see(hp_intel):
			_clear_intel_travel()
			_hunt_ping_accum = 0.0
			_set_player(hp_intel)
			state = State.CHASE
			return
		var arrived_intel: bool = nav_agent.is_navigation_finished() or global_position.distance_to(nav_agent.target_position) <= hunt_arrival_dist_px
		if arrived_intel:
			var saved_rid: int = _intel_room_id
			_clear_intel_travel()
			_hunt_ping_accum = 0.0
			if saved_rid != -1:
				_log_intel("прибыл_в_комнату", saved_rid, global_position)
				var ra: Area2D = _get_room_area_by_id(saved_rid)
				if ra != null:
					_forced_patrol_room = ra
					_room_patrol_time_left = randf_range(room_patrol_min_time_s, room_patrol_max_time_s)
			_pick_new_wander_point()
		else:
			_follow_nav_agent(delta, speed)
		if _detect_visible_player():
			_clear_intel_travel()
			state = State.CHASE
		return

	if hunt_enabled and not _intel_travel_active:
		_hunt_ping_accum += delta
		if _hunt_ping_accum >= hunt_ping_interval_s:
			_hunt_ping_accum = 0.0
			var hp_radar: Node = _resolve_hunt_player()
			if hp_radar != null:
				var r_id: int = _get_room_id_at_point_stable(hp_radar.global_position)
				_log_intel("радар", r_id, hp_radar.global_position)
				if r_id != -1 and _try_pick_intel_travel_to_room(r_id):
					_intel_travel_active = true
					_intel_room_id = r_id
					refresh_navigation(false)
					_follow_nav_agent(delta, speed)
					if _detect_visible_player():
						_clear_intel_travel()
						state = State.CHASE
					return
				# Нет полигона комнаты или путь не строится — идём к точке на карте.
				nav_agent.target_position = hp_radar.global_position
				_intel_travel_active = true
				_intel_room_id = -1
				refresh_navigation(false)
				_follow_nav_agent(delta, speed)
				if _detect_visible_player():
					_clear_intel_travel()
					state = State.CHASE
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

func _start_investigate_room(room_id: int) -> void:
	if not nav_agent:
		return
	var area: Area2D = _get_room_area_by_id(room_id)
	if area == null:
		_start_patrol()
		return
	_clear_intel_travel()
	_investigate_room_area = area
	_investigate_points_remaining = randi_range(investigate_points_min, investigate_points_max)
	state = State.INVESTIGATE
	_log_intel("обследование_начало", room_id, global_position)
	if not _pick_nav_point_inside_room(_investigate_room_area):
		_investigate_room_area = null
		_investigate_points_remaining = 0
		state = State.PATROL
		_start_patrol()

func _process_investigate(delta: float) -> void:
	if not nav_agent:
		return
	nav_agent.max_speed = speed

	if _door_override_active:
		if nav_agent.is_navigation_finished() or global_position.distance_to(_door_exit_target) <= door_override_reach_dist:
			_door_override_active = false
			_set_door_collision_mode(false)
			_investigate_room_area = null
			_start_patrol()
			return
		_follow_nav_agent(delta, speed)
		return

	if hunt_enabled:
		_hunt_ping_accum += delta
		if _hunt_ping_accum >= hunt_ping_interval_s:
			_hunt_ping_accum = 0.0
			var hp_r: Node = _resolve_hunt_player()
			if hp_r != null:
				var r_id2: int = _get_room_id_at_point_stable(hp_r.global_position)
				_log_intel("радар", r_id2, hp_r.global_position)
				if r_id2 != -1 and _try_pick_intel_travel_to_room(r_id2):
					_intel_travel_active = true
					_intel_room_id = r_id2
					_investigate_room_area = null
					state = State.PATROL
					refresh_navigation(false)
					return
				nav_agent.target_position = hp_r.global_position
				_intel_travel_active = true
				_intel_room_id = -1
				_investigate_room_area = null
				state = State.PATROL
				refresh_navigation(false)
				return

	var vis_p: Node = _resolve_hunt_player()
	if vis_p != null and _can_see(vis_p):
		_investigate_room_area = null
		_investigate_points_remaining = 0
		_set_player(vis_p)
		state = State.CHASE
		return

	var dist_t: float = global_position.distance_to(nav_agent.target_position)
	var arrived_inv: bool = nav_agent.is_navigation_finished() or dist_t <= hunt_arrival_dist_px
	if arrived_inv:
		_investigate_points_remaining -= 1
		if _investigate_points_remaining > 0 and _investigate_room_area != null:
			if not _pick_nav_point_inside_room(_investigate_room_area):
				_investigate_points_remaining = 0
		if _investigate_points_remaining <= 0:
			var end_rid: int = -1
			if _investigate_room_area != null:
				end_rid = _get_room_id_from_area(_investigate_room_area)
			_log_intel("обследование_конец", end_rid, global_position)
			_investigate_room_area = null
			state = State.PATROL
			_forced_patrol_room = null
			_room_patrol_time_left = 0.0
			_start_patrol()
			return
		return
	_follow_nav_agent(delta, speed)

func _process_chase(delta: float) -> void:
	if not is_instance_valid(player):
		if is_instance_valid(_collision_exception_player):
			_set_player_collision_passthrough(_collision_exception_player, false)
		player = null
		_restore_collision_mask()
		_reset_attack_state(true)
		state = State.PATROL
		_start_patrol()
		return

	# если игрок невидим, ведёмся так, будто его не видим
	if "is_invisible" in player and player.is_invisible:
		_set_player_collision_passthrough(player, false)
		player = null
		_door_override_active = false
		_set_door_collision_mode(false)
		_restore_collision_mask()
		_reset_attack_state(true)
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
		# Потеряли линию видимости — идём к последней точке; в той же комнате — обследование.
		_door_override_active = false
		_set_door_collision_mode(false)
		var pl_room_los: int = _get_room_id_at_point_stable(player.global_position)
		if pl_room_los != -1:
			_committed_search_room_id = pl_room_los
		last_player_pos = player.global_position
		if nav_agent:
			nav_agent.target_position = last_player_pos
		var dist_los: float = global_position.distance_to(last_player_pos)
		var arrived_los: bool = dist_los <= arrive_last_seen_dist_px or (
			nav_agent != null and nav_agent.is_navigation_finished() and dist_los <= arrive_last_seen_dist_px * 2.5
		)
		if nav_agent and arrived_los:
			# Сразу после удара луч/дистанция могут кратко «потерять» игрока — не уходить в обследование,
			# а тянуться к актуальной позиции (она обновляется в анимации и здесь).
			if _attack_recovery_left > 0.0:
				if is_instance_valid(player):
					last_player_pos = player.global_position
					nav_agent.target_position = last_player_pos
				_follow_nav_agent(delta, speed)
				return
			var my_room_los: int = _get_room_id_at_point_stable(global_position)
			if _committed_search_room_id != -1 and my_room_los == _committed_search_room_id:
				_start_investigate_room(_committed_search_room_id)
				return
			state = State.PATROL
			if _committed_search_room_id != -1 and my_room_los != _committed_search_room_id:
				if _try_pick_intel_travel_to_room(_committed_search_room_id):
					_intel_travel_active = true
					_intel_room_id = _committed_search_room_id
					_log_intel("иду_в_комнату_после_потери_вида", _intel_room_id, last_player_pos)
				else:
					_start_patrol()
			else:
				_start_patrol()
			return
		_follow_nav_agent(delta, speed)
		return

	# видим игрока
	var player_room_id: int = _get_room_id_at_point_stable(player.global_position)
	if player_room_id != -1:
		_last_known_player_room_id = player_room_id
		_committed_search_room_id = player_room_id
	last_player_pos = player.global_position

	if global_position.distance_to(player.global_position) <= attack_range and (not _is_attacking) and _attack_recovery_left <= 0.0:
		_last_facing_dir = (player.global_position - global_position).normalized()
		_play_attack_anim()
		_door_override_active = false
		_set_door_collision_mode(false)
		return

	# Пока игрок в прямой видимости — только погоня к позиции (навигация + триггеры дверей).
	# Ветка «разные room_id → принудительно open_for_maniac» давала байт у двери.

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
	if debug_collision_prints and (state == State.PATROL or state == State.INVESTIGATE) and _debug_collision_timer <= 0.0:
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
	_clear_intel_travel()
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
	if door_node == null:
		return false
	if door_node.nav_a == null or door_node.nav_b == null:
		return false
	if door_node.is_open:
		return false
	if door_trigger_suppress_in_investigate and state == State.INVESTIGATE:
		return false
	if state == State.CHASE and is_instance_valid(player) and _can_see(player):
		if global_position.distance_to(player.global_position) <= door_trigger_suppress_when_chasing_close_px:
			return false
	# Уже решили идти через конкретную дверь — только она.
	if _door_override_active:
		return is_targeting_door(door_node)
	return true

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
	if body != player:
		return
	var saved_pos: Vector2 = player.global_position
	var saved_room: int = _get_room_id_at_point_stable(saved_pos)
	_set_player_collision_passthrough(player, false)
	_restore_collision_mask()
	_reset_attack_state(true)
	player = null
	_door_override_active = false
	_set_door_collision_mode(false)
	last_player_pos = saved_pos
	if saved_room != -1:
		_last_known_player_room_id = saved_room
		_committed_search_room_id = saved_room

	state = State.PATROL
	if saved_room != -1:
		var my_exit: int = _get_room_id_at_point_stable(global_position)
		if my_exit == saved_room:
			_start_investigate_room(saved_room)
		else:
			if _try_pick_intel_travel_to_room(saved_room):
				_intel_travel_active = true
				_intel_room_id = saved_room
				_log_intel("потеря_контакта_иду_в_комнату", saved_room, saved_pos)
			else:
				_start_patrol()
	else:
		_start_patrol()

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
	var target_room_id: int = _last_known_player_room_id
	var saved_inv_pos: Vector2 = last_player_pos
	if is_instance_valid(player):
		saved_inv_pos = player.global_position
		var rr: int = _get_room_id_at_point_stable(saved_inv_pos)
		if rr != -1:
			target_room_id = rr
			_last_known_player_room_id = rr
			_committed_search_room_id = rr
		_set_player_collision_passthrough(player, false)
	player = null
	_restore_collision_mask()
	_reset_attack_state(true)
	last_player_pos = saved_inv_pos
	state = State.PATROL
	if target_room_id != -1:
		var cur_here: int = _get_room_id_at_point_stable(global_position)
		if cur_here == target_room_id:
			_start_investigate_room(target_room_id)
		elif _try_pick_intel_travel_to_room(target_room_id):
			_intel_travel_active = true
			_intel_room_id = target_room_id
			_log_intel("невидимость_иду_в_комнату", target_room_id, saved_inv_pos)
			refresh_navigation(false)
		else:
			_start_patrol()
	else:
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
	var should_repick: bool = repick_wander and (state == State.PATROL or state == State.INVESTIGATE)
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

	if velocity.length() >= 1.0:
		_last_facing_dir = velocity.normalized()

	# Attack animation has priority while timer is active.
	if _attack_anim_time_left > 0.0 and anim.sprite_frames and anim.sprite_frames.has_animation("attack"):
		anim.flip_h = _last_facing_dir.x < -0.05
		if anim.animation != "attack":
			anim.play("attack")
		return

	var dir_name := _dir_to_anim_suffix(_last_facing_dir)
	var next_anim := ""
	if velocity.length() < 1.0:
		next_anim = "idle_%s" % dir_name
	else:
		next_anim = "walk_%s" % dir_name

	if dir_name == "side":
		anim.flip_h = _last_facing_dir.x < -0.05
	else:
		anim.flip_h = false

	if anim.sprite_frames and anim.sprite_frames.has_animation(next_anim):
		if anim.animation != next_anim:
			anim.play(next_anim)
		return

	# Fallback if a specific direction animation is missing.
	if velocity.length() < 1.0:
		if anim.sprite_frames and anim.sprite_frames.has_animation("idle_down") and anim.animation != "idle_down":
			anim.play("idle_down")
	else:
		if anim.sprite_frames and anim.sprite_frames.has_animation("walk_down") and anim.animation != "walk_down":
			anim.play("walk_down")

func _dir_to_anim_suffix(dir: Vector2) -> String:
	if absf(dir.x) > absf(dir.y):
		return "side"
	if dir.y < 0.0:
		return "up"
	return "down"

func _play_attack_anim() -> void:
	_is_attacking = true
	_attack_anim_time_left = attack_anim_duration_s
	_attack_damage_applied = false
	velocity = Vector2.ZERO
	if attack_swing_sfx != null:
		_play_short_sfx(attack_swing_sfx)
	if anim == null:
		# Fallback: если спрайта/анимации нет, не зависаем в вечной атаке.
		_is_attacking = false
		_attack_recovery_left = attack_recovery_s
		return
	if anim.sprite_frames and anim.sprite_frames.has_animation("attack"):
		anim.flip_h = _last_facing_dir.x < -0.05
		anim.play("attack")
		# Таймер синхронизируем с реальной длительностью анимации, чтобы не было спама атак.
		var frames_count: float = float(anim.sprite_frames.get_frame_count("attack"))
		var anim_speed: float = max(float(anim.sprite_frames.get_animation_speed("attack")), 0.001)
		var anim_len: float = frames_count / anim_speed
		_attack_anim_time_left = max(_attack_anim_time_left, anim_len)
	else:
		# Нет анимации attack — используем таймер и recovery как кулдаун.
		_is_attacking = false
		_attack_recovery_left = attack_recovery_s

func _on_anim_finished() -> void:
	if anim == null:
		return
	if anim.animation != "attack":
		return
	_reset_attack_state(true)

func _on_anim_frame_changed() -> void:
	if anim == null:
		return
	var anim_name: String = str(anim.animation)
	if anim_name.begins_with("walk_") and velocity.length() > 28.0:
		if _footstep_cooldown <= 0.0 and footstep_sfx != null:
			_footstep_cooldown = footstep_min_interval_s
			_play_short_sfx(footstep_sfx)
	if _attack_anim_time_left <= 0.0:
		return
	if anim.animation != "attack":
		return
	if _attack_damage_applied:
		return
	if anim.frame != attack_hit_frame_index:
		return

	_attack_damage_applied = true
	if not is_instance_valid(player):
		return
	if global_position.distance_to(player.global_position) > attack_range:
		return
	if player.has_method("take_damage"):
		player.take_damage(1, true)
