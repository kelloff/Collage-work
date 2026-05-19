extends CanvasLayer

signal retry_pressed
signal menu_pressed

const PANEL_MIN_W := 300.0
const PANEL_MAX_W := 540.0
const PANEL_WIDTH_RATIO := 0.9
const PANEL_MAX_H_RATIO := 0.88
const PANEL_MIN_H := 200.0
const BTN_MIN_H := 44.0

@onready var panel: Panel = $Root/Center/Panel
@onready var margin: MarginContainer = $Root/Center/Panel/MarginContainer
@onready var vbox: VBoxContainer = $Root/Center/Panel/MarginContainer/VBox
@onready var stats_label: Label = $Root/Center/Panel/MarginContainer/VBox/StatsLabel
@onready var retry_btn: Button = $Root/Center/Panel/MarginContainer/VBox/Buttons/RetryBtn
@onready var menu_btn: Button = $Root/Center/Panel/MarginContainer/VBox/Buttons/MenuBtn
@onready var dim: ColorRect = $Root/Dim

func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_viewport().size_changed.connect(_on_viewport_resized)

	_style_ui()

	if retry_btn:
		retry_btn.pressed.connect(func(): retry_pressed.emit())
	else:
		push_error("RetryBtn not found.")

	if menu_btn:
		menu_btn.pressed.connect(func(): menu_pressed.emit())
	else:
		push_error("MenuBtn not found.")


func _style_ui() -> void:
	if dim:
		dim.color = Color(0.02, 0.0, 0.02, 0.55)
	if panel:
		GameUiTheme.apply_horror_panel(panel)

	var title: Label = vbox.get_node_or_null("Title") as Label
	if title:
		title.label_settings = GameUiTheme.make_horror_title_settings(32)
	if stats_label:
		stats_label.add_theme_font_size_override("font_size", 15)
		stats_label.add_theme_color_override("font_color", Color(0.96, 0.93, 0.9, 1.0))
		stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	for btn in [retry_btn, menu_btn]:
		if btn:
			btn.custom_minimum_size = Vector2(0, BTN_MIN_H)


func set_stats_text(text: String) -> void:
	if stats_label:
		stats_label.text = text
	call_deferred("_fit_panel")


func _on_viewport_resized() -> void:
	if stats_label and stats_label.text != "":
		call_deferred("_fit_panel")


func _fit_panel() -> void:
	if panel == null or vbox == null or stats_label == null or margin == null:
		return

	var vp := get_viewport().get_visible_rect().size
	var pad_x := float(margin.get_theme_constant("margin_left") + margin.get_theme_constant("margin_right"))
	var pad_y := float(margin.get_theme_constant("margin_top") + margin.get_theme_constant("margin_bottom"))

	var inner_w := clampf(vp.x * PANEL_WIDTH_RATIO - pad_x, PANEL_MIN_W - pad_x, PANEL_MAX_W - pad_x)
	stats_label.custom_minimum_size = Vector2(inner_w, 0)

	var content_min := vbox.get_combined_minimum_size()
	var panel_h := clampf(content_min.y + pad_y, PANEL_MIN_H, vp.y * PANEL_MAX_H_RATIO)
	var panel_w := clampf(content_min.x + pad_x, PANEL_MIN_W, minf(PANEL_MAX_W, vp.x * 0.95))

	panel.custom_minimum_size = Vector2(panel_w, panel_h)
