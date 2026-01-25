extends CanvasLayer

@onready var root: Control = $Control
@onready var pause_panel: Control = $Control/VBoxContainer
@onready var settings_menu: Control = $Control/SettingsMenu

@onready var resume_btn: Button = $Control/VBoxContainer/ResumeButton
@onready var settings_btn: Button = $Control/VBoxContainer/SettingsButton
@onready var exit_btn: Button = $Control/VBoxContainer/ExitButton

const MAIN_MENU_SCENE := "res://scene/main-menu.tscn"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	# скрыто по умолчанию
	hide_all()

	# кнопки паузы
	resume_btn.pressed.connect(_on_resume_pressed)
	settings_btn.pressed.connect(_on_settings_pressed)
	exit_btn.pressed.connect(_on_exit_pressed)

	# кнопка "назад" в настройках
	if settings_menu.has_signal("back_pressed"):
		settings_menu.back_pressed.connect(_on_settings_back)

func show_pause() -> void:
	root.visible = true
	pause_panel.visible = true
	settings_menu.visible = false
	get_tree().paused = true

func show_settings() -> void:
	root.visible = true
	pause_panel.visible = false
	settings_menu.visible = true
	get_tree().paused = true

func hide_all() -> void:
	root.visible = false
	pause_panel.visible = false
	settings_menu.visible = false
	get_tree().paused = false

func toggle_menu() -> void:
	if root.visible:
		hide_all()
	else:
		show_pause()

func _on_resume_pressed() -> void:
	hide_all()

func _on_settings_pressed() -> void:
	show_settings()

func _on_settings_back() -> void:
	show_pause()

func _on_exit_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)
