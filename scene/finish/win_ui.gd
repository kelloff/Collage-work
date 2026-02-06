extends CanvasLayer

@onready var new_game_btn: Button = $Panel/CenterContainer/VBoxContainer/NewGameButton
@onready var exit_btn: Button = $Panel/CenterContainer/VBoxContainer/ExitButton

const LEVEL_SCENE := "res://scene/level/level_1(realno).tscn"
const MAIN_MENU_SCENE := "res://scene/main-menu.tscn"

func _ready() -> void:
	print("WinUI READY")
	visible = false
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED

	if new_game_btn:
		new_game_btn.pressed.connect(_on_new_game_pressed)
	else:
		push_warning("WinUI: NewGameButton not found")

	if exit_btn:
		exit_btn.pressed.connect(_on_exit_pressed)
	else:
		push_warning("WinUI: ExitButton not found")

func show_win() -> void:
	print("WinUI SHOW")
	visible = true

	# 🔴 скрываем подсказку B-руководство
	var hud := get_parent()
	if hud and hud.has_method("hide_persistent_hint"):
		hud.hide_persistent_hint()

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true

	if new_game_btn:
		new_game_btn.grab_focus()

func _on_new_game_pressed() -> void:
	print("WinUI: New Game")

	# 1. полный сброс сейва (как в main menu)
	savemanager.reset_save()

	# 2. обязательно снимаем паузу
	get_tree().paused = false

	# 3. загружаем первый уровень
	get_tree().change_scene_to_file(LEVEL_SCENE)

func _on_exit_pressed() -> void:
	print("WinUI: Exit to Main Menu")

	get_tree().paused = false
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)
	
