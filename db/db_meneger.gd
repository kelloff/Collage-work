extends Node

# DbMeneger.gd
# Менеджер БД: таблицы tasks, progress, lever_links, lever_states и утилиты для работы с ними.
# Совместим с Godot 4: без тернарного оператора ?:, без get(..., default) и с защитой от null db.

var db: SQLite = null

func _ready() -> void:
	randomize()

	# Инициализируем DB до любых операций с ним
	db = SQLite.new()
	db.path = "res://tasks.db"
	if not db.open_db():
		push_error("DbMeneger: cannot open DB")
		db = null
		return

	# Создаём таблицы, если их нет
	db.query("""
		CREATE TABLE IF NOT EXISTS computers (
			id INTEGER PRIMARY KEY,
			name TEXT UNIQUE
		)
	""")

	db.query("""
		CREATE TABLE IF NOT EXISTS tasks (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			level INTEGER,
			category TEXT,
			description TEXT UNIQUE,
			expected_output TEXT,
			required_patterns TEXT,
			check_type TEXT,
			required_keywords TEXT,
			allow_direct_print INTEGER
		)
	""")

	db.query("""
		CREATE TABLE IF NOT EXISTS progress (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			level INTEGER,
			computer_id INTEGER,
			task_id INTEGER,
			status TEXT
		)
	""")

	db.query("""
		CREATE TABLE IF NOT EXISTS lever_links (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			lever_id INTEGER,
			computer_id INTEGER
		)
	""")

	db.query("""
		CREATE TABLE IF NOT EXISTS lever_states (
			lever_id INTEGER PRIMARY KEY,
			is_down INTEGER
		)
	""")

	print("DbMeneger: ready, DB path:", db.path)

	# Загружаем дефолтные задания (путь по умолчанию res://db/task_data.gd)
	


# --- backward-compatible alias (если где-то вызывают старое имя) ---
func debug_dump_tables() -> void:
	debug_dump_all()


# --- tasks helpers ---
func _ensure_db() -> bool:
	if db == null:
		push_error("DbMeneger: DB is not initialized")
		return false
	return true

func get_current_task(level: int, computer_id: int) -> Dictionary:
	load_default_tasks_from_file("res://db/task_data.gd")
	if not _ensure_db():
		return {}

	# Возвращает полную запись задачи, если уже назначена (status = 'assigned')
	db.query("SELECT task_id FROM progress WHERE level = %d AND computer_id = %d AND status = 'assigned'" % [level, computer_id])
	if db.query_result.size() > 0:
		var task_id = int(db.query_result[0]["task_id"])
		db.query("SELECT * FROM tasks WHERE id = %d" % task_id)
		if db.query_result.size() > 0:
			return db.query_result[0]

	# Если есть done — возвращаем сообщение
	db.query("SELECT * FROM progress WHERE level = %d AND computer_id = %d AND status = 'done'" % [level, computer_id])
	if db.query_result.size() > 0:
		return {"message": "Ты уже выполнил задание, продвигайся дальше"}

	return {}

func assign_task(level: int, computer_id: int) -> Dictionary:
	if not _ensure_db():
		return {}

	# Логирование для отладки
	print("DbMeneger.assign_task called: level=", level, "computer_id=", computer_id)
	db.query("SELECT * FROM tasks WHERE level = %d" % level)
	print("  tasks for level:", db.query_result)

	var current = get_current_task(level, computer_id)
	if not current.is_empty():
		return current

	db.query("SELECT * FROM progress WHERE level = %d AND computer_id = %d AND status = 'done'" % [level, computer_id])
	if db.query_result.size() > 0:
		return {"message": "Ты уже выполнил задание, продвигайся дальше"}

	db.query("SELECT * FROM tasks WHERE level = %d" % level)
	var rows = db.query_result
	if rows.size() == 0:
		return {}

	db.query("SELECT task_id FROM progress WHERE level = %d AND status = 'assigned'" % level)
	var busy_ids = []
	for row in db.query_result:
		busy_ids.append(int(row["task_id"]))

	var available = []
	for task in rows:
		var tid = int(task["id"])
		if not busy_ids.has(tid):
			available.append(task)

	if available.size() == 0:
		return {"message": "Все задания уровня %d уже назначены" % level}

	var task = available[randi() % available.size()]
	db.insert_row("progress", {"level": level, "computer_id": computer_id, "task_id": task["id"], "status": "assigned"})
	# Возвращаем полную запись задачи (Dictionary)
	return task

func unassign_task(level: int, computer_id: int) -> void:
	if not _ensure_db():
		return
	# Помечаем назначенное задание как done для данного компьютера и уровня
	db.query("UPDATE progress SET status = 'done' WHERE level = %d AND computer_id = %d AND status = 'assigned'" % [level, computer_id])


# --- lever links and states ---
func link_lever_to_computer(lever_id: int, computer_id: int) -> void:
	if not _ensure_db():
		return
	db.query("SELECT * FROM lever_links WHERE lever_id = %d AND computer_id = %d" % [lever_id, computer_id])
	if db.query_result.size() == 0:
		db.insert_row("lever_links", {"lever_id": lever_id, "computer_id": computer_id})
		print("DbMeneger: linked lever %d -> computer %d" % [lever_id, computer_id])
	else:
		print("DbMeneger: link already exists %d -> %d" % [lever_id, computer_id])

func clear_lever_links() -> void:
	if not _ensure_db():
		return
	db.query("DELETE FROM lever_links")
	print("DbMeneger: cleared lever_links")

func set_lever_state(lever_id: int, is_down: bool) -> void:
	if not _ensure_db():
		return
	db.query("INSERT OR REPLACE INTO lever_states (lever_id, is_down) VALUES (%d, %d)" % [lever_id, (1 if is_down else 0)])
	print("DbMeneger: set_lever_state lever=%d is_down=%d" % [lever_id, (1 if is_down else 0)])

func is_computer_accessible(computer_id: int) -> bool:
	if not _ensure_db():
		# Если DB не инициализирована, безопаснее вернуть false (или true по желанию)
		push_error("DbMeneger: is_computer_accessible called but DB not initialized")
		return false

	db.query("SELECT lever_id FROM lever_links WHERE computer_id = %d" % computer_id)
	var rows = db.query_result
	print("DbMeneger: checking access for computer", computer_id, "linked_count=", rows.size())
	if rows.size() == 0:
		print("DbMeneger: no links -> accessible")
		return true
	for row in rows:
		var lever_id = int(row["lever_id"])
		db.query("SELECT is_down FROM lever_states WHERE lever_id = %d" % lever_id)
		if db.query_result.size() == 0:
			print("DbMeneger: lever", lever_id, "has NO state -> denying access")
			return false
		var is_down = int(db.query_result[0]["is_down"])
		print("DbMeneger: lever", lever_id, "is_down=", is_down)
		# Семантика: is_down == 1 означает опущен; если хоть один рычаг поднят (is_down == 0) — доступ запрещён
		if is_down == 0:
			print("DbMeneger: lever", lever_id, "is UP -> denying access")
			return false
	print("DbMeneger: all linked levers are down -> accessible")
	return true


# --- debug helpers (safe, non-destructive) ---
func debug_dump_all() -> void:
	if not _ensure_db():
		return
	db.query("SELECT * FROM tasks")
	print("DEBUG tasks:", db.query_result)
	db.query("SELECT * FROM progress")
	print("DEBUG progress:", db.query_result)
	db.query("SELECT * FROM lever_links")
	print("DEBUG lever_links:", db.query_result)
	db.query("SELECT * FROM lever_states")
	print("DEBUG lever_states:", db.query_result)

func debug_insert_sample_tasks() -> void:
	if not _ensure_db():
		return
	var sample = [
		{"level": 1, "category":"basic", "description":"print Hello", "expected_output":"Hello", "required_patterns":"", "check_type":"stdout_exact", "required_keywords":"", "allow_direct_print":1},
		{"level": 1, "category":"basic", "description":"sum 2+2", "expected_output":"4", "required_patterns":"", "check_type":"numeric_logic", "required_keywords":"", "allow_direct_print":0}
	]
	for t in sample:
		db.query("SELECT id FROM tasks WHERE description = '%s'" % t["description"].replace("'", "''"))
		if db.query_result.size() == 0:
			db.insert_row("tasks", t)
			print("DbMeneger: inserted sample task:", t["description"])
		else:
			print("DbMeneger: sample task already exists:", t["description"])

func debug_clear_progress() -> void:
	if not _ensure_db():
		return
	db.query("DELETE FROM progress")
	print("DbMeneger: cleared progress")


# --- load default tasks from task_data.gd ---
func load_default_tasks_from_file(path: String = "res://db/task_data.gd") -> void:
	if not _ensure_db():
		return

	var script_res = load(path)
	if script_res == null:
		print("DbMeneger: cannot load task data script at", path)
		return

	# Создаём экземпляр скрипта, если это Script, иначе используем ресурс как есть
	var td = null
	if script_res is Script:
		td = script_res.new()
	else:
		td = script_res

	if td == null:
		print("DbMeneger: failed to instantiate task data")
		return

	# Получаем default_tasks безопасно
	var tasks_arr = null
	# Если td — Dictionary или Object с полем, попытка прямого доступа
	if "default_tasks" in td:
		tasks_arr = td.default_tasks
	elif td.has_method("get"):
		# на случай, если td — не Node, но поддерживает get
		tasks_arr = td.get("default_tasks")
	else:
		tasks_arr = null

	if typeof(tasks_arr) != TYPE_ARRAY:
		print("DbMeneger: default_tasks not found or not an Array in", path)
		return

	var inserted = 0
	for t in tasks_arr:
		if typeof(t) != TYPE_DICTIONARY:
			continue
		var desc = str(t.get("description", "")).replace("'", "''")
		if desc == "":
			continue
		db.query("SELECT id FROM tasks WHERE description = '%s'" % desc)
		if db.query_result.size() == 0:
			var row = {
				"level": int(t.get("level", 0)),
				"category": str(t.get("category", "")),
				"description": str(t.get("description", "")),
				"expected_output": str(t.get("expected_output", "")),
				"required_patterns": str(t.get("required_patterns", "")),
				"check_type": str(t.get("check_type", "stdout_exact")),
				"required_keywords": str(t.get("required_keywords", "")),
				"allow_direct_print": int(t.get("allow_direct_print", 0))
			}
			db.insert_row("tasks", row)
			inserted += 1

	#print("DbMeneger: load_default_tasks_from_file finished, inserted:", inserted)
