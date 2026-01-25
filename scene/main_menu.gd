extends Control

@onready var main_panel: Control = $TextureRect/VBoxContainer
@onready var settings_menu: Control = $SettingsMenu

func _ready() -> void:
	settings_menu.visible = false
	# когда нажмут "назад" в настройках — вернёмся в главное меню
	if settings_menu.has_signal("back_pressed"):
		settings_menu.back_pressed.connect(_on_settings_back)

func _on_play_pressed() -> void:
	get_tree().change_scene_to_file("res://scene/level/level_1(realno).tscn")

func _on_settings_pressed() -> void:
	main_panel.visible = false
	settings_menu.visible = true

func _on_settings_back() -> void:
	settings_menu.visible = false
	main_panel.visible = true

func _on_exit_pressed() -> void:
	get_tree().quit()
