extends Area2D

@export var win_ui_path: NodePath = "../HUD/WinUI"  # укажи путь до WinUI в инспекторе (например "../HUD/WinUI")
var _triggered := false

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if _triggered:
		return
	if not body.is_in_group("player"):
		return

	_triggered = true
	print("WIN TRIGGERED")

	var win_ui = get_node_or_null(win_ui_path)
	if win_ui and win_ui.has_method("show_win"):
		win_ui.show_win()
	else:
		push_warning("FinishTrigger: WinUI not found or no show_win()")
