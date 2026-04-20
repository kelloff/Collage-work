extends CanvasLayer

@onready var new_game_btn: Button = $Panel/CenterContainer/VBoxContainer/NewGameButton
@onready var exit_btn: Button = $Panel/CenterContainer/VBoxContainer/ExitButton

const MAIN_MENU_SCENE := "res://scene/main-menu.tscn"

func _ready() -> void:
	print("WinUI READY")
	visible = false
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED  # ок

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

	# скрываем подсказку B-руководство (если есть)
	var hud := get_parent()
	if hud and hud.has_method("hide_hint"):
		hud.hide_hint() # твой метод из hint_ui.gd

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true

	if new_game_btn:
		new_game_btn.grab_focus()

func _on_new_game_pressed() -> void:
	print("WinUI: New Game → loading / generation")
	get_tree().paused = false
	get_tree().call_deferred("change_scene_to_file", "res://scene/ui/new_game_loading.tscn")

func _on_exit_pressed() -> void:
	print("WinUI: Exit to Main Menu")
	get_tree().paused = false
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)
