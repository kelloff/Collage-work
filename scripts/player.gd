# res://scripts/Player.gd
extends CharacterBody2D

@export var max_speed: float = 200.0
var control_enabled: bool = true

func _ready() -> void:
	add_to_group("player")

func _physics_process(_delta: float) -> void:
	if not control_enabled:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var dir: Vector2 = movement_vector()
	if dir != Vector2.ZERO:
		dir = dir.normalized()
	velocity = dir * max_speed
	move_and_slide()

func movement_vector() -> Vector2:
	var x := 0
	var y := 0
	if Input.is_action_pressed("move_right"):
		x += 1
	if Input.is_action_pressed("move_left"):
		x -= 1
	if Input.is_action_pressed("move_down"):
		y += 1
	if Input.is_action_pressed("move_up"):
		y -= 1
	return Vector2(x, y)

func set_control_enabled(enabled: bool) -> void:
	control_enabled = enabled
	if not enabled:
		velocity = Vector2.ZERO
