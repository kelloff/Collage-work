extends CharacterBody2D

@export var patrol_points: Array[Vector2] = []
@export var speed: float = 80.0
@export var chase_speed: float = 140.0
@export var vision_range: float = 320.0
@export var attack_damage: int = 1
@export var attack_cooldown: float = 1.0
@export var lose_sight_delay: float = 2.0

@export_range(0,31) var PLAYER_LAYER_INDEX: int = 0
@export_range(0,31) var WALLS_LAYER_INDEX: int = 1
@export_range(0,31) var ENEMY_LAYER_INDEX: int = 2

@export var attack_hit_frame: int = 7
@export var force_instant_hit: bool = false

@export var chase_speed_multiplier_vs_player: float = 0.92
@export var min_chase_speed: float = 40.0

@export var stop_distance_to_player: float = 28.0
@export var wall_check_distance: float = 24.0
@export var attack_distance_margin: float = 2.0

@export var debug_logs: bool = false

# Distance under which an invisible player can still be detected
@export var close_alert_distance: float = 80.0

@onready var sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")
@onready var vision_area: Area2D = get_node_or_null("Vision")
@onready var attack_area: Area2D = get_node_or_null("AttackArea")
@onready var attack_area_shape_node: CollisionShape2D = get_node_or_null("AttackArea/CollisionShape2D")
@onready var patrol_timer: Timer = get_node_or_null("patrol_timer")
@onready var body_collision_shape: CollisionShape2D = get_node_or_null("CollisionShape2D")

enum State { PATROL, ALERT, CHASE, ATTACK }
var state: int = State.PATROL

var _player: Node2D = null
var _last_known_pos: Vector2 = Vector2.ZERO
var _has_last_known_pos: bool = false
var _current_patrol_index: int = 0
var _lose_timer: Timer
var _attack_ready: bool = true
var _attack_executed: bool = false

var _vision_check_timer: Timer
var idle_dir := 0
var _current_chase_speed: float = 140.0

var _is_attacking: bool = false
var _cooldown_running: bool = false

var _attack_radius: float = 28.0

# --------------------
# Инициализация
# --------------------
func _ready() -> void:
	add_to_group("maniac")
	if vision_area:
		if not vision_area.is_connected("body_entered", Callable(self, "_on_vision_body_entered")):
			vision_area.body_entered.connect(Callable(self, "_on_vision_body_entered"))
		if not vision_area.is_connected("body_exited", Callable(self, "_on_vision_body_exited")):
			vision_area.body_exited.connect(Callable(self, "_on_vision_body_exited"))
	if attack_area:
		if not attack_area.is_connected("body_entered", Callable(self, "_on_attack_body_entered")):
			attack_area.body_entered.connect(Callable(self, "_on_attack_body_entered"))
	if patrol_timer:
		if not patrol_timer.is_connected("timeout", Callable(self, "_on_patrol_timer_timeout")):
			patrol_timer.timeout.connect(Callable(self, "_on_patrol_timer_timeout"))

	_lose_timer = Timer.new()
	_lose_timer.one_shot = true
	add_child(_lose_timer)
	_lose_timer.timeout.connect(Callable(self, "_on_lose_timer_timeout"))

	_vision_check_timer = Timer.new()
	_vision_check_timer.one_shot = false
	_vision_check_timer.wait_time = 0.18
	add_child(_vision_check_timer)
	_vision_check_timer.timeout.connect(Callable(self, "_on_vision_check_timer_timeout"))

	if sprite:
		if not sprite.is_connected("frame_changed", Callable(self, "_on_frame_changed")):
			sprite.frame_changed.connect(Callable(self, "_on_frame_changed"))
		if not sprite.is_connected("animation_finished", Callable(self, "_on_sprite_animation_finished")):
			sprite.animation_finished.connect(Callable(self, "_on_sprite_animation_finished"))

	state = State.PATROL
	_current_chase_speed = chase_speed

	collision_layer = 1 << ENEMY_LAYER_INDEX
	collision_mask = (1 << WALLS_LAYER_INDEX)

	if attack_area:
		attack_area.collision_mask = 1 << PLAYER_LAYER_INDEX
	if vision_area:
		vision_area.collision_mask = 1 << PLAYER_LAYER_INDEX

	if body_collision_shape:
		body_collision_shape.disabled = false

	_attack_radius = _compute_attack_radius()
	stop_distance_to_player = _attack_radius + attack_distance_margin
	if debug_logs:
		print("READY: attack_radius=", _attack_radius, " stop_distance=", stop_distance_to_player)

func _compute_attack_radius() -> float:
	if not attack_area or not attack_area_shape_node:
		return stop_distance_to_player
	var cs = attack_area_shape_node
	if not cs.shape:
		var aabb = cs.get_transformed_aabb()
		return aabb.size.length() * 0.5
	var s = cs.shape
	var scale_factor = max(attack_area.global_scale.x, attack_area.global_scale.y)
	if s is CircleShape2D:
		return s.radius * scale_factor
	elif s is RectangleShape2D:
		return s.extents.length() * scale_factor
	elif s is CapsuleShape2D:
		var cap = s as CapsuleShape2D
		return max(cap.radius, cap.height * 0.5) * scale_factor
	else:
		return cs.get_transformed_aabb().size.length() * scale_factor

func _move_and_collide_safe(delta: float) -> void:
	var rel = velocity * delta
	if rel == Vector2.ZERO:
		return
	var col = move_and_collide(rel)
	if col:
		velocity = Vector2.ZERO
		if debug_logs:
			print("Collision detected, stopped. collider=", col.get_collider())

func _physics_process(delta: float) -> void:
	if _is_attacking:
		velocity = Vector2.ZERO
		_move_and_collide_safe(delta)
		_update_animation(velocity)
		if debug_logs:
			print("PHYSICS: blocked by _is_attacking")
		return

	match state:
		State.CHASE:
			if _player:
				_chase(delta)
			else:
				if _has_last_known_pos:
					_go_to_last_known(delta)
				else:
					state = State.PATROL
		State.PATROL:
			_patrol(delta)
		State.ALERT:
			velocity = Vector2.ZERO
			_move_and_collide_safe(delta)

	_update_animation(velocity)

# Патруль
func _patrol(delta: float) -> void:
	if patrol_points.size() == 0:
		velocity = Vector2.ZERO
		_move_and_collide_safe(delta)
		return
	var target = patrol_points[_current_patrol_index]
	var dir = target - global_position
	if dir.length() < 8:
		velocity = Vector2.ZERO
	else:
		velocity = dir.normalized() * speed
	_move_and_collide_safe(delta)

func _on_patrol_timer_timeout() -> void:
	if patrol_points.size() == 0:
		return
	_current_patrol_index = (_current_patrol_index + 1) % patrol_points.size()

# Движение к последней известной позиции
func _go_to_last_known(delta: float) -> void:
	if not _has_last_known_pos:
		return
	var dir = _last_known_pos - global_position
	if dir.length() < 6:
		_last_known_pos = Vector2.ZERO
		_has_last_known_pos = false
		velocity = Vector2.ZERO
		_move_and_collide_safe(delta)
		if attack_area and _attack_ready:
			for b in attack_area.get_overlapping_bodies():
				if b and b.is_in_group("player"):
					_start_attack_from_proximity(b)
					return
		return
	velocity = dir.normalized() * speed
	_move_and_collide_safe(delta)

# Преследование
func _chase(delta: float) -> void:
	if _is_attacking:
		velocity = Vector2.ZERO
		_move_and_collide_safe(delta)
		return
	if not _player:
		state = State.PATROL
		return

	_adjust_chase_speed_to_player()

	var to_player = _player.global_position - global_position
	var dist = to_player.length()

	if dist <= _attack_radius + attack_distance_margin:
		velocity = Vector2.ZERO
		_move_and_collide_safe(delta)
		if debug_logs:
			print("CHOKE: within attack radius. dist=", dist)
		if _attack_ready:
			_start_attack_from_proximity(_player)
		return

	if not _can_see_player(_player):
		_last_known_pos = _player.global_position
		_has_last_known_pos = true
		_clear_player()
		state = State.PATROL
		_lose_timer.start(lose_sight_delay)
		return

	velocity = to_player.normalized() * _current_chase_speed
	_move_and_collide_safe(delta)

# --------------------
# Атака
# --------------------
func _start_attack_from_proximity(body: Node) -> void:
	if not body or not body.is_in_group("player"):
		return
	# ignore invisible targets
	if body.is_in_group("invisible") or (body.has_method("is_invisible") and body.is_invisible):
		if debug_logs:
			print("attack: target is invisible, aborting attack start")
		return
	if _is_attacking:
		return
	if debug_logs:
		print("ATTACK START called | is_attacking=", _is_attacking, " attack_ready=", _attack_ready, " attack_executed=", _attack_executed)

	_set_player(body)
	if force_instant_hit:
		_apply_attack_damage_to_overlaps()
		await get_tree().create_timer(attack_cooldown).timeout
		_attack_ready = true
		return
	if not _attack_ready:
		return

	_is_attacking = true
	state = State.ATTACK
	velocity = Vector2.ZERO

	_attack_executed = false
	_attack_ready = false

	var dir = (body.global_position - global_position)
	if abs(dir.x) > abs(dir.y) and sprite:
		sprite.flip_h = dir.x < 0

	if sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation("attack"):
		if debug_logs:
			print("ATTACK: playing AnimatedSprite2D attack (force restart)")
		sprite.stop()
		sprite.frame = 0
		sprite.play("attack")
	else:
		if debug_logs:
			print("ATTACK: no animation found, applying immediate damage")
		_apply_attack_damage_to_overlaps()
		_attack_executed = true
		_start_attack_cooldown()
		_is_attacking = false

func _on_attack_body_entered(body: Node) -> void:
	if not body:
		return
	if not body.is_in_group("player"):
		return
	# ignore invisible players
	if body.is_in_group("invisible") or (body.has_method("is_invisible") and body.is_invisible):
		if debug_logs:
			print("attack_area: ignored invisible player")
		return
	if _is_attacking:
		return
	_start_attack_from_proximity(body)

func _on_frame_changed() -> void:
	if not sprite:
		return
	if sprite.animation != "attack":
		return
	if _attack_executed:
		return
	if sprite.frame == attack_hit_frame:
		if debug_logs:
			print("FRAME HIT: applying damage at frame", sprite.frame)
		_apply_attack_damage_to_overlaps()
		_attack_executed = true
		_start_attack_cooldown()

func _on_sprite_animation_finished(anim_name: String = "") -> void:
	if anim_name != "" and anim_name != "attack":
		return
	if debug_logs:
		print("Sprite animation finished:", anim_name, " attack_executed=", _attack_executed)
	if not _attack_executed:
		_start_attack_cooldown()
	_is_attacking = false
	_attack_executed = false
	_play_idle_animation()
	if attack_area:
		for b in attack_area.get_overlapping_bodies():
			if b and b.is_in_group("player"):
				_set_player(b)
				state = State.CHASE
				if debug_logs:
					print("Player still in attack area after animation — switching to CHASE for retry")
				return
	if _player and _can_see_player(_player):
		state = State.CHASE
	elif _has_last_known_pos:
		state = State.PATROL
	else:
		state = State.PATROL

func _apply_attack_damage_to_overlaps() -> void:
	if not attack_area:
		return
	var bodies: Array = attack_area.get_overlapping_bodies()
	if debug_logs:
		print("apply_attack overlaps count=", bodies.size())
	for b in bodies:
		if b and b.is_in_group("player") and b.has_method("take_damage"):
			# skip invisible players
			if b.is_in_group("invisible") or (b.has_method("is_invisible") and b.is_invisible):
				if debug_logs:
					print("apply_attack: skipped invisible", b)
				continue
			if debug_logs:
				print("HIT ->", b)
			b.take_damage(attack_damage)
			if Engine.has_singleton("GameState"):
				var gs = Engine.get_singleton("GameState")
				if gs and gs.has_method("record_hit"):
					gs.record_hit()

func _start_attack_cooldown() -> void:
	if _cooldown_running:
		return
	_cooldown_running = true
	_attack_ready = false
	if debug_logs:
		print("COOLDOWN START")
	await get_tree().create_timer(attack_cooldown).timeout
	_attack_ready = true
	_cooldown_running = false
	if debug_logs:
		print("COOLDOWN END -> attack_ready=", _attack_ready)

# --------------------
# Видимость и утилиты
# --------------------
func _on_vision_body_entered(body: Node) -> void:
	if not body or not body.is_in_group("player"):
		return
	# Если игрок невидим — игнорируем
	if body.is_in_group("invisible") or (body.has_method("is_invisible") and body.is_invisible):
		if debug_logs:
			print("vision: ignored invisible player on enter")
		return
	_vision_check_timer.start()
	if _can_see_player(body):
		_set_player(body)
		state = State.ALERT
		_last_known_pos = Vector2.ZERO
		_has_last_known_pos = false
		if sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation("alert"):
			sprite.play("alert")
		else:
			state = State.CHASE

func _on_vision_body_exited(body: Node) -> void:
	if not body or not body.is_in_group("player"):
		return
	_vision_check_timer.stop()
	if body == _player:
		_last_known_pos = body.global_position
		_has_last_known_pos = true
		_clear_player()
		state = State.PATROL
		_lose_timer.start(lose_sight_delay)

func _on_vision_check_timer_timeout() -> void:
	if not vision_area:
		return
	for b in vision_area.get_overlapping_bodies():
		if b and b.is_in_group("player"):
			# skip invisible players
			if b.is_in_group("invisible") or (b.has_method("is_invisible") and b.is_invisible):
				continue
			if _can_see_player(b):
				_set_player(b)
				state = State.CHASE
				return

func _can_see_player(player: Node2D) -> bool:
	if not player:
		return false
	var from_pos: Vector2 = global_position
	var to_pos: Vector2 = player.global_position

	# 1) If player is invisible (group or flag), ignore unless very close
	if player.is_in_group("invisible") or (player.has_method("is_invisible") and player.is_invisible):
		if from_pos.distance_to(to_pos) <= close_alert_distance:
			# very close: still detectable
			return true
		# otherwise invisible -> not seen
		return false

	# 2) Distance check
	if from_pos.distance_to(to_pos) > vision_range:
		return false

	# 3) Raycast / physics check
	var space := get_world_2d().direct_space_state
	var mask: int = (1 << PLAYER_LAYER_INDEX) | (1 << WALLS_LAYER_INDEX)
	var params := PhysicsRayQueryParameters2D.new()
	params.from = from_pos
	params.to = to_pos
	params.exclude = [self]
	params.collision_mask = mask
	params.collide_with_bodies = true
	params.collide_with_areas = false
	var res: Dictionary = space.intersect_ray(params)
	if res.size() == 0:
		return true
	return res.get("collider") == player

func _adjust_chase_speed_to_player() -> void:
	if not _player:
		_current_chase_speed = chase_speed
		return
	if _player.has_method("get_speed"):
		var p_speed_m = _player.call("get_speed")
		if typeof(p_speed_m) in [TYPE_INT, TYPE_FLOAT]:
			_current_chase_speed = clamp(float(p_speed_m) * chase_speed_multiplier_vs_player, min_chase_speed, chase_speed)
			return
	var p_speed = _player.get("speed")
	if typeof(p_speed) in [TYPE_INT, TYPE_FLOAT]:
		_current_chase_speed = clamp(float(p_speed) * chase_speed_multiplier_vs_player, min_chase_speed, chase_speed)
		return
	_current_chase_speed = chase_speed

func set_passable(passable: bool) -> void:
	if body_collision_shape:
		body_collision_shape.disabled = passable

func _on_lose_timer_timeout() -> void:
	_last_known_pos = Vector2.ZERO
	_has_last_known_pos = false

# --------------------
# Управление целью (подписки на сигналы игрока)
# --------------------
func _set_player(p: Node) -> void:
	# Очистим предыдущую цель корректно
	_clear_player()
	_player = p
	# Подпишемся на сигнал became_invisible, если он есть
	if _player and _player.has_signal("became_invisible"):
		if not _player.is_connected("became_invisible", Callable(self, "_on_player_became_invisible")):
			_player.connect("became_invisible", Callable(self, "_on_player_became_invisible"))
	# Подписка на became_visible не обязательна, но можно
	if _player and _player.has_signal("became_visible"):
		if not _player.is_connected("became_visible", Callable(self, "_on_player_became_visible")):
			_player.connect("became_visible", Callable(self, "_on_player_became_visible"))

func _clear_player() -> void:
	if _player:
		# отключаем сигналы безопасно
		if _player.has_signal("became_invisible") and _player.is_connected("became_invisible", Callable(self, "_on_player_became_invisible")):
			_player.disconnect("became_invisible", Callable(self, "_on_player_became_invisible"))
		if _player.has_signal("became_visible") and _player.is_connected("became_visible", Callable(self, "_on_player_became_visible")):
			_player.disconnect("became_visible", Callable(self, "_on_player_became_visible"))
	_player = null

func _on_player_became_invisible() -> void:
	# если текущая цель стала невидимой — сбрасываем цель и начинаем потерю
	if _player and _player.is_in_group("invisible"):
		if debug_logs:
			print("player became invisible — dropping target")
		_last_known_pos = _player.global_position
		_has_last_known_pos = true
		_clear_player()
		state = State.PATROL
		_lose_timer.start(lose_sight_delay)

func _on_player_became_visible() -> void:
	# ничего особенного — в следующем цикле vision_check/_on_vision_check_timer_timeout игрок будет обнаружен снова
	pass

# --------------------
# Анимации
# --------------------
func _update_animation(vel: Vector2) -> void:
	if _is_attacking or state == State.ATTACK:
		if sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation("attack"):
			if sprite.animation != "attack":
				sprite.play("attack")
		return
	if state == State.ALERT:
		if sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation("alert") and sprite.animation != "alert":
			sprite.play("alert")
		return
	if state == State.CHASE:
		_play_movement_animation(vel, "walk")
		return
	if vel.length() > 1:
		_play_movement_animation(vel, "walk")
	else:
		_play_idle_animation()

func _play_movement_animation(vel: Vector2, base_name: String) -> void:
	if not sprite:
		return
	if abs(vel.x) > abs(vel.y):
		sprite.flip_h = vel.x < 0
		var anim = base_name + "_side"
		if sprite.animation != anim:
			sprite.play(anim)
		idle_dir = 2 if vel.x < 0 else 3
	else:
		if vel.y < 0:
			var anim = base_name + "_up"
			if sprite.animation != anim:
				sprite.play(anim)
			idle_dir = 1
		else:
			var anim = base_name + "_down"
			if sprite.animation != anim:
				sprite.play(anim)
			idle_dir = 0

func _play_idle_animation() -> void:
	if not sprite:
		return
	match idle_dir:
		0:
			if sprite.animation != "idle_down":
				sprite.play("idle_down")
		1:
			if sprite.animation != "idle_up":
				sprite.play("idle_up")
		2:
			sprite.flip_h = true
			if sprite.sprite_frames and sprite.sprite_frames.has_animation("idle_side"):
				if sprite.animation != "idle_side":
					sprite.play("idle_side")
			else:
				if sprite.animation != "idle_down":
					sprite.play("idle_down")
		3:
			sprite.flip_h = false
			if sprite.sprite_frames and sprite.sprite_frames.has_animation("idle_side"):
				if sprite.animation != "idle_side":
					sprite.play("idle_side")
			else:
				if sprite.animation != "idle_down":
					sprite.play("idle_down")
