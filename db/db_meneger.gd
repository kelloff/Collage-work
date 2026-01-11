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
            expected_code TEXT,
            expected_output TEXT,
            required_patterns TEXT
        )
	""")

	# таблица прогресса (закреплённые задания для каждого компьютера)
	db.query("""
        CREATE TABLE IF NOT EXISTS progress (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            level INTEGER,
            computer_id INTEGER,
            current_task_id INTEGER
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
			"expected_code": task["expected_code"],
			"expected_output": task["expected_output"],
			"required_patterns": task["required_patterns"]
		})

# --- Получить текущее закреплённое задание ---
func get_current_task(level: int, computer_id: int) -> Dictionary:
	db.query("SELECT current_task_id FROM progress WHERE level = %d AND computer_id = %d" % [level, computer_id])
	var rows = db.query_result
	if rows.size() > 0 and rows[0]["current_task_id"] != null:
		var task_id = int(rows[0]["current_task_id"])
		db.query("SELECT * FROM tasks WHERE id = %d" % task_id)
		if db.query_result.size() > 0:
			return db.query_result[0]
	return {}

# --- Назначить новое задание и закрепить ---
func assign_task(level: int, computer_id: int) -> Dictionary:
	var current = get_current_task(level, computer_id)
	if not current.is_empty():
		return current

	db.query("SELECT * FROM tasks WHERE level = %d" % level)
	var rows = db.query_result
	if rows.size() > 0:
		var task = rows[randi() % rows.size()]
		db.query("DELETE FROM progress WHERE level = %d AND computer_id = %d" % [level, computer_id])
		db.insert_row("progress", {"level": level, "computer_id": computer_id, "current_task_id": task["id"]})
		return task

	return {}

# --- Открепить задание после выполнения ---
func unassign_task(level: int, computer_id: int) -> void:
	db.query("DELETE FROM progress WHERE level = %d AND computer_id = %d" % [level, computer_id])
