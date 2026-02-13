extends CharacterBody2D

signal became_invisible
signal became_visible

enum {
	DOWN,
	UP,
	LEFT,
	RIGHT
}
@onready var hint: Label = $Label
@onready var animations: AnimatedSprite2D = $AnimatedSprite2D
@onready var cam: Camera2D = $Camera2D

const BASE_RESOLUTION := Vector2(1280, 720)

var speed := 140.0
var idle_dir := DOWN
var idle_time := 0.0
const IDLE_DELAY := 0.25
var control_enabled: bool = true

# --- HP / DAMAGE ---
@export var max_hp: int = 3
var hp: int
var invuln_time: float = 0.8
var _invuln_timer: Timer
var _is_invulnerable: bool = false

# --- BUFFS ---
var _base_speed: float
var _speed_buff_timer: Timer
var _invis_timer: Timer
var _saved_modulate: Color

# invisibility flag
var is_invisible: bool = false

# --- HINT ---
var _hint_timer: Timer

func _ready() -> void:
	add_to_group("player")

	# HP init
	hp = max_hp
	_invuln_timer = Timer.new()
	_invuln_timer.one_shot = true
	add_child(_invuln_timer)
	_invuln_timer.timeout.connect(_on_invuln_end)

	_base_speed = float(speed)
	_saved_modulate = modulate

	# --- Hint ---
	hint.visible = false
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_hint_timer = Timer.new()
	_hint_timer.one_shot = true
	_hint_timer.wait_time = 1.5
	add_child(_hint_timer)
	_hint_timer.timeout.connect(_hide_hint)

	# --- Buff timers ---
	_speed_buff_timer = Timer.new()
	_speed_buff_timer.one_shot = true
	add_child(_speed_buff_timer)
	_speed_buff_timer.timeout.connect(_on_speed_buff_end)

	_invis_timer = Timer.new()
	_invis_timer.one_shot = true
	add_child(_invis_timer)
	_invis_timer.timeout.connect(_on_invis_end)

	if cam:
		cam.make_current()
		_update_camera_zoom()
		get_viewport().size_changed.connect(_update_camera_zoom)

# =========================
# ПОДСКАЗКИ
# =========================
func show_hint(text: String) -> void:
	hint.text = text
	hint.visible = true
	_hint_timer.start()

func _hide_hint() -> void:
	hint.visible = false

# =========================
# ДВИЖЕНИЕ
# =========================
func _physics_process(delta: float) -> void:
	if not control_enabled:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var dir := Vector2.ZERO

	if Input.is_action_pressed("up"):
		dir.y -= 1
	if Input.is_action_pressed("down"):
		dir.y += 1
	if Input.is_action_pressed("left"):
		dir.x -= 1
	if Input.is_action_pressed("right"):
		dir.x += 1

	if dir != Vector2.ZERO:
		dir = dir.normalized()
		velocity = dir * speed
		idle_time = 0.0
		update_animation(dir)
	else:
		velocity = Vector2.ZERO
		idle_time += delta
		idle()

	move_and_slide()

func update_animation(dir: Vector2) -> void:
	if dir.y < 0:
		animations.play("Idle_up")
		idle_dir = UP
	elif dir.y > 0:
		animations.play("Idle_down")
		idle_dir = DOWN
	elif dir.x < 0:
		animations.flip_h = true
		animations.play("Idle_front")
		idle_dir = LEFT
	elif dir.x > 0:
		animations.flip_h = false
		animations.play("Idle_front")
		idle_dir = RIGHT

func idle() -> void:
	if idle_time >= IDLE_DELAY:
		animations.play("idle")
		return

	match idle_dir:
		DOWN: animations.play("Idle_down")
		UP: animations.play("Idle_up")
		LEFT:
			animations.flip_h = true
			animations.play("Idle_front")
		RIGHT:
			animations.flip_h = false
			animations.play("Idle_front")

# =========================
# КАМЕРА
# =========================
func _update_camera_zoom() -> void:
	var s: Vector2 = get_viewport().get_visible_rect().size
	var scale: float = min(
		s.x / BASE_RESOLUTION.x,
		s.y / BASE_RESOLUTION.y
	)
	cam.zoom = Vector2(scale, scale) * 2

# =========================
# BUFFS
# =========================
func apply_speed_buff(multiplier: float, duration: float) -> void:
	speed = int(_base_speed * multiplier)
	_speed_buff_timer.start(duration)

func _on_speed_buff_end() -> void:
	speed = int(_base_speed)

func apply_invisibility(duration: float) -> void:
	_saved_modulate = modulate
	modulate.a = 0.25
	is_invisible = true
	add_to_group("invisible")
	emit_signal("became_invisible")
	_invis_timer.start(duration)

func _on_invis_end() -> void:
	modulate = _saved_modulate
	is_invisible = false
	if is_in_group("invisible"):
		remove_from_group("invisible")
	emit_signal("became_visible")
	_notify_nearby_maniacs_on_reveal(160.0)

func _notify_nearby_maniacs_on_reveal(radius: float) -> void:
	for m in get_tree().get_nodes_in_group("maniac"):
		if not m:
			continue
		if not m.has_method("on_player_revealed"):
			continue
		if global_position.distance_to(m.global_position) <= radius:
			# вызов напрямую; маньяк сам проверит видимость/дистанцию
			m.on_player_revealed(self)

# =========================
# DAMAGE API
# =========================
func take_damage(amount: int = 1, from_maniac: bool = false) -> void:
	if _is_invulnerable:
		return

	hp -= amount

	if hp <= 0:
		die(from_maniac)
		return

	_become_invulnerable()
	_flash_on_damage()

func _become_invulnerable() -> void:
	_is_invulnerable = true
	_invuln_timer.start(invuln_time)

func _on_invuln_end() -> void:
	_is_invulnerable = false
	modulate = _saved_modulate

func get_hp() -> int:
	return hp

func set_hp(value: int) -> void:
	hp = int(clamp(value, 0, max_hp))

func _flash_on_damage() -> void:
	modulate = Color(1, 0.6, 0.6, 1)

func die(killed_by_maniac: bool = false) -> void:
	control_enabled = false

	var tree: SceneTree = get_tree()
	if tree == null:
		return

	var level_path: String = tree.current_scene.scene_file_path

	var cause: int = DeathFlow.DeathCause.MANIAC if killed_by_maniac else DeathFlow.DeathCause.OTHER
	DeathFlow.start_death_flow(level_path, cause)

	queue_free()



# =========================
# Утилиты
# =========================
func get_speed() -> float:
	return speed
