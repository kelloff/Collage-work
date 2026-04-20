extends Control

@onready var main_panel: Control = $TextureRect/VBoxContainer
@onready var settings_menu: Control = $SettingsMenu

@onready var play_btn: Button = get_node_or_null("TextureRect/VBoxContainer/play")
@onready var continue_btn: Button = get_node_or_null("TextureRect/VBoxContainer/continue")
@onready var settings_btn: Button = get_node_or_null("TextureRect/VBoxContainer/settings")
@onready var exit_btn: Button = get_node_or_null("TextureRect/VBoxContainer/exit")

const NEW_GAME_LOADING := "res://scene/ui/new_game_loading.tscn"

func _ready() -> void:
	_apply_loop_on_music_player_if_present()
	if settings_menu:
		settings_menu.visible = false

	# --- кнопки ---
	if continue_btn:
		continue_btn.pressed.connect(_on_continue_pressed)
		# Continue активна только если есть сейв
		continue_btn.disabled = not Savemeneger.has_save()
	else:
		push_warning("MainMenu: button 'continue' not found (TextureRect/VBoxContainer/continue)")

	if play_btn:
		play_btn.pressed.connect(_on_play_pressed)
	else:
		push_warning("MainMenu: button 'play' not found")

	if settings_btn:
		settings_btn.pressed.connect(_on_settings_pressed)
	else:
		push_warning("MainMenu: button 'settings' not found")

	if exit_btn:
		exit_btn.pressed.connect(_on_exit_pressed)
	else:
		push_warning("MainMenu: button 'exit' not found")

	# назад из настроек
	if settings_menu and settings_menu.has_signal("back_pressed"):
		settings_menu.back_pressed.connect(_on_settings_back)

func _apply_loop_on_music_player_if_present() -> void:
	var p: AudioStreamPlayer = get_node_or_null("music_player") as AudioStreamPlayer
	if p == null or p.stream == null:
		return
	var st: AudioStream = p.stream
	if st is AudioStreamOggVorbis:
		(st as AudioStreamOggVorbis).loop = true
	elif st is AudioStreamWAV:
		(st as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	elif ClassDB.class_exists("AudioStreamMP3") and st is AudioStreamMP3:
		(st as AudioStreamMP3).loop = true

func _on_continue_pressed() -> void:
	Savemeneger.continue_game()

func _on_play_pressed() -> void:
	print("MainMenu: New Game → loading / generation")
	if play_btn:
		play_btn.disabled = true
	get_tree().call_deferred("change_scene_to_file", NEW_GAME_LOADING)

func _on_settings_pressed() -> void:
	main_panel.visible = false
	settings_menu.visible = true

func _on_settings_back() -> void:
	settings_menu.visible = false
	main_panel.visible = true

func _on_exit_pressed() -> void:
	get_tree().quit()
