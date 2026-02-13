extends CanvasLayer

signal finished

@export var duration: float = 1.35

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var timer: Timer = $Timer
@onready var bg: ColorRect = $BG

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_resize_to_screen()
	get_viewport().size_changed.connect(_resize_to_screen)

	timer.one_shot = true
	timer.wait_time = duration
	timer.timeout.connect(_on_timeout)
	timer.start()

	if sprite and sprite.sprite_frames:
		sprite.play() # проиграет текущую анимацию

func _on_timeout() -> void:
	finished.emit()

func _resize_to_screen() -> void:
	var size: Vector2 = get_viewport().get_visible_rect().size

	if bg:
		bg.size = size

	if not sprite or sprite.sprite_frames == null:
		return

	sprite.position = size * 0.5

	# берём текущий кадр, чтобы вычислить масштаб "cover"
	var frames: SpriteFrames = sprite.sprite_frames
	var anim: StringName = sprite.animation
	var frame_idx: int = sprite.frame
	var tex: Texture2D = frames.get_frame_texture(anim, frame_idx)
	if tex == null:
		return

	var tex_size: Vector2 = tex.get_size()
	if tex_size.x <= 0.0 or tex_size.y <= 0.0:
		return

	# покрыть экран полностью
	var scale_factor: float = max(size.x / tex_size.x, size.y / tex_size.y)
	sprite.scale = Vector2.ONE * scale_factor
