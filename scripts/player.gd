# res://scripts/Player.gd
extends CharacterBody2D

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

# --- BUFFS ---
var _base_speed: float
var _speed_buff_timer: Timer
var _invis_timer: Timer
var _saved_modulate: Color

# --- HINT ---
var _hint_timer: Timer

func _ready() -> void:
	add_to_group("player")

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
	_invis_timer.start(duration)

func _on_invis_end() -> void:
	modulate = _saved_modulate
