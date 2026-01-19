# res://scripts/Player.gd
extends CharacterBody2D

enum {
	DOWN,
	UP,
	LEFT,
	RIGHT
}

@onready var animations = $AnimatedSprite2D

var speed = 140
var idle_dir = DOWN
var idle_time := 0.0
const IDLE_DELAY := 0.25
var control_enabled: bool = true

func _ready() -> void:
	add_to_group("player")


func _physics_process(delta: float) -> void:
	if not control_enabled:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var dir := Vector2.ZERO

	# собираем вектор направления
	if Input.is_action_pressed("up"):
		dir.y -= 1
	if Input.is_action_pressed("down"):
		dir.y += 1
	if Input.is_action_pressed("left"):
		dir.x -= 1
	if Input.is_action_pressed("right"):
		dir.x += 1

	if dir != Vector2.ZERO:
		dir = dir.normalized()  # нормализация для диагонали
		velocity = dir * speed
		idle_time = 0.0
		update_animation(dir)
	else:
		velocity = Vector2.ZERO
		idle_time += delta
		idle()


	move_and_slide()


func update_animation(dir: Vector2) -> void:
	# приоритет вертикали: если есть вертикальная компонента — показываем up/down
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


func idle():
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
