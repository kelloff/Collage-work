extends CanvasLayer

@onready var new_game_btn: Button = $Panel/Cenyterbox/VBoxContainer/NewGameButton
@onready var exit_btn: Button = $Panel/Cenyterbox/VBoxContainer/ExitButton
@onready var stats_label: Label = $Panel/Cenyterbox/StatsLabel

const MAIN_MENU_SCENE := "res://scenes/main_menu/main_menu.tscn"

func _ready() -> void:
	print("WinUI READY")
	visible = false
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_style_ui()

	if new_game_btn:
		new_game_btn.pressed.connect(_on_new_game_pressed)
	else:
		push_warning("WinUI: NewGameButton not found")

	if exit_btn:
		exit_btn.pressed.connect(_on_exit_pressed)
	else:
		push_warning("WinUI: ExitButton not found")

func _style_ui() -> void:
	var panel := get_node_or_null("Panel") as Panel
	if panel:
		GameUiTheme.apply_horror_panel(panel)
	var title: Label = get_node_or_null("Panel/Cenyterbox/Label") as Label
	if title:
		title.label_settings = GameUiTheme.make_horror_title_settings(36)
	if stats_label:
		stats_label.add_theme_font_size_override("font_size", 16)
		stats_label.add_theme_color_override("font_color", Color(0.88, 0.95, 0.9, 1.0))
		stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func show_win() -> void:
	print("WinUI SHOW")
	RunStats.refresh_from_db()
	if stats_label:
		stats_label.text = RunStats.build_report_text(true)
	RunStats.try_save_best_score(true)

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
	get_tree().call_deferred("change_scene_to_file", "res://scenes/new_game_loading/new_game_loading.tscn")

func _on_exit_pressed() -> void:
	print("WinUI: Exit to Main Menu")
	get_tree().paused = false
	if typeof(TutorialManager) != TYPE_NIL and TutorialManager.has_method("prepare_exit_to_main_menu"):
		TutorialManager.prepare_exit_to_main_menu()
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)
