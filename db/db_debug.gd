# res://scripts/db/db_debug.gd
extends Node
class_name DbDebug

var dbm: Node = null

func init(db_manager: Node) -> void:
	dbm = db_manager

func debug_dump_all() -> void:
	if not dbm._ensure_db():
		return
	var db = dbm.db
	db.query("SELECT * FROM tasks")
	print("DEBUG tasks:", db.query_result)
	db.query("SELECT * FROM progress")
	print("DEBUG progress:", db.query_result)
	db.query("SELECT * FROM lever_links")
	print("DEBUG lever_links:", db.query_result)
	db.query("SELECT * FROM lever_states")
	print("DEBUG lever_states:", db.query_result)
	db.query("SELECT * FROM computer_doors")
	print("DEBUG computer_doors:", db.query_result)
	db.query("SELECT * FROM lever_doors")
	print("DEBUG lever_doors:", db.query_result)

func debug_insert_sample_tasks() -> void:
	if not dbm._ensure_db():
		return
	var db = dbm.db
	var sample = [
		{"level": 1, "category":"basic", "description":"print Hello", "expected_output":"Hello", "required_patterns":"", "check_type":"stdout_exact", "required_keywords":"", "allow_direct_print":1},
		{"level": 1, "category":"basic", "description":"sum 2+2", "expected_output":"4", "required_patterns":"", "check_type":"numeric_logic", "required_keywords":"", "allow_direct_print":0}
	]
	for t in sample:
		db.query("SELECT id FROM tasks WHERE description = '%s'" % t["description"].replace("'", "''"))
		if db.query_result.size() == 0:
			db.insert_row("tasks", t)
			print("DbDebug: inserted sample task:", t["description"])
