extends CanvasLayer

@onready var arrow: Label = $Arrow
@onready var hint_panel: Panel = $HintPanel
@onready var hint_label: Label = $HintPanel/HintLabel
@onready var popup: Panel = $Popup
@onready var popup_title: Label = $Popup/VBox/Title
@onready var popup_text: RichTextLabel = $Popup/VBox/Text
@onready var popup_btn: Button = $Popup/VBox/BtnOk

var _target: Node2D = null
var _on_close: Callable = Callable()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	hint_panel.visible = false
	popup.visible = false
	arrow.visible = false
	popup_btn.pressed.connect(_on_popup_ok)
	_style_ui()

func _style_ui() -> void:
	hint_label.add_theme_color_override("font_color", GameUiTheme.C_TITLE)
	if popup_title:
		popup_title.label_settings = GameUiTheme.make_subtitle_settings(22, GameUiTheme.C_ACCENT)

func show_tutorial_ui() -> void:
	visible = true
	hint_panel.visible = true
	hint_label.text = "Обучение — следуйте стрелке ▼"

func hide_tutorial_ui() -> void:
	hint_panel.visible = false
	hide_arrow()
	if not popup.visible:
		visible = false

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
	get_tree().paused = true
	if GameState.has_method("push_world_input_block"):
		GameState.push_world_input_block()

func _on_popup_ok() -> void:
	popup.visible = false
	get_tree().paused = false
	if GameState.has_method("pop_world_input_block"):
		GameState.pop_world_input_block()
	if _on_close.is_valid():
		_on_close.call()
	_on_close = Callable()

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
