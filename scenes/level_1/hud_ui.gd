# res://ui/hint_ui.gd
extends CanvasLayer

@onready var panel: Panel = $HintPanel
@onready var persistent_hint: Label = $HintPanel/PersistentHint
@onready var dynamic_hint: Label = $HintPanel/HintLabel
@onready var timer: Timer = $HintPanel/HintTimer

var _owner: Object = null
var _hp_panel: PanelContainer
var _hearts_row: HBoxContainer
var _hp_value_label: Label
var _blood_bar: ProgressBar
var _heart_labels: Array[Label] = []
var _player: Node = null
var _last_hp: int = -1
var _low_hp_pulse: Tween
var _heart_pulse_tweens: Array[Tween] = []

const HUD_LAYER := 20
const HP_OVERLAY_LAYER := 32

const C_BLOOD := Color(0.78, 0.05, 0.08, 1.0)
const C_BLOOD_GLOW := Color(1.0, 0.22, 0.18, 1.0)
const C_BLOOD_EMPTY := Color(0.32, 0.28, 0.3, 0.72)
const C_ASH := Color(0.82, 0.78, 0.8, 1.0)
const C_PALE := Color(0.92, 0.88, 0.9, 1.0)

var _hp_canvas: CanvasLayer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = HUD_LAYER

	GameUiTheme.apply_horror_panel(panel)
	panel.visible = true

	persistent_hint.add_theme_color_override("font_color", GameUiTheme.C_TEXT)
	persistent_hint.text = "B — руководство"
	persistent_hint.visible = true

	dynamic_hint.add_theme_color_override("font_color", GameUiTheme.C_HORROR_OUTLINE)
	dynamic_hint.visible = false

	timer.one_shot = true
	timer.timeout.connect(hide_hint)

	_setup_hp_display()
	call_deferred("_bind_player")


func _exit_tree() -> void:
	if _hp_canvas and is_instance_valid(_hp_canvas):
		_hp_canvas.queue_free()
		_hp_canvas = null


func _make_horror_hp_panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.08, 0.04, 0.05, 0.94)
	s.border_color = Color(0.72, 0.12, 0.14, 0.95)
	s.border_width_left = 1
	s.border_width_top = 1
	s.border_width_right = 1
	s.border_width_bottom = 2
	s.corner_radius_top_left = 4
	s.corner_radius_top_right = 4
	s.corner_radius_bottom_right = 4
	s.corner_radius_bottom_left = 4
	s.content_margin_left = 12.0
	s.content_margin_top = 10.0
	s.content_margin_right = 12.0
	s.content_margin_bottom = 10.0
	s.shadow_color = Color(0.35, 0.0, 0.02, 0.45)
	s.shadow_size = 10
	s.shadow_offset = Vector2(0, 2)
	return s

func _make_blood_bar_styles() -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.06, 0.03, 0.04, 0.95)
	track.border_color = Color(0.28, 0.03, 0.05, 0.6)
	track.set_border_width_all(1)
	track.set_corner_radius_all(2)
	track.content_margin_left = 1.0
	track.content_margin_top = 1.0
	track.content_margin_right = 1.0
	track.content_margin_bottom = 1.0

	var fill := StyleBoxFlat.new()
	fill.bg_color = C_BLOOD
	fill.set_corner_radius_all(1)

	_blood_bar.add_theme_stylebox_override("background", track)
	_blood_bar.add_theme_stylebox_override("fill", fill)

func _setup_hp_display() -> void:
	_hp_panel = PanelContainer.new()
	_hp_panel.name = "HpPanel"
	add_child(_hp_panel)

	_hp_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_hp_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_hp_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hp_panel.offset_left = -188.0
	_hp_panel.offset_top = -108.0
	_hp_panel.offset_right = -12.0
	_hp_panel.offset_bottom = -12.0
	_hp_panel.add_theme_stylebox_override("panel", _make_horror_hp_panel_style())

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 4)
	margin.add_theme_constant_override("margin_top", 2)
	margin.add_theme_constant_override("margin_right", 4)
	margin.add_theme_constant_override("margin_bottom", 2)
	_hp_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "ЖИЗНЬ"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var title_ls := LabelSettings.new()
	if ResourceLoader.exists(GameUiTheme.FONT_DISPLAY):
		title_ls.font = load(GameUiTheme.FONT_DISPLAY)
	title_ls.font_size = 14
	title_ls.font_color = C_ASH
	title_ls.outline_size = 2
	title_ls.outline_color = Color(0.18, 0.02, 0.04, 0.9)
	title.label_settings = title_ls
	vbox.add_child(title)

	_hearts_row = HBoxContainer.new()
	_hearts_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_hearts_row.add_theme_constant_override("separation", 10)
	vbox.add_child(_hearts_row)

	_blood_bar = ProgressBar.new()
	_blood_bar.custom_minimum_size = Vector2(148, 9)
	_blood_bar.show_percentage = false
	_blood_bar.max_value = 3.0
	_blood_bar.value = 3.0
	_make_blood_bar_styles()
	vbox.add_child(_blood_bar)

	_hp_value_label = Label.new()
	_hp_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_value_label.add_theme_font_size_override("font_size", 13)
	_hp_value_label.add_theme_color_override("font_color", C_PALE)
	vbox.add_child(_hp_value_label)

	_mount_hp_above_canvas_modulate()

func _mount_hp_above_canvas_modulate() -> void:
	if _hp_panel == null:
		return
	var parent := _hp_panel.get_parent()
	if parent:
		parent.remove_child(_hp_panel)
	if _hp_canvas == null or not is_instance_valid(_hp_canvas):
		_hp_canvas = CanvasLayer.new()
		_hp_canvas.name = "HpHudOverlay"
		_hp_canvas.layer = HP_OVERLAY_LAYER
		_hp_canvas.process_mode = Node.PROCESS_MODE_ALWAYS
		get_tree().root.add_child(_hp_canvas)
	_hp_canvas.add_child(_hp_panel)
	_hp_panel.self_modulate = Color.WHITE
	_hp_panel.modulate = Color.WHITE

func _bind_player() -> void:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	_player = players[0]
	if _player.has_signal("hp_changed"):
		_player.hp_changed.connect(_on_hp_changed)
	var max_hp := 3
	if "max_hp" in _player:
		max_hp = int(_player.max_hp)
	var current_hp := max_hp
	if _player.has_method("get_hp"):
		current_hp = int(_player.get_hp())
	_rebuild_hearts(max_hp)
	_on_hp_changed(current_hp, max_hp)

func _rebuild_hearts(max_hp: int) -> void:
	for heart in _heart_labels:
		heart.queue_free()
	_heart_labels.clear()

	for _i in range(max_hp):
		var heart := Label.new()
		heart.text = "♥"
		heart.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		heart.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		heart.add_theme_font_size_override("font_size", 28)
		heart.modulate = Color.WHITE
		heart.add_theme_color_override("font_outline_color", Color(0.12, 0.02, 0.04, 0.95))
		heart.add_theme_constant_override("outline_size", 2)
		_hearts_row.add_child(heart)
		_heart_labels.append(heart)

func _on_hp_changed(current: int, maximum: int) -> void:
	if _heart_labels.size() != maximum:
		_rebuild_hearts(maximum)

	for i in range(maximum):
		var heart := _heart_labels[i]
		var filled := i < current
		heart.modulate = Color.WHITE
		heart.add_theme_color_override(
			"font_color",
			C_BLOOD_GLOW if filled else C_BLOOD_EMPTY
		)
		heart.scale = Vector2.ONE

	if _blood_bar:
		_blood_bar.max_value = float(maximum)
		_blood_bar.value = float(current)
		var fill_style := _blood_bar.get_theme_stylebox("fill") as StyleBoxFlat
		if fill_style:
			fill_style.bg_color = C_BLOOD_GLOW if current <= 1 else C_BLOOD

	_hp_value_label.text = _format_hp_text(current, maximum)
	_hp_value_label.add_theme_color_override(
		"font_color",
		C_BLOOD_GLOW if current <= 1 else C_PALE
	)

	_update_low_hp_pulse(current)

	if _last_hp >= 0 and current < _last_hp and current >= 0 and current < _heart_labels.size():
		_pulse_heart(_heart_labels[current])
		_pulse_hp_panel()

	_last_hp = current

func _format_hp_text(current: int, maximum: int) -> String:
	var numerals: PackedStringArray = PackedStringArray(["0", "I", "II", "III", "IV", "V"])
	var cur_s: String = numerals[current] if current >= 0 and current < numerals.size() else str(current)
	var max_s: String = numerals[maximum] if maximum >= 0 and maximum < numerals.size() else str(maximum)
	return "%s / %s" % [cur_s, max_s]

func _update_low_hp_pulse(current: int) -> void:
	if _low_hp_pulse and _low_hp_pulse.is_valid():
		_low_hp_pulse.kill()
		_low_hp_pulse = null
	for ht in _heart_pulse_tweens:
		if ht and ht.is_valid():
			ht.kill()
	_heart_pulse_tweens.clear()

	if _hp_panel:
		_hp_panel.modulate = Color.WHITE

	if current > 1:
		for heart in _heart_labels:
			if heart.get_theme_color("font_color") != C_BLOOD_EMPTY:
				heart.add_theme_color_override("font_color", C_BLOOD_GLOW)
		return

	_low_hp_pulse = create_tween()
	_low_hp_pulse.set_loops()
	_low_hp_pulse.set_trans(Tween.TRANS_SINE)
	_low_hp_pulse.set_ease(Tween.EASE_IN_OUT)
	_low_hp_pulse.tween_property(_hp_panel, "modulate", Color(1.0, 0.9, 0.9, 1.0), 0.55)
	_low_hp_pulse.tween_property(_hp_panel, "modulate", Color(0.92, 0.86, 0.88, 1.0), 0.55)

	for heart in _heart_labels:
		if heart.get_theme_color("font_color") == C_BLOOD_EMPTY:
			continue
		var ht := create_tween()
		ht.set_loops()
		ht.set_trans(Tween.TRANS_SINE)
		ht.set_ease(Tween.EASE_IN_OUT)
		ht.tween_method(
			func(c: Color) -> void: heart.add_theme_color_override("font_color", c),
			C_BLOOD,
			C_BLOOD_GLOW,
			0.55
		)
		ht.tween_method(
			func(c: Color) -> void: heart.add_theme_color_override("font_color", c),
			C_BLOOD_GLOW,
			C_BLOOD,
			0.55
		)
		_heart_pulse_tweens.append(ht)

func _pulse_heart(heart: Label) -> void:
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_ELASTIC)
	tween.set_ease(Tween.EASE_OUT)
	heart.add_theme_color_override("font_color", Color(1.0, 0.35, 0.28, 1.0))
	heart.scale = Vector2(1.4, 1.4)
	tween.tween_property(heart, "scale", Vector2.ONE, 0.35)
	tween.parallel().tween_method(
		func(c: Color) -> void: heart.add_theme_color_override("font_color", c),
		Color(1.0, 0.35, 0.28, 1.0),
		C_BLOOD_EMPTY,
		0.45
	)

func _pulse_hp_panel() -> void:
	if _hp_panel == null:
		return
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_EXPO)
	tween.set_ease(Tween.EASE_OUT)
	_hp_panel.modulate = Color(1.15, 0.35, 0.38, 1.0)
	tween.tween_property(_hp_panel, "modulate", Color.WHITE, 0.5)

func show_hint(text: String, duration: float = 0.0, owner: Object = null) -> void:
	_owner = owner
	dynamic_hint.text = text
	dynamic_hint.visible = true

	if duration > 0.0:
		timer.stop()
		timer.start(duration)

func hide_hint(owner: Object = null) -> void:
	if owner != null and _owner != owner:
		return

	dynamic_hint.visible = false
	_owner = null
	timer.stop()

func hide_persistent_hint() -> void:
	panel.visible = false
	_owner = null
	timer.stop()
