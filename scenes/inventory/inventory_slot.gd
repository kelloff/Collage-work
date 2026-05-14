extends Control

@onready var icon: TextureRect = $ItemIcon

var item_type: String = ""
var duration: float = 0.0
var value: float = 0.0

func _ready() -> void:
	if icon == null:
		push_error("%s: ItemIcon not found" % name)
		return
	clear()

func set_item(_type: String, _icon: Texture2D, _duration: float, _value: float = 0.0) -> void:
	item_type = _type
	duration = _duration
	value = _value
	icon.texture = _icon
	icon.visible = true

func clear() -> void:
	item_type = ""
	duration = 0.0
	value = 0.0
	icon.texture = null
	icon.visible = false

func is_empty() -> bool:
	return item_type == ""

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if is_empty():
			return
		var player := get_tree().get_first_node_in_group("player")
		if player == null:
			return

		match item_type:
			"speed":
				if player.has_method("apply_speed_buff"):
					player.apply_speed_buff(value, duration)
					clear()
			"invis":
				if player.has_method("apply_invisibility"):
					player.apply_invisibility(duration)
					clear()
