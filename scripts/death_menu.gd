# res://scripts/DeathMenu.gd
extends CanvasLayer

@onready var overlay: ColorRect = $overlay
@onready var panel: Panel = $Panel
@onready var anim: AnimationPlayer = $AnimationPlayer

func _ready() -> void:
	add_to_group("ui")
	visible = false
	# начальные значения (скрыто)
	overlay.modulate.a = 0.0
	panel.modulate.a = 0.0
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP

func show_menu() -> void:
	visible = true
	# обновление статистики здесь...
	# проиграть анимацию появления
	if anim.has_animation("fade_in"):
		anim.play("fade_in")
	else:
		# fallback: мгновенно показать
		overlay.modulate.a = 0.5
		panel.modulate.a = 0.95

func hide_menu() -> void:
	if anim.has_animation("fade_out"):
		anim.play("fade_out")
	else:
		visible = false
