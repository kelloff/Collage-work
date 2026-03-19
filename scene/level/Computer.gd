extends Node2D

@onready var area: Area2D = $InteractionArea
@onready var terminal_ui: CanvasLayer = $TerminalUI
@onready var sprite: Sprite2D = $Sprite2D

@export var level: int = 0
@export var computer_id: int = 0
@export var linked_doors: Array = []

var player_in_range: bool = false
var player_node: Node = null
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

	if terminal_ui:
		terminal_ui.visible = false

	outline_material = ShaderMaterial.new()
	if ResourceLoader.exists("res://shaders/outline.gdshader"):
		outline_material.shader = load("res://shaders/outline.gdshader")
		sprite.material = outline_material

	set_outline(false)
	set_highlight(false)

# ---------------- HUD helpers ----------------
func _hud() -> Node:
	return get_tree().current_scene.get_node_or_null("HUD")

func _show_hint(text: String, duration: float = 0.0) -> void:
	var hud = _hud()
	if hud and hud.has_method("show_hint"):
		hud.show_hint(text, duration, self)

func _hide_hint() -> void:
	var hud = _hud()
	if hud and hud.has_method("hide_hint"):
		hud.hide_hint(self)

func _update_hint_for_state() -> void:
	if not player_in_range:
		return
	if DbManager.is_computer_accessible(computer_id):
		_show_hint("E — открыть терминал")
	else:
		_show_hint("❌ Терминал заблокирован")
# --------------------------------------------

func _process(_delta: float) -> void:
	# Если терминал открыт — слушаем закрытие
	if terminal_ui and terminal_ui.visible:
		if Input.is_action_just_pressed("close_terminal"):
			close_terminal()
		return

	if player_in_range and Input.is_action_just_pressed("interact"):
		open_terminal()

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		player_in_range = true
		player_node = body
		set_outline(true)
		set_highlight(true)
		_update_hint_for_state()

func _on_body_exited(body: Node) -> void:
	if body == player_node:
		player_in_range = false
		player_node = null
		set_outline(false)
		set_highlight(false)
		_hide_hint()

func open_terminal() -> void:
	if computer_id == 0:
		return

	if not DbManager.is_computer_accessible(computer_id):
		_show_hint("❌ Терминал заблокирован", 1.5)
		return

	_hide_hint()

	if player_node and player_node.has_method("set_control_enabled"):
		player_node.set_control_enabled(false)

	# 1) Если компьютер уже выполнен — показываем сообщение и
	#    НЕ выдаём новую задачу.
	if DbManager.is_computer_done(level, computer_id):
		current_task = {"message": "Ты уже выполнил это задание, продвигайся дальше"}
	else:
		# 2) Иначе если задача была закреплена ранее — используем её,
		#    даже если БД/таблицы временно ведут себя нестабильно.
		var cached: Dictionary = DbManager.get_assigned_task(level, computer_id)
		if not cached.is_empty():
			current_task = cached
		else:
			# 3) Пытаемся взять задачу из БД; если пусто — назначаем новую.
			refresh_current_task()
			if current_task.is_empty():
				current_task = DbManager.assign_task(level, computer_id)
			# Закрепляем задачу в памяти на время сессии, чтобы она не
			# повторялась при повторном заходе.
			DbManager.set_assigned_task(level, computer_id, current_task)

	if terminal_ui and terminal_ui.has_method("open_with_task"):
		terminal_ui.call("open_with_task", level, current_task)

func close_terminal() -> void:
	if terminal_ui and terminal_ui.has_method("close"):
		terminal_ui.call("close")

	if player_node and player_node.has_method("set_control_enabled"):
		player_node.set_control_enabled(true)

	_update_hint_for_state()

func set_outline(enabled: bool) -> void:
	if outline_material:
		outline_material.set_shader_parameter("enabled", enabled)

func set_highlight(enabled: bool) -> void:
	if outline_material:
		outline_material.set_shader_parameter("highlight", enabled)

func unassign_task_if_completed() -> void:
	if computer_id == 0:
		return

	print("Computer.unassign_task_if_completed: level=%d computer_id=%d" % [level, computer_id])
	var finished_task: Dictionary = current_task
	DbManager.unassign_task(level, computer_id)
	DbManager.mark_computer_done(level, computer_id)
	# Сохраняем последнюю задачу как закреплённую (на будущее сообщение/контекст).
	if not finished_task.is_empty():
		DbManager.set_assigned_task(level, computer_id, finished_task)
	current_task = {}

	var door_ids = DbManager.get_doors_for_computer(computer_id)
	if door_ids.size() == 0:
		if linked_doors.size() > 0:
			door_ids = linked_doors.duplicate()
		else:
			return

	var doors = get_tree().get_nodes_in_group("doors")
	for did in door_ids:
		for d in doors:
			if ("door_id" in d) and int(d.door_id) == int(did):
				if d.has_method("open"):
					d.open()

func refresh_current_task() -> void:
	if computer_id == 0:
		return
	current_task = DbManager.get_current_task(level, computer_id)
