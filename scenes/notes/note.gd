extends Area2D

const ICON_SIZE_PX := 16.0

@export var note_id: String = "note_01"
@export var text_path: String = "res://docs/notes/note_01.txt"
@export var tutorial_step: String = ""

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

var player_in_range: bool = false
var _outline_vis := InteractionOutline.new()

func _ready() -> void:
	if tutorial_step != "":
		add_to_group("tutorial_target")

	# если уже собрана — удалить
	if JournalData.has_note(note_id):
		queue_free()
		return

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	_setup_outline()
	_outline_vis.set_both(false)

func _setup_outline() -> void:
	if sprite == null:
		push_warning("Note: AnimatedSprite2D not found")
		return
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var tex: Texture2D = sprite.sprite_frames.get_frame_texture(sprite.animation, 0) if sprite.sprite_frames else null
	if tex:
		var sz := tex.get_size()
		if sz.x > 0.0 and sz.y > 0.0:
			sprite.scale = Vector2(ICON_SIZE_PX / sz.x, ICON_SIZE_PX / sz.y)
	_outline_vis.setup(sprite, 0.01)

func _process(_delta: float) -> void:
	if GameState.has_method("is_world_input_blocked") and GameState.is_world_input_blocked():
		return
	if player_in_range and Input.is_action_just_pressed("interact"):
		if TutorialManager.is_active():
			if TutorialManager.try_lesson_then("note", Callable(self, "_pickup")):
				return
		_pickup()

func _pickup() -> void:
	_hide_hint()
	var text := _load_text(text_path)
	JournalData.add_note(note_id, text)
	if tutorial_step != "":
		TutorialManager.notify_note_collected(note_id)
	queue_free()

func _load_text(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return "Файл не найден:\n" + path
	return f.get_as_text()

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		player_in_range = true
		_outline_vis.set_both(true)
		_show_hint("E — подобрать записку")

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		player_in_range = false
		_outline_vis.set_both(false)
		_hide_hint()

func _hud() -> Node:
	return get_tree().current_scene.get_node_or_null("HUD")

func _show_hint(text: String) -> void:
	var hud := _hud()
	if hud and hud.has_method("show_hint"):
		hud.show_hint(text, 0.0, self)

func _hide_hint() -> void:
	var hud := _hud()
	if hud and hud.has_method("hide_hint"):
		hud.hide_hint(self)

func set_outline(enabled: bool) -> void:
	_outline_vis.set_outline(enabled)

func set_highlight(enabled: bool) -> void:
	_outline_vis.set_highlight(enabled)

func refresh_interaction_highlight() -> void:
	_outline_vis.refresh_from_player_in_range(player_in_range)
