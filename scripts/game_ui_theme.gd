extends Node
## Глобальная UI-тема: яркие кнопки, единый шрифт, стиль для подростковой аудитории.

const FONT_DISPLAY := "res://ui/fonts/game_display.ttf"
const FONT_BODY := "res://ui/fonts/game_display.ttf"

const C_TEXT := Color(1.0, 0.97, 0.94, 1.0)
const C_TEXT_DIM := Color(0.82, 0.78, 0.86, 1.0)
const C_TITLE := Color(1.0, 0.88, 0.35, 1.0)
const C_ACCENT := Color(0.35, 1.0, 0.62, 1.0)
const C_DANGER := Color(1.0, 0.42, 0.48, 1.0)
## Как обводка интерактивных объектов (InteractHighlight).
const C_HORROR_OUTLINE := Color(0.9, 0.32, 0.26, 0.96)
const C_HORROR_GLOW := Color(0.48, 0.06, 0.09, 0.4)

var theme: Theme

func _ready() -> void:
	theme = _build_theme()
	get_tree().root.theme = theme

func _build_theme() -> Theme:
	var t := Theme.new()

	var font_display := _load_font(FONT_DISPLAY, 18)
	var font_body := _load_font(FONT_BODY, 16)

	t.default_font = font_body
	t.default_font_size = 18

	# --- Кнопки ---
	var btn_styles := _make_button_styles()
	var btn_normal: StyleBoxFlat = btn_styles[0]
	var btn_hover: StyleBoxFlat = btn_styles[1]
	var btn_pressed: StyleBoxFlat = btn_styles[2]
	var btn_disabled: StyleBoxFlat = btn_styles[3]
	var btn_focus: StyleBoxFlat = btn_styles[4]

	t.set_font("font", "Button", font_display)
	t.set_font_size("font_size", "Button", 22)
	t.set_color("font_color", "Button", C_TEXT)
	t.set_color("font_hover_color", "Button", Color(1.0, 1.0, 1.0))
	t.set_color("font_pressed_color", "Button", Color(0.95, 0.9, 0.9))
	t.set_color("font_disabled_color", "Button", C_TEXT_DIM)
	t.set_stylebox("normal", "Button", btn_normal)
	t.set_stylebox("hover", "Button", btn_hover)
	t.set_stylebox("pressed", "Button", btn_pressed)
	t.set_stylebox("disabled", "Button", btn_disabled)
	t.set_stylebox("focus", "Button", btn_focus)
	t.set_constant("outline_size", "Button", 0)
	t.set_constant("h_separation", "Button", 0)

	# --- Лейблы ---
	t.set_font("font", "Label", font_body)
	t.set_font_size("font_size", "Label", 18)
	t.set_color("font_color", "Label", C_TEXT)

	# --- Чекбокс (пустые стили — без скачков layout) ---
	var cb_empty := StyleBoxEmpty.new()
	t.set_font("font", "CheckBox", font_body)
	t.set_font_size("font_size", "CheckBox", 17)
	t.set_color("font_color", "CheckBox", C_TEXT)
	t.set_color("font_hover_color", "CheckBox", C_TEXT)
	t.set_color("font_pressed_color", "CheckBox", C_TEXT)
	t.set_color("font_disabled_color", "CheckBox", C_TEXT_DIM)
	t.set_icon("checked", "CheckBox", _checkbox_icon(true))
	t.set_icon("unchecked", "CheckBox", _checkbox_icon(false))
	t.set_constant("h_separation", "CheckBox", 12)
	t.set_constant("outline_size", "CheckBox", 0)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		t.set_stylebox(state, "CheckBox", cb_empty)

	# --- Панели ---
	t.set_stylebox("panel", "Panel", _style_panel())

	# --- OptionButton ---
	t.set_font("font", "OptionButton", font_body)
	t.set_font_size("font_size", "OptionButton", 18)
	t.set_stylebox("normal", "OptionButton", btn_normal.duplicate())
	t.set_stylebox("hover", "OptionButton", btn_hover.duplicate())
	t.set_stylebox("pressed", "OptionButton", btn_pressed.duplicate())
	t.set_stylebox("focus", "OptionButton", btn_focus.duplicate())
	t.set_color("font_color", "OptionButton", C_TEXT)

	# --- RichTextLabel ---
	t.set_font("normal_font", "RichTextLabel", font_body)
	t.set_font_size("normal_font_size", "RichTextLabel", 17)
	t.set_color("default_color", "RichTextLabel", C_TEXT)

	# --- HSlider ---
	t.set_stylebox("slider", "HSlider", _style_slider_track())
	t.set_stylebox("grabber_area", "HSlider", StyleBoxEmpty.new())
	t.set_stylebox("grabber_area_highlight", "HSlider", StyleBoxEmpty.new())

	return t

func make_title_settings(size: int = 42) -> LabelSettings:
	var ls := LabelSettings.new()
	ls.font = _load_font(FONT_DISPLAY, size)
	ls.font_size = size
	ls.font_color = C_TITLE
	ls.outline_size = 4
	ls.outline_color = Color(0.35, 0.05, 0.12, 0.9)
	ls.shadow_size = 6
	ls.shadow_color = Color(0.0, 0.0, 0.0, 0.55)
	ls.shadow_offset = Vector2(2, 3)
	return ls

func make_horror_panel_style(
	border_width: int = 3,
	corner_radius: int = 10,
	bg_alpha: float = 0.92,
	margin: float = 14.0
) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.05, 0.02, 0.04, bg_alpha)
	s.border_color = C_HORROR_OUTLINE
	s.set_border_width_all(border_width)
	s.set_corner_radius_all(corner_radius)
	s.content_margin_left = margin
	s.content_margin_top = margin
	s.content_margin_right = margin
	s.content_margin_bottom = margin
	s.shadow_color = C_HORROR_GLOW
	s.shadow_size = 8
	s.shadow_offset = Vector2(0, 3)
	s.anti_aliasing = true
	return s


func apply_horror_panel(node: Control) -> void:
	if node == null:
		return
	var style := make_horror_panel_style()
	if node is Panel:
		(node as Panel).add_theme_stylebox_override("panel", style)
	elif node is PanelContainer:
		(node as PanelContainer).add_theme_stylebox_override("panel", style)


func make_horror_title_settings(size: int = 24) -> LabelSettings:
	return make_subtitle_settings(size, C_HORROR_OUTLINE)


func make_dialog_body_settings(size: int = 17, color: Color = C_TEXT) -> LabelSettings:
	var ls := LabelSettings.new()
	ls.font = _load_font(FONT_BODY, size)
	ls.font_size = size
	ls.font_color = color
	ls.outline_size = 2
	ls.outline_color = Color(0.08, 0.04, 0.06, 0.85)
	return ls


func make_subtitle_settings(size: int = 28, color: Color = C_ACCENT) -> LabelSettings:
	var ls := LabelSettings.new()
	ls.font = _load_font(FONT_DISPLAY, size)
	ls.font_size = size
	ls.font_color = color
	ls.outline_size = 3
	ls.outline_color = Color(0.1, 0.1, 0.15, 0.85)
	return ls

func _load_font(path: String, base_size: int) -> Font:
	if ResourceLoader.exists(path):
		var ff: FontFile = load(path)
		ff.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		ff.hinting = TextServer.HINTING_LIGHT
		return ff
	var sf := SystemFont.new()
	sf.font_weight = 700
	sf.font_names = PackedStringArray(["Segoe UI", "Arial", "Noto Sans"])
	return sf

func _make_button_styles() -> Array[StyleBoxFlat]:
	var base := StyleBoxFlat.new()
	base.bg_color = Color(0.52, 0.14, 0.28, 0.95)
	base.border_color = Color(1.0, 0.45, 0.55, 1.0)
	base.set_border_width_all(3)
	base.set_corner_radius_all(14)
	base.content_margin_left = 20.0
	base.content_margin_top = 12.0
	base.content_margin_right = 20.0
	base.content_margin_bottom = 12.0
	base.shadow_size = 0
	base.shadow_offset = Vector2.ZERO
	base.expand_margin_left = 0.0
	base.expand_margin_top = 0.0
	base.expand_margin_right = 0.0
	base.expand_margin_bottom = 0.0
	base.anti_aliasing = true
	base.anti_aliasing_size = 1.0

	var hover := base.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.68, 0.2, 0.38, 1.0)
	hover.border_color = Color(1.0, 0.72, 0.42, 1.0)

	var pressed := base.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.38, 0.08, 0.18, 1.0)
	pressed.border_color = Color(1.0, 0.35, 0.45, 1.0)

	var disabled := base.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.22, 0.18, 0.24, 0.55)
	disabled.border_color = Color(0.45, 0.4, 0.48, 0.6)

	var focus := base.duplicate() as StyleBoxFlat
	focus.bg_color = Color(0.58, 0.16, 0.32, 1.0)
	focus.border_color = Color(1.0, 0.55, 0.62, 1.0)

	return [base, hover, pressed, disabled, focus]

func _style_btn(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.border_width_left = 3
	s.border_width_top = 3
	s.border_width_right = 3
	s.border_width_bottom = 3
	s.corner_radius_top_left = 14
	s.corner_radius_top_right = 14
	s.corner_radius_bottom_right = 14
	s.corner_radius_bottom_left = 14
	s.content_margin_left = 20.0
	s.content_margin_top = 12.0
	s.content_margin_right = 20.0
	s.content_margin_bottom = 12.0
	s.shadow_size = 0
	s.shadow_offset = Vector2.ZERO
	return s

func _style_panel() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.07, 0.05, 0.12, 0.88)
	s.border_color = Color(1.0, 0.4, 0.5, 0.85)
	s.border_width_left = 3
	s.border_width_top = 3
	s.border_width_right = 3
	s.border_width_bottom = 3
	s.corner_radius_top_left = 18
	s.corner_radius_top_right = 18
	s.corner_radius_bottom_right = 18
	s.corner_radius_bottom_left = 18
	s.content_margin_left = 20.0
	s.content_margin_top = 16.0
	s.content_margin_right = 20.0
	s.content_margin_bottom = 16.0
	s.shadow_color = Color(0.0, 0.0, 0.0, 0.5)
	s.shadow_size = 8
	s.shadow_offset = Vector2(0, 4)
	return s

func _style_slider_track() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.25, 0.12, 0.2, 1.0)
	s.border_color = Color(1.0, 0.45, 0.55, 0.7)
	s.border_width_left = 2
	s.border_width_top = 2
	s.border_width_right = 2
	s.border_width_bottom = 2
	s.corner_radius_top_left = 6
	s.corner_radius_top_right = 6
	s.corner_radius_bottom_right = 6
	s.corner_radius_bottom_left = 6
	return s

func _checkbox_icon(checked: bool) -> ImageTexture:
	var img := Image.create(24, 24, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.12, 0.08, 0.16, 1.0))
	for x in range(24):
		for y in range(24):
			if x == 0 or y == 0 or x == 23 or y == 23:
				img.set_pixel(x, y, Color(1.0, 0.5, 0.58, 1.0))
	if checked:
		for x in range(7, 18):
			img.set_pixel(x, 12, Color(0.35, 1.0, 0.62, 1.0))
			img.set_pixel(x, 13, Color(0.35, 1.0, 0.62, 1.0))
		for y in range(9, 16):
			img.set_pixel(12, y, Color(0.35, 1.0, 0.62, 1.0))
	var tex := ImageTexture.create_from_image(img)
	return tex
