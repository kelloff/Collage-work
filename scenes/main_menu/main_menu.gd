extends Control

@onready var main_panel: Control = $TextureRect/VBoxContainer
@onready var settings_menu: Control = $SettingsMenu

@onready var play_btn: Button = get_node_or_null("TextureRect/VBoxContainer/play")
@onready var continue_btn: Button = get_node_or_null("TextureRect/VBoxContainer/continue")
@onready var settings_btn: Button = get_node_or_null("TextureRect/VBoxContainer/settings")
@onready var exit_btn: Button = get_node_or_null("TextureRect/VBoxContainer/exit")
@onready var tutorial_toggle: Button = get_node_or_null("TextureRect/VBoxContainer/tutorial_hint")
@onready var _new_game_confirm: Control = $NewGameConfirmDialog

const NEW_GAME_LOADING := "res://scenes/new_game_loading/new_game_loading.tscn"

func _ready() -> void:
	if typeof(TutorialManager) != TYPE_NIL and TutorialManager.has_method("cleanup_overlays"):
		TutorialManager.cleanup_overlays()
	_style_ui()
	_apply_loop_on_music_player_if_present()
	if settings_menu:
		settings_menu.visible = false

	# --- кнопки (в .tscn уже есть connection; подключаем только если ещё нет) ---
	if continue_btn:
		_connect_pressed_once(continue_btn, _on_continue_pressed)
		_apply_continue_button_state()
	else:
		push_warning("MainMenu: button 'continue' not found (TextureRect/VBoxContainer/continue)")

	if play_btn:
		_connect_pressed_once(play_btn, _on_play_pressed)
	else:
		push_warning("MainMenu: button 'play' not found")

	if settings_btn:
		_connect_pressed_once(settings_btn, _on_settings_pressed)
	else:
		push_warning("MainMenu: button 'settings' not found")

	if exit_btn:
		_connect_pressed_once(exit_btn, _on_exit_pressed)
	else:
		push_warning("MainMenu: button 'exit' not found")

	# назад из настроек
	if settings_menu and settings_menu.has_signal("back_pressed"):
		settings_menu.back_pressed.connect(_on_settings_back)

	if tutorial_toggle:
		tutorial_toggle.toggled.connect(_on_tutorial_toggled)
		_refresh_tutorial_toggle()

func _connect_pressed_once(btn: Button, handler: Callable) -> void:
	if not btn.pressed.is_connected(handler):
		btn.pressed.connect(handler)


func _style_ui() -> void:
	var title: Label = get_node_or_null("TextureRect/VBoxContainer/Label") as Label
	if title:
		title.label_settings = GameUiTheme.make_title_settings(40)
		title.text = "The Last Code"
	for path in ["play", "continue", "settings", "exit", "tutorial_hint"]:
		var btn := get_node_or_null("TextureRect/VBoxContainer/%s" % path) as Button
		if btn:
			btn.custom_minimum_size = Vector2(280, 54)
			btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			btn.focus_mode = Control.FOCUS_NONE
			btn.text = btn.text.strip_edges()
	if tutorial_toggle:
		tutorial_toggle.toggle_mode = true

func _on_tutorial_toggled(_pressed: bool) -> void:
	_refresh_tutorial_toggle()

func _refresh_tutorial_toggle() -> void:
	if tutorial_toggle == null:
		return
	var on: bool = tutorial_toggle.button_pressed
	tutorial_toggle.text = "Обучение: включено" if on else "Обучение: выключено"
	tutorial_toggle.modulate = Color(0.92, 1.0, 0.95) if on else Color(0.72, 0.72, 0.76)

func _apply_loop_on_music_player_if_present() -> void:
	var p: AudioStreamPlayer = get_node_or_null("music_player") as AudioStreamPlayer
	if p == null or p.stream == null:
		return
	var st: AudioStream = p.stream
	if st is AudioStreamOggVorbis:
		st.loop = true
	elif st is AudioStreamWAV:
		st.loop_mode = AudioStreamWAV.LOOP_FORWARD
	elif ClassDB.class_exists("AudioStreamMP3") and st is AudioStreamMP3:
		st.loop = true

func _on_continue_pressed() -> void:
	TutorialManager.set_enabled(false)
	Savemeneger.continue_game()

func _apply_continue_button_state() -> void:
	if continue_btn == null:
		return
	var has_save: bool = Savemeneger.has_save()
	continue_btn.disabled = not has_save
	if has_save:
		continue_btn.modulate = Color(1.0, 1.0, 1.0, 1.0)
		continue_btn.tooltip_text = "Продолжить сохранённую игру"
	else:
		continue_btn.modulate = Color(0.42, 0.42, 0.48, 1.0)
		continue_btn.tooltip_text = "Нет сохранения — начните новую игру"


func _on_play_pressed() -> void:
	if Savemeneger.has_save() and _new_game_confirm:
		_new_game_confirm.open(
			"Новая игра",
			"Начать новую игру?",
			"Начать заново",
			"Отмена",
			"Текущее сохранение и прогресс будут перезаписаны.",
			_start_new_game_flow
		)
		return
	_start_new_game_flow()


func _start_new_game_flow() -> void:
	print("MainMenu: New Game → loading / generation")
	if play_btn:
		play_btn.disabled = true
	var with_tutorial := true
	if tutorial_toggle:
		with_tutorial = tutorial_toggle.button_pressed
	TutorialManager.set_enabled(with_tutorial)
	get_tree().call_deferred("change_scene_to_file", NEW_GAME_LOADING)

func _on_settings_pressed() -> void:
	main_panel.visible = false
	settings_menu.visible = true

func _on_settings_back() -> void:
	settings_menu.visible = false
	main_panel.visible = true

func _on_exit_pressed() -> void:
	get_tree().quit()
