class_name InteractionOutline
extends RefCounted

## Состояние обводки для одного объекта (шкаф, дверь, бафф…).
var material: ShaderMaterial = null
var _outline_on: bool = false
var _highlight_on: bool = false

func setup(sprite: CanvasItem, alpha_cutoff: float = InteractHighlight.ALPHA_CUTOFF) -> void:
	material = InteractHighlight.bind_canvas_item(sprite, alpha_cutoff)
	_apply()

func adopt_existing(mat: ShaderMaterial, alpha_cutoff: float = InteractHighlight.ALPHA_CUTOFF) -> void:
	material = mat
	InteractHighlight.apply(material, alpha_cutoff)
	_apply()

func set_outline(enabled: bool) -> void:
	_outline_on = enabled
	_apply()

func set_highlight(enabled: bool) -> void:
	_highlight_on = enabled
	_apply()

func set_both(enabled: bool) -> void:
	_outline_on = enabled
	_highlight_on = enabled
	_apply()

func refresh_from_player_in_range(in_range: bool) -> void:
	set_both(in_range)

func _apply() -> void:
	InteractHighlight.set_enabled(material, _outline_on, _highlight_on)
