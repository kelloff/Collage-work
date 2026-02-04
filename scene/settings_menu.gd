extends Control

signal back_pressed

@onready var volume_slider: HSlider = $TextureRect/VBoxContainer/HSlider
@onready var resolution_box: OptionButton = $TextureRect/VBoxContainer/OptionButton
@onready var exit_btn: Button = $TextureRect/VBoxContainer/exit

func _ready() -> void:
	# ---------- ГРОМКОСТЬ ----------
	volume_slider.min_value = -40
	volume_slider.max_value = 0
	volume_slider.step = 1
	volume_slider.value = audio_manager.get_volume_db()

	volume_slider.value_changed.connect(_on_volume_changed)

	# ---------- РАЗРЕШЕНИЕ ----------
	if resolution_box.item_count == 0:
		resolution_box.add_item("Полноэкранный")
		resolution_box.add_item("1280x720")
		resolution_box.add_item("1600x900")
		resolution_box.add_item("1920x1080")

	resolution_box.item_selected.connect(_on_resolution_selected)

	# ---------- ВЫХОД ----------
	exit_btn.pressed.connect(_on_back_pressed)

	
func _on_volume_changed(value: float) -> void:
	audio_manager.set_volume_db(value)

func _on_resolution_selected(index: int) -> void:
	match index:
		0:
			DisplayServer.window_set_mode(
				DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
			)
		1:
			_set_windowed(1280, 720)
		2:
			_set_windowed(1600, 900)
		3:
			_set_windowed(1920, 1080)

func _set_windowed(w: int, h: int):
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_WINDOWED
	)
	DisplayServer.window_set_size(Vector2i(w, h))

func _on_back_pressed() -> void:
	back_pressed.emit()
