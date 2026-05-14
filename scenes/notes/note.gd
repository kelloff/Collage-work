extends Area2D

@export var note_id: String = "note_01"
@export var text_path: String = "res://docs/notes/note_01.txt"
@export var tutorial_step: String = ""

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

var player_in_range: bool = false
var outline_material: ShaderMaterial

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
	set_outline(false)
	set_highlight(false)

func _setup_outline() -> void:
	if sprite == null:
		push_warning("Note: AnimatedSprite2D not found")
		return

	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	if sprite.material is ShaderMaterial:
		outline_material = sprite.material as ShaderMaterial
	else:
		outline_material = ShaderMaterial.new()
		if ResourceLoader.exists("res://shaders/Outline.gdshader"):
			outline_material.shader = load("res://shaders/Outline.gdshader")
		sprite.material = outline_material

	outline_material.set_shader_parameter("alpha_cutoff", 0.01)

func _process(_delta: float) -> void:
	if GameState.has_method("is_world_input_blocked") and GameState.is_world_input_blocked():
		return
	if player_in_range and Input.is_action_just_pressed("interact"):
		if tutorial_step != "" and TutorialManager.try_interact_step(tutorial_step, Callable(self, "_pickup")):
			return
		_pickup()

func _pickup() -> void:
	_hide_hint()
	var text := _load_text(text_path)
	JournalData.add_note(note_id, text)
	queue_free()

func _load_text(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return "Файл не найден:\n" + path
	return f.get_as_text()

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		player_in_range = true
		set_outline(true)
		set_highlight(true)
		_show_hint("E — подобрать записку")

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		player_in_range = false
		set_outline(false)
		set_highlight(false)
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
	if outline_material:
		outline_material.set_shader_parameter("enabled", enabled)

func set_highlight(enabled: bool) -> void:
	if outline_material:
		outline_material.set_shader_parameter("highlight", enabled)
