extends CanvasLayer

const SETTINGS_SCENE := preload("res://scene/SettingsMenu.tscn") # путь проверь
const MAIN_MENU_SCENE := "res://scene/main-menu.tscn" # проверь путь

@onready var pause_panel: Control = get_node_or_null("PausePanel")
@onready var settings_menu: Control = get_node_or_null("SettingsMenu")

@onready var resume_btn: Button = get_node_or_null("PausePanel/VBoxContainer/ResumeButton")
@onready var save_btn: Button = get_node_or_null("PausePanel/VBoxContainer/SaveButton")
@onready var settings_btn: Button = get_node_or_null("PausePanel/VBoxContainer/SettingsButton")
@onready var exit_btn: Button = get_node_or_null("PausePanel/VBoxContainer/ExitButton")

var _open: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	set_process_unhandled_input(true)
	visible = false
	_hide_all_panels()

	# Подключаем кнопки
	if resume_btn:
		resume_btn.pressed.connect(_on_resume_pressed)
	else:
		push_warning("PauseMenu: ResumeButton not found")

	if save_btn:
		save_btn.pressed.connect(_on_save_pressed)
	else:
		push_warning("PauseMenu: SaveButton not found")

	if settings_btn:
		settings_btn.pressed.connect(_on_settings_pressed)
	else:
		push_warning("PauseMenu: SettingsButton not found")

	if exit_btn:
		exit_btn.pressed.connect(_on_exit_pressed)
	else:
		push_warning("PauseMenu: ExitButton not found")

	# Назад из настроек (если сигнал есть)
	if settings_menu and settings_menu.has_signal("back_pressed"):
		settings_menu.back_pressed.connect(_on_settings_back)
	# Если SettingsMenu не найден — инстансим SettingsMenu.tscn и добавляем
	if settings_menu == null:
		settings_menu = SETTINGS_SCENE.instantiate()
		settings_menu.name = "SettingsMenu"
		add_child(settings_menu)
		settings_menu.visible = false

	# Назад из настроек (если сигнал есть)
	if settings_menu and settings_menu.has_signal("back_pressed"):
		if not settings_menu.back_pressed.is_connected(_on_settings_back):
			settings_menu.back_pressed.connect(_on_settings_back)


func _hide_all_panels() -> void:
	if pause_panel:
		pause_panel.visible = false
	if settings_menu:
		settings_menu.visible = false


func show_pause() -> void:
	_open = true
	visible = true
	_hide_all_panels()
	if pause_panel:
		pause_panel.visible = true

	get_tree().paused = true


func hide_pause() -> void:
	_open = false
	_hide_all_panels()
	visible = false

	get_tree().paused = false


func toggle_menu() -> void:
	if _open:
		hide_pause()
	else:
		show_pause()


func is_open() -> bool:
	return _open

func _on_resume_pressed() -> void:
	hide_pause()


func _on_settings_pressed() -> void:
	if pause_panel:
		pause_panel.visible = false

	if settings_menu:
		settings_menu.visible = true
		settings_menu.process_mode = Node.PROCESS_MODE_WHEN_PAUSED  # важно для UI на паузе


func _on_settings_back() -> void:
	if settings_menu:
		settings_menu.visible = false
	if pause_panel:
		pause_panel.visible = true


func _on_save_pressed() -> void:
	# Autoload у тебя называется savemanager
	if Engine.has_singleton("Savemeneger") or (typeof(Savemeneger) != TYPE_NIL):
		Savemeneger.save_now()
	else:
		push_warning("PauseMenu: autoload 'savemanager' not found")


func _on_exit_pressed() -> void:
	# снимаем паузу ОБЯЗАТЕЛЬНО
	get_tree().paused = false

	# закрываем пауз-меню
	_open = false
	visible = false

	# переходим в главное меню
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		toggle_menu()
		get_viewport().set_input_as_handled()
