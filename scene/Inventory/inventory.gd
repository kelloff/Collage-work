extends CanvasLayer

@onready var root: Control = $InventoryRoot
@onready var slots_container: Node = $InventoryRoot/Slots
@onready var avatar: AnimatedSprite2D = $InventoryRoot/Avatar

var is_open := false

const BASE_RESOLUTION := Vector2(1080, 720)

func _ready() -> void:
	add_to_group("inventory")
	process_mode = Node.PROCESS_MODE_ALWAYS
	root.visible = false

	# аватар
	if avatar and avatar.sprite_frames:
		if avatar.sprite_frames.has_animation("idle"):
			avatar.play("idle")

	# 🔥 ВАЖНО: подписываемся на изменение viewport
	get_viewport().size_changed.connect(_apply_scale)

	# первый расчёт
	call_deferred("_apply_scale")

func _apply_scale() -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size

	var scale_factor: float = min(
		viewport_size.x / BASE_RESOLUTION.x,
		viewport_size.y / BASE_RESOLUTION.y
	)

	root.scale = Vector2(scale_factor, scale_factor)
	root.position = (viewport_size - root.size * scale_factor) * 0.5

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
