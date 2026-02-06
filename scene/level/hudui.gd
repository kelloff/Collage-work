# res://ui/hint_ui.gd
extends CanvasLayer

@onready var panel: Panel = $HintPanel
@onready var persistent_hint: Label = $HintPanel/PersistentHint
@onready var dynamic_hint: Label = $HintPanel/HintLabel
@onready var timer: Timer = $HintPanel/HintTimer

var _owner: Object = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	# чёрный квадрат всегда виден
	panel.visible = true

	# постоянная подсказка
	persistent_hint.text = "B — руководство"
	persistent_hint.visible = true

	# временная по умолчанию скрыта
	dynamic_hint.visible = false

	timer.one_shot = true
	timer.timeout.connect(hide_hint)


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
