extends Node2D

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var area: Area2D = $InteractionArea

var is_on: bool = true
var player_in_range: bool = false
var outline_material: ShaderMaterial

@export var lever_id: int = 0
@export var linked_computers: Array[int] = []
@export var linked_doors: Array[int] = []  # список door_id через инспектор

# Если true — при опускании рычага двери открываются, при подъёме закрываются.
@export var open_doors_on_down: bool = true

func _enter_tree() -> void:
	if not is_in_group("levers"):
		add_to_group("levers")

func _ready() -> void:
	if area:
		area.body_entered.connect(_on_body_entered)
		area.body_exited.connect(_on_body_exited)

	# Инициализация визуального состояния
	is_on = true
	sprite.animation = "up"
	sprite.frame = 0
	sprite.stop()

	outline_material = ShaderMaterial.new()
	if ResourceLoader.exists("res://shaders/outline.gdshader"):
		outline_material.shader = load("res://shaders/outline.gdshader")
		sprite.material = outline_material

	set_outline(false)
	set_highlight(false)

	# Синхронизируем состояние из БД, если есть
	if lever_id > 0:
		if DbMeneger.has_method("get_lever_state"):
			var state = DbMeneger.get_lever_state(lever_id)
			if state != null:
				# state: 1 = is_down, 0 = up
				is_on = (state == 0)
				sprite.animation = "up" if is_on else "down"
				sprite.frame = 0
				sprite.stop()
	else:
		push_warning("Lever '%s' has lever_id = 0 — установи в инспекторе" % name)

	# Регистрируем связи в БД (если есть методы) и применяем состояние к дверям
	register_links()
	# Синхронизируем двери с текущим состоянием рычага
	_apply_linked_doors()

func register_links() -> void:
	if lever_id == 0:
		#push_warning("Lever '%s' has lever_id = 0 — не могу зарегистрировать связи" % name)
		return
	for comp_id in linked_computers:
		if typeof(comp_id) == TYPE_INT and comp_id > 0:
			if DbMeneger.has_method("link_lever_to_computer"):
				DbMeneger.link_lever_to_computer(lever_id, comp_id)
			else:
				push_warning("DbMeneger.link_lever_to_computer not found")
		else:
			push_warning("Lever '%s': некорректный ID компьютера: %s" % [name, str(comp_id)])

	for did in linked_doors:
		if typeof(did) == TYPE_INT and did > 0:
			if DbMeneger.has_method("link_lever_to_door"):
				DbMeneger.link_lever_to_door(lever_id, did)
			# иначе — связь остаётся локальной в linked_doors
		else:
			push_warning("Lever '%s': некорректный ID двери: %s" % [name, str(did)])

func _process(_delta: float) -> void:
	if player_in_range and Input.is_action_just_pressed("interact"):
		toggle()

func toggle() -> void:
	# Меняем визуальное состояние
	is_on = not is_on
	sprite.animation = "up" if is_on else "down"
	sprite.frame = 0
	sprite.stop()

	# Сохраняем состояние в БД: is_down = not is_on
	if lever_id > 0:
		if DbMeneger.has_method("set_lever_state"):
			DbMeneger.set_lever_state(lever_id, not is_on)
		print("Lever toggled: %s (lever_id=%d) → is_down=%d" % [name, lever_id, int(not is_on)])
	else:
		push_warning("Lever '%s': toggle без lever_id" % name)

	# Небольшая задержка, чтобы запись в БД успела примениться (опционально)
	await get_tree().create_timer(0.02).timeout

	# Прямое управление связанными дверями: открываем или закрываем в соответствии с состоянием рычага
	_apply_linked_doors()

func _apply_linked_doors() -> void:
	# Решение: если open_doors_on_down == true, то при is_on == false открываем двери, иначе закрываем.
	var should_open := (not is_on) if open_doors_on_down else is_on

	# Получаем все ноды в группе "doors" и применяем действие к тем, чей door_id совпадает
	var doors = get_tree().get_nodes_in_group("doors")
	for d in doors:
		# Защита: у двери должно быть поле door_id
		if not ("door_id" in d):
			continue
		var did := int(d.door_id)
		if did in linked_doors:
			# Прямое управление: открываем или закрываем независимо от других условий
			if should_open:
				if d.has_method("open"):
					d.open()
				elif d.has_method("toggle"):
					# fallback: если есть только toggle, убедимся, что дверь закрыта
					if not d.is_open and d.has_method("toggle"):
						d.toggle()
			else:
				if d.has_method("close"):
					d.close()
				elif d.has_method("toggle"):
					# fallback: если есть только toggle, убедимся, что дверь открыта
					if d.is_open and d.has_method("toggle"):
						d.toggle()

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
		
