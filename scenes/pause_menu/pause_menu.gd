extends CanvasLayer

const SETTINGS_SCENE := preload("res://scenes/settings_menu/settings_menu.tscn") # путь проверь
const MAIN_MENU_SCENE := "res://scenes/main_menu/main_menu.tscn" # проверь путь

@onready var pause_panel: Control = get_node_or_null("PausePanel")
@onready var menu_panel: Panel = get_node_or_null("PausePanel/MenuPanel") as Panel
@onready var settings_menu: Control = get_node_or_null("PausePanel/SettingsMenu")

@onready var resume_btn: Button = get_node_or_null("PausePanel/MenuPanel/VBoxContainer/ResumeButton")
@onready var save_btn: Button = get_node_or_null("PausePanel/MenuPanel/VBoxContainer/SaveButton")
@onready var settings_btn: Button = get_node_or_null("PausePanel/MenuPanel/VBoxContainer/SettingsButton")
@onready var exit_btn: Button = get_node_or_null("PausePanel/MenuPanel/VBoxContainer/ExitButton")

var _open: bool = false
var _pause_pushed_world_block: bool = false

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	set_process_unhandled_input(true)
	visible = false
	_style_ui()
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
	if settings_menu:
		settings_menu.visible = false
		settings_menu.z_index = 20
		settings_menu.process_mode = Node.PROCESS_MODE_WHEN_PAUSED


func _style_ui() -> void:
	var menu_panel := get_node_or_null("PausePanel/MenuPanel") as Panel
	if menu_panel:
		GameUiTheme.apply_horror_panel(menu_panel)
	var title: Label = get_node_or_null("PausePanel/MenuPanel/VBoxContainer/Title") as Label
	if title:
		title.label_settings = GameUiTheme.make_horror_title_settings(30)


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
	if menu_panel:
		menu_panel.visible = true

	_freeze_player_for_pause(true)

	if GameState.has_method("push_gameplay_freeze"):
		GameState.push_gameplay_freeze()
	else:
		get_tree().paused = true


func hide_pause() -> void:
	_open = false
	_hide_all_panels()
	visible = false

	_freeze_player_for_pause(false)

	if GameState.has_method("pop_gameplay_freeze"):
		GameState.pop_gameplay_freeze()
	else:
		get_tree().paused = false


func _freeze_player_for_pause(frozen: bool) -> void:
	if frozen:
		if not _pause_pushed_world_block and GameState.has_method("push_world_input_block"):
			GameState.push_world_input_block()
			_pause_pushed_world_block = true
	else:
		if _pause_pushed_world_block and GameState.has_method("pop_world_input_block"):
			GameState.pop_world_input_block()
			_pause_pushed_world_block = false
	var players := get_tree().get_nodes_in_group("player")
	for p in players:
		if p.has_method("set_control_enabled"):
			p.set_control_enabled(not frozen)


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
	if menu_panel:
		menu_panel.visible = false
	if settings_menu:
		settings_menu.visible = true
		if settings_menu.has_method("refresh_pause_ui"):
			settings_menu.refresh_pause_ui()


func _on_settings_back() -> void:
	if settings_menu:
		settings_menu.visible = false
	if menu_panel:
		menu_panel.visible = true


func _on_save_pressed() -> void:
	# Autoload у тебя называется savemanager
	if Engine.has_singleton("Savemeneger") or (typeof(Savemeneger) != TYPE_NIL):
		Savemeneger.save_now()
	else:
		push_warning("PauseMenu: autoload 'savemanager' not found")


func _on_exit_pressed() -> void:
	_freeze_player_for_pause(false)
	if GameState.has_method("clear_gameplay_freeze"):
		GameState.clear_gameplay_freeze()
	else:
		get_tree().paused = false

	if typeof(TutorialManager) != TYPE_NIL and TutorialManager.has_method("prepare_exit_to_main_menu"):
		TutorialManager.prepare_exit_to_main_menu()

	_open = false
	visible = false

	get_tree().change_scene_to_file(MAIN_MENU_SCENE)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		toggle_menu()
		get_viewport().set_input_as_handled()
