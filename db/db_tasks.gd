# res://scripts/db/db_tasks.gd
extends Node
class_name DbTasks

var dbm: Node = null

func init(db_manager: Node) -> void:
	dbm = db_manager
	if dbm and dbm._ensure_db():
		_create_tables()
		# На всякий случай проверяем схему progress повторно:
		# если где-то миграция не применилась (шаблонная БД/особенности gdsqlite),
		# пересоздадим прогресс принудительно.
		_ensure_progress_schema(true)
		# Безопасно чистим только если колонка `status` реально существует.
		var db = dbm.db
		db.query("PRAGMA table_info(progress)")
		var progress_cols: Array = []
		for row in db.query_result:
			var name := str(row.get("name", ""))
			if name != "":
				progress_cols.append(name)

		if progress_cols.has("status"):
			# Если мы перегенерировали tasks (через AI), то нужно сбросить
			# только "assigned" задачи, чтобы терминалы не показывали старые
			# активные задания. done (открытые двери) трогаем не надо.
			dbm.db.query("DELETE FROM progress WHERE status = 'assigned'")
		else:
			print("DbTasks.init: skip clearing progress; progress.status column missing. cols=", progress_cols)
		load_default_tasks_from_file("res://db/task_data.gd")

func _create_tables() -> void:
	var db = dbm.db
	# Жёсткая страховка от несовпадения схемы template/user DB:
	# всегда пересоздаём таблицы tasks/progress в ожидаемом формате.
	# Это сбросит прогресс/связанные данные, зато убирает постоянные SQL-ошибки.
	db.query("DROP TABLE IF EXISTS progress")
	db.query("DROP TABLE IF EXISTS tasks")

	db.query("""
		CREATE TABLE IF NOT EXISTS tasks (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			level INTEGER,
			category TEXT,
			description TEXT UNIQUE,
			expected_code TEXT,
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

func _ensure_tasks_schema() -> void:
	var db = dbm.db
	db.query("PRAGMA table_info(tasks)")
	var cols: Array = []
	for row in db.query_result:
		var name := str(row.get("name", ""))
		if name != "":
			cols.append(name)

	# Если схема задач не совпадает с тем, что ожидает игра/вставка,
	# то ALTER TABLE может не сработать в gdsqlite.
	# В этом случае безопаснее пересоздать таблицу и потом заново загрузить tasks из task_data.gd.
	var required := {
		"level": "INTEGER",
		"category": "TEXT",
		"description": "TEXT",
		"expected_code": "TEXT",
		"expected_output": "TEXT",
		"required_patterns": "TEXT",
		"check_type": "TEXT",
		"required_keywords": "TEXT",
		"allow_direct_print": "INTEGER",
	}

	var missing: Array = []
	for k in required.keys():
		if not cols.has(k):
			missing.append(k)

	if missing.size() > 0:
		print("DbTasks._ensure_tasks_schema: schema mismatch, missing=", missing, " recreating tasks table...")
		db.query("DROP TABLE IF EXISTS tasks")
		db.query("""
			CREATE TABLE IF NOT EXISTS tasks (
				id INTEGER PRIMARY KEY AUTOINCREMENT,
				level INTEGER,
				category TEXT,
				description TEXT UNIQUE,
				expected_code TEXT,
				expected_output TEXT,
				required_patterns TEXT,
				check_type TEXT,
				required_keywords TEXT,
				allow_direct_print INTEGER
			)
		""")

		# Проверяем результат миграции.
		db.query("PRAGMA table_info(tasks)")
		var cols_after: Array = []
		for row2 in db.query_result:
			var n2 := str(row2.get("name", ""))
			if n2 != "":
				cols_after.append(n2)
		print("DbTasks._ensure_tasks_schema: after cols=", cols_after)

func _ensure_progress_schema(force_recreate_if_broken: bool) -> void:
	var db = dbm.db
	db.query("PRAGMA table_info(progress)")
	var cols: Array = []
	for row in db.query_result:
		var name := str(row.get("name", ""))
		if name != "":
			cols.append(name)

	# Ожидаемая схема:
	var required := {
		"level": "INTEGER",
		"computer_id": "INTEGER",
		"task_id": "INTEGER",
		"status": "TEXT",
	}

	print("DbTasks._ensure_progress_schema: before cols=", cols)

	var missing: Array = []
	for k in required.keys():
		if not cols.has(k):
			missing.append(k)

	if missing.size() > 0:
		print("DbTasks._ensure_progress_schema: schema mismatch, missing=", missing, " recreating progress table...")
		db.query("DROP TABLE IF EXISTS progress")
		db.query("""
			CREATE TABLE IF NOT EXISTS progress (
				id INTEGER PRIMARY KEY AUTOINCREMENT,
				level INTEGER,
				computer_id INTEGER,
				task_id INTEGER,
				status TEXT
			)
		""")

		# Проверяем результат миграции.
		db.query("PRAGMA table_info(progress)")
		var cols_after: Array = []
		for row2 in db.query_result:
			var name2 := str(row2.get("name", ""))
			if name2 != "":
				cols_after.append(name2)
		print("DbTasks._ensure_progress_schema: after cols=", cols_after)
	elif force_recreate_if_broken:
		# Если всё есть — ничего не делаем.
		pass

func load_default_tasks_from_file(path: String = "res://db/task_data.gd") -> void:
	if not dbm._ensure_db():
		return
	var db = dbm.db

	# Берем реальный набор колонок, чтобы вставлять только то, что существует в схеме
	# (иногда template DB уже имеет таблицу `tasks` со старой структурой).
	db.query("PRAGMA table_info(tasks)")
	var task_cols: Array = []
	for r in db.query_result:
		var n := str(r.get("name", ""))
		if n != "":
			task_cols.append(n)

	# Если task_data.gd был сгенерирован AI-скриптом, то перед вставкой
	# полностью очищаем таблицы, чтобы старые задания не оставались в БД.
	var is_autogenerated: bool = false
	var fa: FileAccess = FileAccess.open(path, FileAccess.READ)
	if fa:
		var first_line: String = fa.get_line()
		is_autogenerated = first_line.begins_with("# AUTOGENERATED")
		fa.close()
	else:
		print("DbTasks.load_default_tasks_from_file: FileAccess.open failed for:", path)

	if is_autogenerated:
		# Очищать БД будем ПОСЛЕ успешной загрузки task_data.gd и проверки массива.
		# Иначе можно оставить таблицу пустой, если загрузка/парсинг сорвутся.
		pass

	var script_res = load(path)
	if script_res == null:
		print("DbTasks.load_default_tasks_from_file: load(path) failed for:", path)
		return
	var td = script_res if not (script_res is Script) else script_res.new()
	if td == null:
		print("DbTasks.load_default_tasks_from_file: td is null for:", path)
		return
	var tasks_arr = null
	if "default_tasks" in td:
		tasks_arr = td.default_tasks
	elif td.has_method("get"):
		tasks_arr = td.get("default_tasks")
	if typeof(tasks_arr) != TYPE_ARRAY:
		print("DbTasks.load_default_tasks_from_file: tasks_arr is not array. type=", typeof(tasks_arr), " path=", path)
		return
	var inserted_count: int = 0

	if is_autogenerated:
		# При генерации новых заданий из AI:
		# - убираем старые задачи из `tasks`
		# - но НЕ трогаем `done` в `progress`, чтобы уже открытые двери/доступы не ломались
		# - убираем только активные `assigned`, чтобы терминалы не цепляли старые task_id
		db.query("DELETE FROM tasks")
		db.query("DELETE FROM progress WHERE status = 'assigned'")

	for t in tasks_arr:
		if typeof(t) != TYPE_DICTIONARY:
			continue
		var desc = str(t.get("description", "")).replace("'", "''")
		if desc == "":
			continue
		db.query("SELECT id FROM tasks WHERE description = '%s'" % desc)
		if db.query_result.size() == 0:
			var row: Dictionary = {}
			if task_cols.has("level"):
				row["level"] = int(t.get("level", 0))
			if task_cols.has("category"):
				row["category"] = str(t.get("category", ""))
			if task_cols.has("description"):
				row["description"] = str(t.get("description", ""))
			if task_cols.has("expected_output"):
				row["expected_output"] = str(t.get("expected_output", ""))
			if task_cols.has("required_patterns"):
				row["required_patterns"] = str(t.get("required_patterns", ""))
			if task_cols.has("check_type"):
				row["check_type"] = str(t.get("check_type", "stdout_exact"))
			if task_cols.has("required_keywords"):
				row["required_keywords"] = str(t.get("required_keywords", ""))
			if task_cols.has("allow_direct_print"):
				row["allow_direct_print"] = int(t.get("allow_direct_print", 0))

			db.insert_row("tasks", row)
			inserted_count += 1

			# Мини-проверка: убедимся, что хотя бы 1 запись реально появилась.
			if inserted_count == 1:
				db.query("SELECT id FROM tasks WHERE description = '%s' LIMIT 1" % desc)
				if db.query_result.size() == 0:
					print("DbTasks.load_default_tasks_from_file: INSERT failed for description:", desc)

	db.query("SELECT COUNT(*) as cnt FROM tasks")
	var total_tasks: int = 0
	if db.query_result.size() > 0:
		var r: Dictionary = db.query_result[0]
		total_tasks = int(r.get("cnt", r.get("COUNT(*)", 0)))
	print("DbTasks.load_default_tasks_from_file:", "autogen=", is_autogenerated, "tasks_arr=", tasks_arr.size(), "inserted=", inserted_count, "total_tasks=", total_tasks, "count_row=", db.query_result)

func get_current_task(level: int, computer_id: int) -> Dictionary:
	if not dbm._ensure_db():
		return {}
	var db = dbm.db
	# Для каждого компьютера держим одну "актуальную" запись прогресса.
	db.query("SELECT level, task_id, status FROM progress WHERE computer_id = %d ORDER BY id DESC LIMIT 1" % computer_id)
	if db.query_result.size() == 0:
		return {}

	var row: Dictionary = db.query_result[0]
	var task_id: int = int(row.get("task_id", 0))
	var status: String = str(row.get("status", ""))

	if task_id > 0:
		db.query("SELECT * FROM tasks WHERE id = %d LIMIT 1" % task_id)
		if db.query_result.size() > 0:
			var task: Dictionary = db.query_result[0]
			# При done возвращаем специальное сообщение, но task остается
			# "прикреплён" к этому компьютеру навсегда.
			if status == "done":
				return {
					"message": "Ты уже выполнил это задание, продвигайся дальше",
					"id": task_id,
					"status": "done",
					"description": str(task.get("description", ""))
				}
			task["status"] = status
			return task

		# ВАЖНО:
		# после AI-перегенерации tasks таблица может поменять id,
		# а progress (особенно status='done') останется. Тогда task по task_id не найдётся.
		# Для done возвращаем сообщение, чтобы терминал работал корректно.
		if status == "done":
			return {
				"message": "Ты уже выполнил это задание, продвигайся дальше",
				"id": task_id,
				"status": "done",
				"description": ""
			}

	return {}

func assign_task(level: int, computer_id: int) -> Dictionary:
	if not dbm._ensure_db():
		return {}
	var db = dbm.db
	var current = get_current_task(level, computer_id)
	if not current.is_empty():
		return current

	# Ищем только AI-задачи (описание с префиксом "AI:").
	db.query("SELECT * FROM tasks WHERE level = %d AND description LIKE 'AI:%'" % level)
	var rows = db.query_result
	# fallback, если вдруг AI-задач нет
	if rows.size() == 0:
		db.query("SELECT * FROM tasks WHERE level = %d" % level)
		rows = db.query_result
	if rows.size() == 0:
		return {}

	# Неповторяемость задач:
	# если задача уже была когда-либо выдана какому-либо компьютеру,
	# больше её не выдаём.
	db.query("SELECT task_id FROM progress WHERE task_id > 0")
	var busy_ids: Array = []
	for row in db.query_result:
		busy_ids.append(int(row["task_id"]))

	var available: Array = []
	for task in rows:
		var tid = int(task["id"])
		if not busy_ids.has(tid):
			available.append(task)
	if available.size() == 0:
		return {"message": "Все задания уровня %d уже назначены" % level}
	var task = available[randi() % available.size()]

	# Чистим возможный старый мусор по этому компьютеру и пишем 1 запись assigned.
	db.query("DELETE FROM progress WHERE computer_id = %d" % computer_id)
	db.query("INSERT INTO progress (level, computer_id, task_id, status) VALUES (%d, %d, %d, 'assigned')" % [level, computer_id, int(task["id"])])

	db.query("SELECT level, computer_id, task_id, status FROM progress WHERE computer_id = %d" % computer_id)
	print("DbTasks.assign_task: rows for computer=%d -> %s" % [computer_id, str(db.query_result)])
	return task

func unassign_task(level: int, computer_id: int) -> void:
	if not dbm._ensure_db():
		return
	var db = dbm.db
	print("DbTasks.unassign_task: marking DONE for level=%d, computer=%d" % [level, computer_id])

	# Берём прикреплённый task_id, чтобы он навсегда остался за компьютером.
	db.query("SELECT level, task_id, status FROM progress WHERE computer_id = %d ORDER BY id DESC LIMIT 1" % computer_id)
	var task_id: int = 0
	var row_level: int = level
	if db.query_result.size() > 0:
		var row: Dictionary = db.query_result[0]
		task_id = int(row.get("task_id", 0))
		row_level = int(row.get("level", level))

	# Нормализуем: по компьютеру одна запись со статусом done.
	db.query("DELETE FROM progress WHERE computer_id = %d" % computer_id)
	db.query("INSERT INTO progress (level, computer_id, task_id, status) VALUES (%d, %d, %d, 'done')" % [row_level, computer_id, task_id])

	db.query("SELECT level, computer_id, task_id, status FROM progress WHERE computer_id = %d" % computer_id)
	print("DbTasks.unassign_task: rows after DONE normalize -> %s" % str(db.query_result))
