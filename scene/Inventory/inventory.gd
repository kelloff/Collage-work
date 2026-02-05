extends CanvasLayer

@onready var root: Control = $InventoryRoot
@onready var slots_container: Node = $InventoryRoot/Slots
@onready var avatar: AnimatedSprite2D = $InventoryRoot/Avatar

var is_open := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	root.visible = false

	# аватар (анимированный)
	if avatar and avatar.sprite_frames:
		if avatar.sprite_frames.has_animation("idle"):
			avatar.play("idle")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory"):
		toggle()

func toggle() -> void:
	is_open = !is_open
	root.visible = is_open


func add_item(item_type: String, icon: Texture2D, duration: float, value: float = 0.0) -> bool:
	for slot in slots_container.get_children():
		if slot.has_method("is_empty") and slot.is_empty():
			slot.set_item(item_type, icon, duration, value)
			return true
	return false
