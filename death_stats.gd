extends Control

signal retry_pressed
signal menu_pressed

@onready var stats_label: Label = $Panel/VBoxContainer/StatsLabel
@onready var retry_btn: Button = $Panel/VBoxContainer/HBoxContainer/RetryBtn
@onready var menu_btn: Button = $Panel/VBoxContainer/HBoxContainer/MenuBtn

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	if retry_btn == null:
		push_error("RetryBtn not found. Check node path.")
	else:
		retry_btn.pressed.connect(func(): retry_pressed.emit())

	if menu_btn == null:
		push_error("MenuBtn not found. Check node path.")
	else:
		menu_btn.pressed.connect(func(): menu_pressed.emit())


func set_stats_text(text: String) -> void:
	stats_label.text = text
