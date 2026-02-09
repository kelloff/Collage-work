extends StaticBody2D
class_name Door

signal opened_by_system
signal closed_by_system

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var door_collision: CollisionShape2D = $CollisionShape2D
@onready var area: Area2D = $Area2D
@onready var audio_player: AudioStreamPlayer2D = $AudioStreamPlayer2D

@export var door_id: int = 0

# 🔊 звуки
@export var sfx_open: AudioStream
@export var sfx_close: AudioStream

var is_open: bool = false
var player_in_range: bool = false
var outline_material: ShaderMaterial


# ---------------- INIT ----------------
func _enter_tree() -> void:
	if not is_in_group("doors"):
		add_to_group("doors")


func _ready() -> void:
	# проверки
	if not sprite:
		push_error("Door: AnimatedSprite2D not found")
	if not door_collision:
		push_error("Door: CollisionShape2D not found")
	if not area:
		push_error("Door: Area2D not found")
	if not audio_player:
		push_error("Door: AudioStreamPlayer2D not found")

	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)

	_restore_from_db()

	# outline
	if sprite and ResourceLoader.exists("res://shaders/outline.gdshader"):
		outline_material = ShaderMaterial.new()
		outline_material.shader = load("res://shaders/outline.gdshader")
		sprite.material = outline_material
		set_outline(false)
		set_highlight(false)


func _process(_delta: float) -> void:
	if player_in_range and Input.is_action_just_pressed("interact"):
		try_toggle_by_player()


# ---------------- SAVE ----------------
func _restore_from_db() -> void:
	if door_id > 0 and DbManager.has_method("get_door_state"):
		var st = DbManager.get_door_state(door_id)
		if st != null:
			is_open = bool(st)
	_apply_visuals()


func _write_state_to_db() -> void:
	if door_id > 0 and DbManager.has_method("set_door_state"):
		DbManager.set_door_state(door_id, is_open)


# ---------------- VISUALS ----------------
func _apply_visuals() -> void:
	if sprite:
		sprite.animation = "open" if is_open else "closed"
		sprite.frame = 0
		sprite.stop()

	if door_collision:
		door_collision.disabled = is_open


# ---------------- SOUND ----------------
func _play_open_sound() -> void:
	if audio_player and sfx_open:
		audio_player.stream = sfx_open
		audio_player.play()


func _play_close_sound() -> void:
	if audio_player and sfx_close:
		audio_player.stream = sfx_close
		audio_player.play()


# ---------------- HUD ----------------
func _hud() -> Node:
	return get_tree().current_scene.get_node_or_null("HUD")


func _show_hint(text: String, duration := 0.0) -> void:
	var hud = _hud()
	if hud and hud.has_method("show_hint"):
		hud.show_hint(text, duration, self)


func _hide_hint() -> void:
	var hud = _hud()
	if hud and hud.has_method("hide_hint"):
		hud.hide_hint(self)


func _update_hint_for_state() -> void:
	if not player_in_range:
		return

	if DbManager.is_door_accessible(door_id):
		_show_hint("E — открыть/закрыть дверь")
	else:
		_show_hint("❌ Дверь заблокирована")


# ---------------- LOGIC ----------------
func try_toggle_by_player() -> void:
	if not DbManager.is_door_accessible(door_id):
		_show_hint("❌ Дверь заблокирована", 1.5)
		return

	toggle(false)


func toggle(by_system: bool = false) -> void:
	if not DbManager.is_door_accessible(door_id):
		return

	is_open = not is_open

	if is_open:
		_play_open_sound()
	else:
		_play_close_sound()

	_apply_visuals()
	_write_state_to_db()

	if by_system:
		if is_open:
			emit_signal("opened_by_system")
		else:
			emit_signal("closed_by_system")

	_update_hint_for_state()


func open(by_system: bool = false) -> void:
	if is_open:
		return

	is_open = true
	_play_open_sound()
	_apply_visuals()
	_write_state_to_db()

	if by_system:
		emit_signal("opened_by_system")

	_update_hint_for_state()


func close(by_system: bool = false) -> void:
	if not is_open:
		return

	is_open = false
	_play_close_sound()
	_apply_visuals()
	_write_state_to_db()

	if by_system:
		emit_signal("closed_by_system")

	_update_hint_for_state()


# ---------------- AREA ----------------
func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		player_in_range = true
		set_outline(true)
		set_highlight(true)
		_update_hint_for_state()


func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		player_in_range = false
		set_outline(false)
		set_highlight(false)
		_hide_hint()


# ---------------- OUTLINE ----------------
func set_outline(enabled: bool) -> void:
	if outline_material:
		outline_material.set_shader_parameter("enabled", enabled)


func set_highlight(enabled: bool) -> void:
	if outline_material:
		outline_material.set_shader_parameter("highlight", enabled)
