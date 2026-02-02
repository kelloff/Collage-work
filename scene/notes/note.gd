extends Area2D

@onready var rect: ColorRect = $ColorRect

@export var note_id: String = "note_01"
@export var text_path: String = "res://docs/notes/note_01.txt"

var player_in_range: bool = false
var outline_material: ShaderMaterial

func _ready() -> void:
	# если уже собрана — удалить
	if JournalData.has_note(note_id):
		queue_free()
		return

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	# белый контур
	outline_material = ShaderMaterial.new()
	if ResourceLoader.exists("res://shaders/outline.gdshader"):
		outline_material.shader = load("res://shaders/outline.gdshader")
		rect.material = outline_material

	set_outline(false)
	set_highlight(false)

func _process(_delta: float) -> void:
	if player_in_range and Input.is_action_just_pressed("interact"):
		_pickup()

func _pickup() -> void:
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

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		player_in_range = false
		set_outline(false)
		set_highlight(false)

func set_outline(enabled: bool) -> void:
	if outline_material:
		outline_material.set_shader_parameter("enabled", enabled)

func set_highlight(enabled: bool) -> void:
	if outline_material:
		outline_material.set_shader_parameter("highlight", enabled)
