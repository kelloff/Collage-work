extends StaticBody2D
class_name Door

signal opened_by_system
signal closed_by_system

@onready var sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")
@onready var door_collision: CollisionShape2D = get_node_or_null("CollisionShape2D")
@onready var area: Area2D = get_node_or_null("Area2D")

@export var door_id: int = 0

var is_open: bool = false
var player_in_range: bool = false
var outline_material: ShaderMaterial

func _enter_tree() -> void:
	if not is_in_group("doors"):
		add_to_group("doors")

func _ready() -> void:
	# защита от кривой сцены
	if sprite == null:
		push_error("Door '%s': node 'AnimatedSprite2D' NOT FOUND. Проверь имя узла!" % name)
	if door_collision == null:
		push_error("Door '%s': node 'CollisionShape2D' NOT FOUND." % name)
	if area == null:
		push_error("Door '%s': node 'Area2D' NOT FOUND." % name)

	if area:
		area.body_entered.connect(_on_body_entered)
		area.body_exited.connect(_on_body_exited)

	# восстановление состояния двери из БД (если есть метод)
	_restore_from_db()

	# outline (если есть спрайт)
	if sprite:
		outline_material = ShaderMaterial.new()
		if ResourceLoader.exists("res://shaders/outline.gdshader"):
			outline_material.shader = load("res://shaders/outline.gdshader")
			sprite.material = outline_material
		set_outline(false)
		set_highlight(false)

	if door_id == 0:
		push_warning("Door '%s' has door_id = 0 — установи в инспекторе" % name)

func _process(_delta: float) -> void:
	if player_in_range and Input.is_action_just_pressed("interact"):
		try_toggle_by_player()

# ---------- SAVE/LOAD ----------
func _restore_from_db() -> void:
	# если у DbMeneger есть get_door_state — применяем
	if door_id > 0 and DbMeneger.has_method("get_door_state"):
		var st = DbMeneger.get_door_state(door_id) # ожидаем true/false или 1/0
		if st != null:
			is_open = bool(st)
			_apply_visuals()

	# если метода нет — просто применим дефолт (закрыто)
	else:
		is_open = false
		_apply_visuals()

func _write_state_to_db() -> void:
	if door_id > 0 and DbMeneger.has_method("set_door_state"):
		DbMeneger.set_door_state(door_id, is_open)
# ------------------------------

func _apply_visuals() -> void:
	# НИКОГДА не трогаем sprite если его нет
	if sprite:
		sprite.animation = "open" if is_open else "closed"
		sprite.frame = 0
		sprite.stop()
	if door_collision:
		door_collision.disabled = is_open

# ---------------- HUD helpers ----------------
func _hud() -> Node:
	return get_tree().current_scene.get_node_or_null("HUD")

func _show_hint(text: String, duration: float = 0.0) -> void:
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
	if DbMeneger.is_door_accessible(door_id):
		_show_hint("E — открыть/закрыть дверь")
	else:
		_show_hint("❌ Дверь заблокирована")
# --------------------------------------------

func try_toggle_by_player() -> void:
	if not DbMeneger.is_door_accessible(door_id):
		_show_hint("❌ Дверь заблокирована", 1.5)
		return
	toggle(false)

func toggle(by_system: bool = false) -> void:
	if not DbMeneger.is_door_accessible(door_id):
		_show_hint("❌ Дверь заблокирована", 1.5)
		return

	is_open = not is_open
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
	_apply_visuals()
	_write_state_to_db()
	if by_system:
		emit_signal("opened_by_system")
	_update_hint_for_state()

func close(by_system: bool = false) -> void:
	if not is_open:
		return
	is_open = false
	_apply_visuals()
	_write_state_to_db()
	if by_system:
		emit_signal("closed_by_system")
	_update_hint_for_state()

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

func set_outline(enabled: bool) -> void:
	if outline_material:
		outline_material.set_shader_parameter("enabled", enabled)

func set_highlight(enabled: bool) -> void:
	if outline_material:
		outline_material.set_shader_parameter("highlight", enabled)
