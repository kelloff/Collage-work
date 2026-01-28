# res://scripts/db/db_tasks.gd
extends Node
class_name DbTasks

var dbm: Node = null

func init(db_manager: Node) -> void:
	dbm = db_manager
	if dbm and dbm._ensure_db():
		_create_tables()
		load_default_tasks_from_file("res://db/task_data.gd")

func _create_tables() -> void:
	var db = dbm.db
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

func load_default_tasks_from_file(path: String = "res://db/task_data.gd") -> void:
	if not dbm._ensure_db():
		return
	var db = dbm.db
	var script_res = load(path)
	if script_res == null:
		return
	var td = script_res if not (script_res is Script) else script_res.new()
	if td == null:
		return
	var tasks_arr = null
	if "default_tasks" in td:
		tasks_arr = td.default_tasks
	elif td.has_method("get"):
		tasks_arr = td.get("default_tasks")
	if typeof(tasks_arr) != TYPE_ARRAY:
		return
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

func get_current_task(level: int, computer_id: int) -> Dictionary:
	if not dbm._ensure_db():
		return {}
	var db = dbm.db
	db.query("SELECT task_id FROM progress WHERE level = %d AND computer_id = %d AND status = 'assigned'" % [level, computer_id])
	if db.query_result.size() > 0:
		var task_id = int(db.query_result[0]["task_id"])
		db.query("SELECT * FROM tasks WHERE id = %d" % task_id)
		if db.query_result.size() > 0:
			return db.query_result[0]
	db.query("SELECT * FROM progress WHERE level = %d AND computer_id = %d AND status = 'done'" % [level, computer_id])
	if db.query_result.size() > 0:
		return {"message": "Ты уже выполнил задание, продвигайся дальше"}
	return {}

func assign_task(level: int, computer_id: int) -> Dictionary:
	if not dbm._ensure_db():
		return {}
	var db = dbm.db
	var current = get_current_task(level, computer_id)
	if not current.is_empty():
		return current
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
	return task

func unassign_task(level: int, computer_id: int) -> void:
	if not dbm._ensure_db():
		return
	var db = dbm.db
	db.query("UPDATE progress SET status = 'done' WHERE level = %d AND computer_id = %d AND status = 'assigned'" % [level, computer_id])
