extends Node

var db: SQLite

func _ready():
	randomize()
	db = SQLite.new()
	db.path = "res://tasks.db"
	if not db.open_db():
		push_error("Не удалось открыть БД")
		return

	# таблица заданий
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

	# таблица прогресса (история + статус)
	db.query("""
        CREATE TABLE IF NOT EXISTS progress (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            level INTEGER,
            computer_id INTEGER,
            task_id INTEGER,
			status TEXT   -- "assigned" или "done"
        )
	""")

	# если таблица пустая — вставляем дефолтные задания
	db.query("SELECT * FROM tasks")
	if db.query_result.size() == 0:
		_insert_default_tasks()

# --- Вставка дефолтных заданий ---
func _insert_default_tasks():
	var tasks = preload("res://db/task_data.gd").new().default_tasks
	for task in tasks:
		db.insert_row("tasks", {
			"level": task["level"],
			"category": task["category"],
			"description": task["description"],
			"expected_output": task["expected_output"],
			"required_patterns": task.get("required_patterns", ""),
			"check_type": task.get("check_type", "stdout_exact"),
			"required_keywords": task.get("required_keywords", ""),
			"allow_direct_print": task.get("allow_direct_print", 0)
		})

# --- Получить текущее задание ---
func get_current_task(level: int, computer_id: int) -> Dictionary:
	# проверяем активное задание
	db.query("SELECT task_id FROM progress WHERE level = %d AND computer_id = %d AND status = 'assigned'" % [level, computer_id])
	var rows = db.query_result
	if rows.size() > 0:
		var task_id = int(rows[0]["task_id"])
		db.query("SELECT * FROM tasks WHERE id = %d" % task_id)
		if db.query_result.size() > 0:
			return db.query_result[0]

	# если активного нет, но есть выполненные
	db.query("SELECT * FROM progress WHERE level = %d AND computer_id = %d AND status = 'done'" % [level, computer_id])
	if db.query_result.size() > 0:
		return {"message": "Ты уже выполнил задание, продвигайся дальше"}

	return {}

# --- Назначить новое задание ---
func assign_task(level: int, computer_id: int) -> Dictionary:
	var current = get_current_task(level, computer_id)
	if not current.is_empty():
		return current

	# проверяем, есть ли выполненные задания
	db.query("SELECT * FROM progress WHERE level = %d AND computer_id = %d AND status = 'done'" % [level, computer_id])
	if db.query_result.size() > 0:
		return {"message": "Ты уже выполнил задание, продвигайся дальше"}

	# все задания уровня
	db.query("SELECT * FROM tasks WHERE level = %d" % level)
	var rows = db.query_result
	if rows.size() == 0:
		return {}

	# исключаем задания, которые уже назначены другим компьютерам
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
	return task

# --- Завершить задание ---
func unassign_task(level: int, computer_id: int) -> void:
	db.query("UPDATE progress SET status = 'done' WHERE level = %d AND computer_id = %d AND status = 'assigned'" % [level, computer_id])
