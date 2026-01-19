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
	var is_moving = false
	if not control_enabled:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	if Input.is_action_pressed("up"):
		up_move()
		is_moving = true
	elif Input.is_action_pressed("down"):
		down_move()
		is_moving = true
	elif Input.is_action_pressed("left"):
		left_move()
		is_moving = true
	elif Input.is_action_pressed("right"):
		right_move()
		is_moving = true
	else:
		idle_time += delta
		idle()

	if is_moving:
		idle_time = 0.0

	move_and_slide()
func up_move():
	animations.play("Idle_up")
	velocity.x = 0
	velocity.y = -speed
	idle_dir = UP
func down_move():
	animations.play("Idle_down")
	velocity.x = 0
	velocity.y = speed
	idle_dir = DOWN

func left_move():
	animations.flip_h = true
	animations.play("Idle_front")
	velocity.x = -speed
	velocity.y = 0
	idle_dir = LEFT
	
func right_move():
	animations.flip_h = false
	animations.play("Idle_front")
	velocity.x = speed
	velocity.y = 0
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
				
#@export var max_speed: float = 200.0

#
#func _physics_process(_delta: float) -> void:

#
	#var dir: Vector2 = movement_vector()
	#if dir != Vector2.ZERO:
		#dir = dir.normalized()
	#velocity = dir * max_speed
	#move_and_slide()
#
#func movement_vector() -> Vector2:
	#var x := 0
	#var y := 0
	#if Input.is_action_pressed("move_right"):
		#x += 1
	#if Input.is_action_pressed("move_left"):
		#x -= 1
	#if Input.is_action_pressed("move_down"):
		#y += 1
	#if Input.is_action_pressed("move_up"):
		#y -= 1
	#return Vector2(x, y)
