extends Node2D

@onready var area: Area2D = $InteractionArea
@onready var terminal_ui: CanvasLayer = $TerminalUI
@onready var sprite: Sprite2D = $Sprite2D

var player_in_range: bool = false
var player_node: Node = null

@export var level: int = 0
@export var computer_id: int = 0
@export var linked_doors: Array = []  # список door_id через инспектор

var current_task: Dictionary = {}
var outline_material: ShaderMaterial

func _enter_tree() -> void:
	if not is_in_group("computers"):
		add_to_group("computers")

func _ready() -> void:
	if computer_id == 0:
		push_warning("Computer '%s' has computer_id = 0. Set it in inspector." % name)

	if area:
		area.body_entered.connect(_on_body_entered)
		area.body_exited.connect(_on_body_exited)
	else:
		push_error("InteractionArea not found in Computer '%s'" % name)

	# Terminal UI скрываем по умолчанию
	if terminal_ui:
		terminal_ui.visible = false

	# Outline material
	outline_material = ShaderMaterial.new()
	if ResourceLoader.exists("res://shaders/outline.gdshader"):
		outline_material.shader = load("res://shaders/outline.gdshader")
		sprite.material = outline_material

	set_outline(false)
	set_highlight(false)

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		player_in_range = true
		player_node = body
		set_outline(true)
		set_highlight(true)

func _on_body_exited(body: Node) -> void:
	if body == player_node:
		player_in_range = false
		player_node = null
		set_outline(false)
		set_highlight(false)

func _process(_delta: float) -> void:
	# Если терминал открыт — слушаем отмену
	if terminal_ui and terminal_ui.visible:
		if Input.is_action_just_pressed("ui_cancel"):
			close_terminal()
		return

	# Взаимодействие
	if Input.is_action_just_pressed("interact") and player_in_range:
		open_terminal()

func open_terminal() -> void:
	if computer_id == 0:
		print("Computer '%s' has computer_id = 0 — set it in inspector" % name)
		return

	# Проверяем доступность через DbMeneger (связан с рычагами)
	if not DbMeneger.is_computer_accessible(computer_id):
		print("❌ Терминал заблокирован: не все рычаги опущены (computer_id=", computer_id, ")")
		return

	print("✅ Терминал доступен, открываем (computer_id=", computer_id, ")")
	if player_node and player_node.has_method("set_control_enabled"):
		player_node.set_control_enabled(false)

	# Назначаем задачу, если ещё нет
	if current_task.is_empty():
		current_task = DbMeneger.assign_task(level, computer_id)

	# Открываем UI терминала и передаём задачу
	if terminal_ui and terminal_ui.has_method("open_with_task"):
		terminal_ui.call("open_with_task", level, current_task)

func close_terminal() -> void:
	if terminal_ui and terminal_ui.has_method("close"):
		terminal_ui.call("close")
	if player_node and player_node.has_method("set_control_enabled"):
		player_node.set_control_enabled(true)

func set_outline(enabled: bool) -> void:
	if outline_material:
		outline_material.set_shader_parameter("enabled", enabled)

func set_highlight(enabled: bool) -> void:
	if outline_material:
		outline_material.set_shader_parameter("highlight", enabled)

# Этот метод вызывается из TerminalUI после успешной проверки решения
# Он помечает задачу как выполненную и открывает связанные двери
func unassign_task_if_completed() -> void:
	# Защита: проверим, что у нас есть назначенная задача и корректный id
	if computer_id == 0:
		print("Computer.unassign_task_if_completed: invalid computer_id (0)")
		return

	# Помечаем assigned -> done в таблице progress
	DbMeneger.unassign_task(level, computer_id)
	print("Computer: task marked done for computer_id=", computer_id, " level=", level)

	# Сбрасываем локальную текущую задачу
	current_task = {}

	# Получаем список дверей, связанных с этим компьютером, и открываем их
	var door_ids = DbMeneger.get_doors_for_computer(computer_id)
	if door_ids.size() == 0:
		# Если в БД нет связей, попробуем использовать linked_doors из инспектора
		if linked_doors.size() > 0:
			door_ids = linked_doors.duplicate()
		else:
			print("Computer: no doors linked to computer", computer_id)
			return

	var doors = get_tree().get_nodes_in_group("doors")
	for did in door_ids:
		for d in doors:
			# Защита: у двери должно быть поле door_id и метод open()
			if ("door_id" in d) and int(d.door_id) == int(did):
				if d.has_method("open"):
					d.open()
					print("Computer: opened door id=", did, " (node=", d.name, ")")
				else:
					print("Computer: door node", d.name, "has no method open()")

# Утилита: обновить состояние текущей задачи (если нужно)
func refresh_current_task() -> void:
	if computer_id == 0:
		return
	current_task = DbMeneger.get_current_task(level, computer_id)
