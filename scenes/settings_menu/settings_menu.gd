extends Control

signal back_pressed

@onready var _bg_texture: TextureRect = get_node_or_null("TextureRect") as TextureRect
@onready var _dim: ColorRect = get_node_or_null("Dim") as ColorRect
@onready var _master_slider: HSlider = $MenuPanel/VBoxContainer/MasterVolumeSlider
@onready var _music_slider: HSlider = $MenuPanel/VBoxContainer/MusicVolumeSlider
@onready var exit_btn: Button = $MenuPanel/VBoxContainer/exit


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_INHERIT
	_style_ui()
	_setup_sliders()


func refresh_pause_ui() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_style_ui()
	_sync_sliders_from_audio()


func _setup_sliders() -> void:
	for sl in [_master_slider, _music_slider]:
		if sl == null:
			continue
		sl.min_value = audio_manager.MIN_DB
		sl.max_value = audio_manager.MAX_DB
		sl.step = 1.0

	_sync_sliders_from_audio()

	if _master_slider:
		_master_slider.value_changed.connect(_on_master_volume_changed)
	if _music_slider:
		_music_slider.value_changed.connect(_on_music_volume_changed)
	if exit_btn:
		exit_btn.pressed.connect(_on_back_pressed)


func _sync_sliders_from_audio() -> void:
	if _master_slider:
		_master_slider.set_value_no_signal(audio_manager.get_master_volume_db())
	if _music_slider:
		_music_slider.set_value_no_signal(audio_manager.get_music_volume_db())


func _style_ui() -> void:
	if _bg_texture:
		_bg_texture.visible = false
	if _dim:
		_dim.visible = true
		_dim.color = Color(0.04, 0.02, 0.08, 0.72)
	var menu_panel := get_node_or_null("MenuPanel") as Panel
	if menu_panel:
		GameUiTheme.apply_horror_panel(menu_panel)
	var title: Label = get_node_or_null("MenuPanel/VBoxContainer/Label") as Label
	if title:
		title.label_settings = GameUiTheme.make_horror_title_settings(28)
	for path in ["MasterVolumeSlider", "MusicVolumeSlider", "exit"]:
		var c := get_node_or_null("MenuPanel/VBoxContainer/%s" % path) as Control
		if c is Button:
			c.custom_minimum_size = Vector2(0, 48)


func _on_master_volume_changed(value: float) -> void:
	audio_manager.set_master_volume_db(value)


func _on_music_volume_changed(value: float) -> void:
	audio_manager.set_music_volume_db(value)


func _on_back_pressed() -> void:
	back_pressed.emit()
