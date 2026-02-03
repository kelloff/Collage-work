extends Node

# Autoload: DbMeneger.gd
# Monolithic core that initializes DB and delegates to modules.

var save = null
var db: SQLite = null
var tasks = null
var levers = null
var doors = null
var debug = null

func _ready() -> void:
	randomize()
	# Миграция (копирование шаблона в user:// если нужно)
	var migr = preload("res://db/db_migration.gd").new()
	migr.run_migration()
	# Открываем DB
	db = SQLite.new()
	db.path = "user://tasks.db"
	if not db.open_db():
		push_error("DbMeneger: cannot open DB at %s" % db.path)
		db = null
		return
	# Загружаем модули
	_load_modules()
	# Создаём таблицы (модули сами создают свои таблицы в init)
	if debug and debug.has_method("debug_dump_all"):
		# опционально: debug.debug_dump_all()
		pass
	print("DbMeneger: ready, DB path:", db.path)

func _load_modules() -> void:
	# Путь к модулям — поправьте при необходимости
	tasks = preload("res://db/db_tasks.gd").new()
	levers = preload("res://db/db_levers.gd").new()
	doors = preload("res://db/db_doors.gd").new()
	debug = preload("res://db/db_debug.gd").new()
	# Инициализируем модули, передаём ссылку на этот singleton
	if tasks and tasks.has_method("init"):
		tasks.init(self)
	if levers and levers.has_method("init"):
		levers.init(self)
	if doors and doors.has_method("init"):
		doors.init(self)
	if debug and debug.has_method("init"):
		debug.init(self)
	save = preload("res://db/db_save.gd").new()
	if save and save.has_method("init"):
		save.init(self)

# -----------------------
# Общие помощники
# -----------------------
func _ensure_db() -> bool:
	if db == null:
		push_error("DbMeneger: DB is not initialized")
		return false
	return true

# -----------------------
# Делегирующие методы (используются в проекте)
# -----------------------
# Tasks
func assign_task(level: int, computer_id: int) -> Dictionary:
	if tasks and tasks.has_method("assign_task"):
		return tasks.assign_task(level, computer_id)
	return {}

func get_current_task(level: int, computer_id: int) -> Dictionary:
	if tasks and tasks.has_method("get_current_task"):
		return tasks.get_current_task(level, computer_id)
	return {}

func unassign_task(level: int, computer_id: int) -> void:
	if tasks and tasks.has_method("unassign_task"):
		tasks.unassign_task(level, computer_id)

# Levers
func set_lever_state(lever_id: int, is_down: bool) -> void:
	if levers and levers.has_method("set_lever_state"):
		levers.set_lever_state(lever_id, is_down)

func get_lever_state(lever_id: int) -> Variant:
	if levers and levers.has_method("get_lever_state"):
		return levers.get_lever_state(lever_id)
	return null

func link_lever_to_computer(lever_id: int, computer_id: int) -> void:
	if levers and levers.has_method("link_lever_to_computer"):
		levers.link_lever_to_computer(lever_id, computer_id)

func link_lever_to_door(lever_id: int, door_id: int) -> void:
	if levers and levers.has_method("link_lever_to_door"):
		levers.link_lever_to_door(lever_id, door_id)

func is_computer_accessible(computer_id: int) -> bool:
	if levers and levers.has_method("is_computer_accessible"):
		return levers.is_computer_accessible(computer_id)
	# fallback: доступ открыт
	return true

# Doors
func link_computer_to_door(computer_id: int, door_id: int) -> void:
	if doors and doors.has_method("link_computer_to_door"):
		doors.link_computer_to_door(computer_id, door_id)

func get_doors_for_computer(computer_id: int) -> Array:
	if doors and doors.has_method("get_doors_for_computer"):
		return doors.get_doors_for_computer(computer_id)
	return []

func is_door_accessible(door_id: int) -> bool:
	if doors and doors.has_method("is_door_accessible"):
		return doors.is_door_accessible(door_id)
	# fallback: доступ открыт
	return true

# Debug
func debug_dump_all() -> void:
	if debug and debug.has_method("debug_dump_all"):
		debug.debug_dump_all()

func debug_insert_sample_tasks() -> void:
	if debug and debug.has_method("debug_insert_sample_tasks"):
		debug.debug_insert_sample_tasks()
		
# Save
func has_save() -> bool:
	if save and save.has_method("has_save"):
		return save.has_save()
	return false

func set_save(scene_path: String, pos: Vector2) -> void:
	if save and save.has_method("set_save"):
		save.set_save(scene_path, pos)

func get_save() -> Dictionary:
	if save and save.has_method("get_save"):
		return save.get_save()
	return {}

func clear_save() -> void:
	if save and save.has_method("clear_save"):
		save.clear_save()
		
func reset_all() -> void:
	if not _ensure_db():
		return

	print("DbMeneger: FULL RESET")

	# Удаляем данные
	db.query("DELETE FROM tasks")
	db.query("DELETE FROM lever_states")
	db.query("DELETE FROM door_states")
	db.query("DELETE FROM lever_to_computer")
	db.query("DELETE FROM lever_to_door")
	db.query("DELETE FROM save")

	# Сброс автоинкремента (на всякий случай)
	db.query("VACUUM")

	print("DbMeneger: reset complete")
	
# Doors state (нужно, чтобы двери сохранялись)
func set_door_state(door_id: int, opened: bool) -> void:
	if doors and doors.has_method("set_door_state"):
		doors.set_door_state(door_id, opened)

func get_door_state(door_id: int) -> Variant:
	if doors and doors.has_method("get_door_state"):
		return doors.get_door_state(door_id)
	return null
