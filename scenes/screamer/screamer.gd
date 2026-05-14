extends CanvasLayer

signal finished

@export var duration: float = 1.35

const CREAMER_SFX_PATH := "res://audio/sounds/creamer.mp3"

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var timer: Timer = $Timer
@onready var bg: ColorRect = $BG
@onready var sfx_player: AudioStreamPlayer = get_node_or_null("ScreamerSfx")

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

	_play_creamer_sfx()

func _play_creamer_sfx() -> void:
	if sfx_player == null:
		sfx_player = AudioStreamPlayer.new()
		sfx_player.name = "ScreamerSfx"
		add_child(sfx_player)
	if not ResourceLoader.exists(CREAMER_SFX_PATH):
		push_warning("screamer: missing audio %s" % CREAMER_SFX_PATH)
		return
	var stream: AudioStream = load(CREAMER_SFX_PATH)
	if stream == null:
		return
	sfx_player.stream = stream
	sfx_player.bus = "Master"
	sfx_player.play()

func _on_timeout() -> void:
	if sfx_player and sfx_player.playing:
		sfx_player.stop()
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
