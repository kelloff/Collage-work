# res://scripts/Computer.gd
extends Node2D

@onready var area: Area2D = $InteractionArea
@onready var hint_label: Label = $HintLabel
@onready var terminal_ui: CanvasLayer = $TerminalUI
const CODE_EDITOR_PATH := "PanelContainer/HBoxContainer/CodeEditor"

var player_in_range: bool = false
var player_node: Node = null

@export var level: int = 0   # уровень сложности для этого компьютера

func _ready():
	print("Computer ready. Area node:", area)
	if area:
		print("Area monitoring:", area.monitoring, "monitorable:", area.monitorable)
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
	if Input.is_action_just_pressed("interact") and player_in_range:
		open_terminal()
	if terminal_ui.visible and Input.is_action_just_pressed("ui_cancel"):
		close_terminal()

func open_terminal() -> void:
	if player_node and player_node.has_method("set_control_enabled"):
		player_node.set_control_enabled(false)
	# теперь передаём уровень в терминал
	terminal_ui.call("open_with_level", level)
	hint_label.visible = false

func close_terminal() -> void:
	terminal_ui.call("close")
	if player_node and player_node.has_method("set_control_enabled"):
		player_node.set_control_enabled(true)
