extends CanvasLayer

@onready var arrow: Label = $Arrow
@onready var hint_panel: Panel = $HintPanel
@onready var hint_margin: MarginContainer = $HintPanel/MarginContainer
@onready var hint_label: Label = $HintPanel/MarginContainer/HintLabel
@onready var popup: Panel = $Popup
@onready var popup_title: Label = $Popup/VBox/Title
@onready var popup_text: RichTextLabel = $Popup/VBox/Text
@onready var popup_btn: Button = $Popup/VBox/BtnOk

const HINT_EDGE := Vector2(12, 12)
const HINT_WIDTH_MIN := 260.0
const HINT_WIDTH_MAX := 520.0
const HINT_WIDTH_RATIO := 0.38
const POPUP_WIDTH_MIN := 300.0
const POPUP_WIDTH_MAX := 580.0
const POPUP_WIDTH_RATIO := 0.52
const POPUP_HEIGHT_MIN := 200.0
const POPUP_HEIGHT_MAX := 460.0
const POPUP_HEIGHT_RATIO := 0.52

var _target: Node2D = null
var _on_close: Callable = Callable()
var _base_objective: String = ""
var _flash_objective: String = ""
var _banner_step_num: int = 1
var _banner_step_total: int = 1

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process_unhandled_input(true)
	visible = false
	hint_panel.visible = false
	popup.visible = false
	arrow.visible = false
	popup_btn.pressed.connect(_on_popup_ok)
	_style_ui()
	get_viewport().size_changed.connect(_on_viewport_size_changed)

func _style_ui() -> void:
	GameUiTheme.apply_horror_panel(hint_panel)
	GameUiTheme.apply_horror_panel(popup)

	hint_label.add_theme_color_override("font_color", GameUiTheme.C_TEXT)
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	arrow.add_theme_color_override("font_color", GameUiTheme.C_HORROR_OUTLINE)
	if popup_title:
		popup_title.label_settings = GameUiTheme.make_horror_title_settings(22)
		popup_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if popup_text:
		popup_text.add_theme_color_override("default_color", GameUiTheme.C_TEXT)

func _on_viewport_size_changed() -> void:
	if hint_panel.visible:
		call_deferred("_fit_hint_panel")
	if popup.visible:
		call_deferred("_fit_popup")

func show_tutorial_ui() -> void:
	visible = true
	hint_panel.visible = true
	call_deferred("_fit_hint_panel")

func hide_tutorial_ui() -> void:
	hint_panel.visible = false
	hide_arrow()
	if not popup.visible:
		visible = false


func force_hide_all() -> void:
	hide_arrow()
	if popup:
		popup.visible = false
	if hint_panel:
		hint_panel.visible = false
	visible = false

func set_step_banner(step_num: int, total: int, objective: String) -> void:
	_banner_step_num = step_num
	_banner_step_total = total
	_base_objective = objective
	_flash_objective = ""
	_apply_banner_text(step_num, total)

func flash_objective(msg: String) -> void:
	_flash_objective = msg
	_apply_banner_text(_banner_step_num, _banner_step_total)

func _apply_banner_text(step_num: int, total: int) -> void:
	if _flash_objective != "":
		hint_label.text = "⚠ %s" % _flash_objective
		hint_label.add_theme_color_override("font_color", GameUiTheme.C_DANGER)
	else:
		hint_label.text = "Обучение — шаг %d / %d\n%s" % [step_num, total, _base_objective]
		hint_label.add_theme_color_override("font_color", Color(0.9, 0.88, 0.86, 1.0))
	call_deferred("_fit_hint_panel")

func _fit_hint_panel() -> void:
	if hint_panel == null or hint_label == null:
		return

	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var panel_w: float = clampf(vp_size.x * HINT_WIDTH_RATIO, HINT_WIDTH_MIN, HINT_WIDTH_MAX)
	var m_left: float = float(hint_margin.get_theme_constant("margin_left"))
	var m_right: float = float(hint_margin.get_theme_constant("margin_right"))
	var m_top: float = float(hint_margin.get_theme_constant("margin_top"))
	var m_bottom: float = float(hint_margin.get_theme_constant("margin_bottom"))
	var inner_w: float = maxf(80.0, panel_w - m_left - m_right)

	hint_label.custom_minimum_size = Vector2(inner_w, 0)
	hint_label.size = Vector2(inner_w, 0)

	var label_h: float = hint_label.get_minimum_size().y
	var panel_h: float = label_h + m_top + m_bottom + 4.0

	hint_panel.offset_left = -panel_w - HINT_EDGE.x
	hint_panel.offset_top = HINT_EDGE.y
	hint_panel.offset_right = -HINT_EDGE.x
	hint_panel.offset_bottom = HINT_EDGE.y + panel_h

func _fit_popup() -> void:
	if popup == null:
		return

	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var w: float = clampf(vp_size.x * POPUP_WIDTH_RATIO, POPUP_WIDTH_MIN, POPUP_WIDTH_MAX)
	var h: float = clampf(vp_size.y * POPUP_HEIGHT_RATIO, POPUP_HEIGHT_MIN, POPUP_HEIGHT_MAX)
	popup.offset_left = -w * 0.5
	popup.offset_top = -h * 0.5
	popup.offset_right = w * 0.5
	popup.offset_bottom = h * 0.5

func point_at(target: Node2D) -> void:
	_target = target
	arrow.visible = target != null and is_instance_valid(target)
	if arrow.visible:
		_update_arrow_position()

func hide_arrow() -> void:
	_target = null
	arrow.visible = false

func show_popup(title: String, text: String, on_close: Callable) -> void:
	hide_arrow()
	_on_close = on_close
	popup_title.text = title
	popup_text.text = text
	popup_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	popup_text.scroll_active = true
	popup_text.fit_content = false
	popup.visible = true
	call_deferred("_fit_popup")
	if GameState.has_method("push_world_input_block"):
		GameState.push_world_input_block()
	if GameState.has_method("push_gameplay_freeze"):
		GameState.push_gameplay_freeze()

func _on_popup_ok() -> void:
	popup.visible = false
	if GameState.has_method("pop_gameplay_freeze"):
		GameState.pop_gameplay_freeze()
	if GameState.has_method("pop_world_input_block"):
		GameState.pop_world_input_block()
	if _on_close.is_valid():
		_on_close.call()
	_on_close = Callable()

func _unhandled_input(event: InputEvent) -> void:
	if not popup.visible:
		return
	if event.is_action_pressed("pause_menu"):
		var level := get_tree().current_scene
		if level:
			var pause_menu: Node = level.get_node_or_null("PauseMenu")
			if pause_menu and pause_menu.has_method("toggle_menu"):
				pause_menu.toggle_menu()
				get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	if not arrow.visible:
		return
	if _target == null or not is_instance_valid(_target):
		hide_arrow()
		return
	_update_arrow_position()

func _update_arrow_position() -> void:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var screen_pos: Vector2 = get_viewport().get_canvas_transform() * _target.global_position
	arrow.position = screen_pos + Vector2(-arrow.size.x * 0.5, -40.0)
