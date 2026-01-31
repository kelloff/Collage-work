# res://scripts/Player.gd
extends CharacterBody2D

enum {
	DOWN,
	UP,
	LEFT,
	RIGHT
}

@onready var animations: AnimatedSprite2D = $AnimatedSprite2D
@onready var cam: Camera2D = $Camera2D

# База — то разрешение, в котором камера "правильная" (у тебя это 1280x720)
const BASE_RESOLUTION := Vector2(1280, 720)

var speed := 140.0
var idle_dir := DOWN
var idle_time := 0.0
const IDLE_DELAY := 0.25
var control_enabled: bool = true

# --- BUFFS ---
var _base_speed: float
var _speed_buff_timer: Timer
var _invis_timer: Timer
var _saved_modulate: Color

func _ready() -> void:
	add_to_group("player")

	_base_speed = float(speed)
	_saved_modulate = modulate

	_speed_buff_timer = Timer.new()
	_speed_buff_timer.one_shot = true
	add_child(_speed_buff_timer)
	_speed_buff_timer.timeout.connect(_on_speed_buff_end)

	_invis_timer = Timer.new()
	_invis_timer.one_shot = true
	add_child(_invis_timer)
	_invis_timer.timeout.connect(_on_invis_end)

	# Гарантируем, что активна именно камера игрока
	if is_instance_valid(cam):
		cam.make_current()
		_update_camera_zoom()
		# будет вызываться при смене размера окна / разрешения / fullscreen
		get_viewport().size_changed.connect(_update_camera_zoom)


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
	velocity = Vector2.ZERO

	if idle_time >= IDLE_DELAY:
		animations.play("idle")
		return

	match idle_dir:
		DOWN:
			animations.play("Idle_down")
		UP:
			animations.play("Idle_up")
		LEFT:
			animations.flip_h = true
			animations.play("Idle_front")
		RIGHT:
			animations.flip_h = false
			animations.play("Idle_front")


func set_control_enabled(enabled: bool) -> void:
	control_enabled = enabled
	if not enabled:
		velocity = Vector2.ZERO


# --- Камера: адаптация под разрешение ---
func _update_camera_zoom() -> void:
	if not is_instance_valid(cam):
		return

	# Реальный видимый размер экрана (учитывает fullscreen/окно)
	var s: Vector2 = get_viewport().get_visible_rect().size

	# Насколько текущий экран больше/меньше базового
	var scale_x := s.x / BASE_RESOLUTION.x
	var scale_y := s.y / BASE_RESOLUTION.y
	var scale: float = min(scale_x, scale_y)

	# КЛЮЧЕВОЕ:
	# Чтобы на большом экране (fullscreen) камера НЕ была "слишком далеко",
	# мы увеличиваем zoom => камера приближается.
	cam.zoom = Vector2(scale, scale) * 2
func apply_speed_buff(multiplier: float, duration: float) -> void:
	speed = int(_base_speed * multiplier)
	_speed_buff_timer.start(duration)

func _on_speed_buff_end() -> void:
	speed = int(_base_speed)

func apply_invisibility(duration: float) -> void:
	_saved_modulate = modulate
	modulate.a = 0.25  # 0.0 если хочешь полностью исчезать
	_invis_timer.start(duration)

func _on_invis_end() -> void:
	modulate = _saved_modulate
