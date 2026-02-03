extends Control

@onready var icon: TextureRect = $ItemIcon

var item_type: String = ""
var duration: float = 0.0
var value: float = 0.0

func set_item(_type: String, _icon: Texture2D, _duration: float, _value: float = 0.0):
	item_type = _type
	duration = _duration
	value = _value
	icon.texture = _icon
	icon.visible = true

func clear():
	item_type = ""
	duration = 0
	value = 0
	icon.texture = null
	icon.visible = false

func _gui_input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if item_type != "":
			var player = get_tree().get_first_node_in_group("player")

			match item_type:
				"speed":
					player.apply_speed_buff(value, duration)
				"invis":
					player.apply_invisibility(duration)

			clear()


func is_empty() -> bool:
	return item_type == ""
