#inventory
extends CanvasLayer

@onready var root: Control = $InventoryRoot
@onready var slots_container = $InventoryRoot/Slots 

var is_open: bool = false

func _ready() -> void:
	root.visible = false
	root.scale = Vector2(1.2, 1.2)
	root.pivot_offset = root.size / 2

func toggle() -> void:
	is_open = !is_open
	root.visible = is_open

# Добавление предмета
func add_item(type: String, icon: Texture2D, duration: float, value: float = 0.0) -> bool:
	for slot in slots_container.get_children():
		if slot.is_empty():
			slot.set_item(type, icon, duration, value)
			return true
	return false

	
func _process(_delta: float) -> void:
	if is_open:
		if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	if get_tree().paused and is_open:
		root.visible = false 
