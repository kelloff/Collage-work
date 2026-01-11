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

	# таблица прогресса
	db.query("""
        CREATE TABLE IF NOT EXISTS progress (
            task_id INTEGER UNIQUE
        )
	""")

	# если таблица пустая — вставляем дефолтные задания
	db.query("SELECT * FROM tasks")
	if db.query_result.size() == 0:
		_insert_default_tasks()

# --- Вставка дефолтных заданий через insert_row ---
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

# --- Пометить задание как использованное ---
func mark_task_as_used(task_id: int):
	db.insert_row("progress", {"task_id": task_id})

# --- Получение случайного задания по уровню ---
func get_random_task_by_level(level: int) -> Dictionary:
	db.query("SELECT * FROM tasks WHERE level = %d AND id NOT IN (SELECT task_id FROM progress)" % level)
	var rows = db.query_result

	if rows.size() > 0:
		var task = rows[randi() % rows.size()]
		mark_task_as_used(task["id"])
		return task

	return {}
