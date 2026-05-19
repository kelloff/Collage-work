extends Control

signal confirmed
signal cancelled

@onready var _dim: ColorRect = $Dim
@onready var _panel: Panel = $MenuPanel
@onready var _title: Label = $MenuPanel/VBoxContainer/TitleLabel
@onready var _message: Label = $MenuPanel/VBoxContainer/MessageLabel
@onready var _warning: Label = $MenuPanel/VBoxContainer/WarningLabel
@onready var _confirm_btn: Button = $MenuPanel/VBoxContainer/ButtonRow/ConfirmButton
@onready var _cancel_btn: Button = $MenuPanel/VBoxContainer/ButtonRow/CancelButton

var _on_confirm: Callable = Callable()


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 100
	set_process_unhandled_input(true)
	_style_ui()
	_confirm_btn.pressed.connect(_on_confirm_pressed)
	_cancel_btn.pressed.connect(_on_cancel_pressed)
	_dim.gui_input.connect(_on_dim_gui_input)


func _style_ui() -> void:
	_dim.color = Color(0.04, 0.02, 0.08, 0.78)
	GameUiTheme.apply_horror_panel(_panel)
	_title.label_settings = GameUiTheme.make_horror_title_settings(26)
	_message.label_settings = GameUiTheme.make_dialog_body_settings(18)
	_warning.label_settings = GameUiTheme.make_dialog_body_settings(16, GameUiTheme.C_DANGER)
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for btn in [_confirm_btn, _cancel_btn]:
		btn.custom_minimum_size = Vector2(0, 50)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.focus_mode = Control.FOCUS_NONE


func open(
	title: String,
	message: String,
	confirm_label: String,
	cancel_label: String,
	warning: String = "",
	on_confirm: Callable = Callable()
) -> void:
	_title.text = title.to_upper()
	_message.text = message
	_warning.text = warning
	_warning.visible = warning.strip_edges() != ""
	_confirm_btn.text = confirm_label
	_cancel_btn.text = cancel_label
	_on_confirm = on_confirm
	visible = true
	move_to_front()
	_confirm_btn.grab_focus()


func close() -> void:
	visible = false
	_on_confirm = Callable()


func _on_confirm_pressed() -> void:
	var cb := _on_confirm
	close()
	confirmed.emit()
	if cb.is_valid():
		cb.call()


func _on_cancel_pressed() -> void:
	close()
	cancelled.emit()


func _on_dim_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_on_cancel_pressed()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		_on_cancel_pressed()
		get_viewport().set_input_as_handled()
