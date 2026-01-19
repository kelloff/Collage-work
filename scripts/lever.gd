extends Node2D

@onready var animations: AnimatedSprite2D = $AnimatedSprite2D
@onready var area: Area2D = $InteractionArea


var is_on: bool = false
var linked_doors: Array = []

var player_in_range: bool = false
var player_node: Node = null

func _ready():
	if area:
		area.monitoring = true # убедиться, что Area2D активна
		if not area.is_connected("body_entered", Callable(self, "_on_body_entered")):
			area.body_entered.connect(_on_body_entered)
		if not area.is_connected("body_exited", Callable(self, "_on_body_exited")):
			area.body_exited.connect(_on_body_exited)
	else:
		push_error("InteractionArea not found")
	
	# показать первый кадр без проигрывания
	animations.animation = "down"
	animations.frame = 0
	animations.stop() # стоп, чтобы не проигрывалось

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		player_in_range = true
		player_node = body
		show_hint(true)

func _on_body_exited(body: Node) -> void:
	if body == player_node:
		player_in_range = false
		player_node = null
		show_hint(false)

func _process(delta: float) -> void:
	if player_in_range and Input.is_action_pressed("interact"):
		toggle()

func toggle():
	is_on = !is_on
	if is_on:
		animations.animation = "up"
	else:
		animations.animation = "down"
	animations.frame = 0
	animations.stop() # чтобы не проигрывалась анимация, только кадр

	# связь с дверями
	for door in linked_doors:
		if door.has_method("on_lever_toggled"):
			door.on_lever_toggled(self, is_on)

func show_hint(show: bool):
	# сюда можно вставить UI подсказку "E"
	pass
