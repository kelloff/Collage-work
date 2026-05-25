extends CanvasLayer

const MAIN_MENU_SCENE := "res://scenes/main_menu/main_menu.tscn"
const PANEL_MIN_W := 400.0
const PANEL_MAX_W := 620.0
const PANEL_WIDTH_RATIO := 0.92
const PANEL_MAX_H_RATIO := 0.88
const PANEL_MIN_H := 320.0
const STATS_SCROLL_MIN_H := 180.0
const STATS_SCROLL_MAX_H := 320.0
const BTN_MIN_H := 48.0

@onready var panel: Panel = $Root/Center/Panel
@onready var margin: MarginContainer = $Root/Center/Panel/MarginContainer
@onready var vbox: VBoxContainer = $Root/Center/Panel/MarginContainer/VBox
@onready var stats_scroll: ScrollContainer = $Root/Center/Panel/MarginContainer/VBox/StatsScroll
@onready var stats_label: Label = $Root/Center/Panel/MarginContainer/VBox/StatsScroll/StatsLabel
@onready var new_game_btn: Button = $Root/Center/Panel/MarginContainer/VBox/Buttons/NewGameButton
@onready var exit_btn: Button = $Root/Center/Panel/MarginContainer/VBox/Buttons/ExitButton


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	visible = false
	get_viewport().size_changed.connect(_on_viewport_resized)
	_style_ui()

	if new_game_btn:
		new_game_btn.pressed.connect(_on_new_game_pressed)
	if exit_btn:
		exit_btn.pressed.connect(_on_exit_pressed)


func _style_ui() -> void:
	if panel:
		GameUiTheme.apply_horror_panel(panel)
	var title: Label = vbox.get_node_or_null("Title") as Label
	if title:
		title.label_settings = GameUiTheme.make_horror_title_settings(34)
	if stats_label:
		stats_label.add_theme_font_size_override("font_size", 15)
		stats_label.add_theme_color_override("font_color", Color(0.88, 0.95, 0.9, 1.0))
		stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for btn in [new_game_btn, exit_btn]:
		if btn:
			btn.custom_minimum_size = Vector2(0, BTN_MIN_H)
			btn.mouse_filter = Control.MOUSE_FILTER_STOP


func show_win() -> void:
	RunStats.refresh_from_db()
	if stats_label:
		stats_label.text = RunStats.build_report_text(true)
	RunStats.try_save_best_score(true)

	visible = true
	call_deferred("_fit_panel")

	var hud := get_parent()
	if hud and hud.has_method("hide_hint"):
		hud.hide_hint()

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true

	if new_game_btn:
		new_game_btn.grab_focus()


func _on_viewport_resized() -> void:
	if visible and stats_label and stats_label.text != "":
		call_deferred("_fit_panel")


func _fit_panel() -> void:
	if panel == null or vbox == null or stats_label == null or margin == null:
		return

	var vp := get_viewport().get_visible_rect().size
	var pad_x := float(
		margin.get_theme_constant("margin_left") + margin.get_theme_constant("margin_right")
	)
	var pad_y := float(
		margin.get_theme_constant("margin_top") + margin.get_theme_constant("margin_bottom")
	)

	var inner_w := clampf(vp.x * PANEL_WIDTH_RATIO - pad_x, PANEL_MIN_W - pad_x, PANEL_MAX_W - pad_x)
	stats_label.custom_minimum_size = Vector2(maxf(200.0, inner_w), 0)

	var content_min := vbox.get_combined_minimum_size()
	var scroll_h := clampf(content_min.y * 0.55, STATS_SCROLL_MIN_H, STATS_SCROLL_MAX_H)
	if stats_scroll:
		stats_scroll.custom_minimum_size = Vector2(0, scroll_h)

	content_min = vbox.get_combined_minimum_size()
	var panel_h := clampf(content_min.y + pad_y, PANEL_MIN_H, vp.y * PANEL_MAX_H_RATIO)
	var panel_w := clampf(content_min.x + pad_x, PANEL_MIN_W, minf(PANEL_MAX_W, vp.x * 0.95))
	panel.custom_minimum_size = Vector2(panel_w, panel_h)


func _on_new_game_pressed() -> void:
	get_tree().paused = false
	get_tree().call_deferred("change_scene_to_file", "res://scenes/new_game_loading/new_game_loading.tscn")


func _on_exit_pressed() -> void:
	get_tree().paused = false
	if typeof(TutorialManager) != TYPE_NIL and TutorialManager.has_method("prepare_exit_to_main_menu"):
		TutorialManager.prepare_exit_to_main_menu()
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)
