extends Node2D

@onready var area: Area2D = $InteractionArea
@onready var hint_label: Label = $HintLabel
@onready var terminal_ui: CanvasLayer = $TerminalUI

var player_in_range: bool = false
var player_node: Node = null

@export var level: int = 0
var computer_id: int = 0

static var id_counter: int = 1

var current_task: Dictionary = {}

func _ready():
	# авто‑назначение ID при создании узла
	computer_id = id_counter
	id_counter += 1

	if area:
		if not area.is_connected("body_entered", Callable(self, "_on_body_entered")):
			area.connect("body_entered", Callable(self, "_on_body_entered"))
		if not area.is_connected("body_exited", Callable(self, "_on_body_exited")):
			area.connect("body_exited", Callable(self, "_on_body_exited"))
	else:
		push_error("InteractionArea not found")
		return

	hint_label.visible = false
	terminal_ui.visible = false

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		player_in_range = true
		player_node = body
		hint_label.visible = true

func _on_body_exited(body: Node) -> void:
	if body == player_node:
		player_in_range = false
		player_node = null
		hint_label.visible = false

func _process(_delta: float) -> void:
	# если терминал открыт — обрабатываем только закрытие
	if terminal_ui.visible:
		if Input.is_action_just_pressed("ui_cancel"):
			close_terminal()
		return

	# безопасно получаем текущий узел с фокусом (поддержка Godot 3 и 4)
	var focus = null
	if get_tree().has_method("get_focus_owner"):
		focus = get_tree().get_focus_owner()
	elif get_viewport().has_method("get_focus_owner"):
		focus = get_viewport().get_focus_owner()

	# если фокус на UI — не открываем терминал
	if focus and focus is Control:
		return

	# открываем терминал только если игрок в зоне и терминал сейчас НЕ открыт
	if Input.is_action_just_pressed("interact") and player_in_range:
		open_terminal()

func open_terminal() -> void:
	if player_node and player_node.has_method("set_control_enabled"):
		player_node.set_control_enabled(false)

	# Если задание уже закреплено за этим компьютером — не запрашиваем новое
	if current_task.is_empty():
		current_task = DbMeneger.assign_task(level, computer_id)

	# Передаём задание в UI (UI сам не перезапишет текущее, если оно уже есть)
	terminal_ui.call("open_with_task", level, current_task)

	hint_label.visible = false

func close_terminal() -> void:
	terminal_ui.call("close")
	if player_node and player_node.has_method("set_control_enabled"):
		player_node.set_control_enabled(true)

# --- метод для открепления задания после выполнения ---
func unassign_task_if_completed():
	if not current_task.is_empty():
		DbMeneger.unassign_task(current_task["level"], computer_id)
		current_task = {}
