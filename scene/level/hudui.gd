# res://ui/hint_ui.gd
extends CanvasLayer

@onready var panel: Panel = $HintPanel
@onready var label: Label = $HintPanel/HintLabel
@onready var timer: Timer = $HintPanel/HintTimer

var _owner: Object = null  # кто "владеет" подсказкой

func _ready() -> void:
	panel.visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	timer.one_shot = true
	timer.timeout.connect(hide_hint)

func show_hint(text: String, duration: float = 0.0, owner: Object = null) -> void:
	_owner = owner
	label.text = text
	panel.visible = true

	if duration > 0.0:
		timer.stop()
		timer.start(duration)

func hide_hint(owner: Object = null) -> void:
	# если указан owner — скрываем только если подсказка принадлежит ему
	if owner != null and _owner != owner:
		return
	panel.visible = false
	_owner = null
	timer.stop()
