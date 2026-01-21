extends Node2D

@onready var area: Area2D = $InteractionArea
@onready var terminal_ui: CanvasLayer = $TerminalUI
@onready var sprite: Sprite2D = $Sprite2D

var player_in_range: bool = false
var player_node: Node = null

@export var level: int = 0
@export var computer_id: int = 0

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

	terminal_ui.visible = false

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
	if terminal_ui.visible:
		if Input.is_action_just_pressed("ui_cancel"):
			close_terminal()
		return

	if Input.is_action_just_pressed("interact") and player_in_range:
		open_terminal()

func open_terminal() -> void:
	if computer_id == 0:
		print("Computer '%s' has computer_id = 0 — set it in inspector" % name)
		return

	if not DbMeneger.is_computer_accessible(computer_id):
		print("❌ Терминал заблокирован: не все рычаги опущены (computer_id=", computer_id, ")")
		return

	print("✅ Терминал доступен, открываем (computer_id=", computer_id, ")")
	if player_node and player_node.has_method("set_control_enabled"):
		player_node.set_control_enabled(false)

	if current_task.is_empty():
		current_task = DbMeneger.assign_task(level, computer_id)

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
