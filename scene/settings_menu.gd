extends Control

@onready var volume_slider: HSlider = $TextureRect/VBoxContainer/HSlider
@onready var resolution_box: OptionButton = $TextureRect/VBoxContainer/OptionButton

func _ready():
	# Заполняем список разрешений
	resolution_box.add_item("Полноэкранный")
	resolution_box.add_item("1280x720")
	resolution_box.add_item("1920x1080")

	# Стартовое значение громкости
	volume_slider.value = AudioServer.get_bus_volume_db(0)

func _on_volume_slider_value_changed(value):
	AudioServer.set_bus_volume_db(0, value)

func _on_resolution_box_item_selected(index):
	match index:
		0:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		1:
			DisplayServer.window_set_size(Vector2i(1280, 720))
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		2:
			DisplayServer.window_set_size(Vector2i(1920, 1080))
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

func _on_back_pressed():
	get_tree().change_scene_to_file("res://scene/main-menu.tscn")
