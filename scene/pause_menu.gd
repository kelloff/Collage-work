extends CanvasLayer

@onready var root: Control = $Control
@onready var pause_panel: Control = $Control/VBoxContainer
@onready var settings_menu: Control = $Control/SettingsMenu

@onready var resume_btn: Button = $Control/VBoxContainer/ResumeButton
@onready var settings_btn: Button = $Control/VBoxContainer/SettingsButton
@onready var save_btn: Button = $Control/VBoxContainer/SaveButton
@onready var exit_btn: Button = $Control/VBoxContainer/ExitButton

const MAIN_MENU_SCENE := "res://scene/main-menu.tscn"
func _enter_tree() -> void:
	print(">>> PauseMenu _enter_tree called; node path:", get_path())


func _ready() -> void:
	print("PauseMenu _ready() called; node path:", get_path())
	print("PauseMenu: Engine.has_singleton list:", Engine.get_singleton_list())
	print("PauseMenu: get_node_or_null('/root/SaveMeneger') =", get_node_or_null("/root/SaveMeneger"))

	process_mode = Node.PROCESS_MODE_ALWAYS
	hide_all()

	# подключаем кнопки
	resume_btn.pressed.connect(_on_resume_pressed)
	settings_btn.pressed.connect(_on_settings_pressed)
	save_btn.pressed.connect(_on_save_pressed)
	exit_btn.pressed.connect(_on_exit_pressed)

	# кнопка "назад" в настройках
	if settings_menu.has_signal("back_pressed"):
		settings_menu.back_pressed.connect(_on_settings_back)
	if Engine.has_singleton("SaveMeneger"):
		print("PauseMenu: SaveMeneger доступен как глобальный синглтон")
	else:
		print("PauseMenu: SaveMeneger НЕ доступен — проверь Autoload")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_menu"): # pause_menu = Esc
		toggle_menu()

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
	if root.is_visible_in_tree():
		hide_all()
	else:
		show_pause()

func _on_resume_pressed() -> void:
	hide_all()

func _on_settings_pressed() -> void:
	show_settings()

func _on_settings_back() -> void:
	show_pause()

func _on_save_pressed() -> void:
	if Engine.has_singleton("SaveMeneger"):
		SaveMeneger.save_game()
		print("PauseMenu: игра сохранена")

func _on_exit_pressed() -> void:
	if Engine.has_singleton("SaveMeneger"):
		SaveMeneger.save_game()
		print("PauseMenu: авто‑сохранение перед выходом")
	else:
		print("lox")
	get_tree().paused = false
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)
