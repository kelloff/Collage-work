extends Node
class_name DbTerminalCode

var dbm: Node = null

const LEGACY_SAVE_PATH := "user://terminal_last_code.txt"


func init(db_manager: Node) -> void:
	dbm = db_manager
	if dbm and dbm._ensure_db():
		_create_table()


func _create_table() -> void:
	var db = dbm.db
	db.query("""
		CREATE TABLE IF NOT EXISTS terminal_code (
			level INTEGER NOT NULL,
			computer_id INTEGER NOT NULL,
			code_text TEXT NOT NULL DEFAULT '',
			updated_at INTEGER NOT NULL DEFAULT 0,
			PRIMARY KEY (level, computer_id)
		)
	""")


func get_code(level: int, computer_id: int) -> String:
	if computer_id <= 0 or not dbm._ensure_db():
		return ""
	var db = dbm.db
	db.query(
		"SELECT code_text FROM terminal_code WHERE level = %d AND computer_id = %d"
		% [int(level), int(computer_id)]
	)
	if db.query_result.size() > 0:
		return str(db.query_result[0].get("code_text", ""))
	return _maybe_import_legacy_file(level, computer_id)


func set_code(level: int, computer_id: int, code_text: String) -> void:
	if computer_id <= 0 or not dbm._ensure_db():
		return
	var db = dbm.db
	var ts := int(Time.get_unix_time_from_system())
	var escaped := _sql_escape(code_text)
	db.query(
		"INSERT OR REPLACE INTO terminal_code (level, computer_id, code_text, updated_at) "
		+ "VALUES (%d, %d, '%s', %d)" % [int(level), int(computer_id), escaped, ts]
	)


func clear_all() -> void:
	if not dbm._ensure_db():
		return
	dbm.db.query("DELETE FROM terminal_code")


func _maybe_import_legacy_file(level: int, computer_id: int) -> String:
	if not FileAccess.file_exists(LEGACY_SAVE_PATH):
		return ""
	var db = dbm.db
	db.query("SELECT COUNT(*) AS cnt FROM terminal_code")
	var cnt := 0
	if db.query_result.size() > 0:
		cnt = int(db.query_result[0].get("cnt", db.query_result[0].get("COUNT(*)", 0)))
	if cnt > 0:
		return ""
	var f := FileAccess.open(LEGACY_SAVE_PATH, FileAccess.READ)
	if f == null:
		return ""
	var legacy := f.get_as_text()
	f.close()
	if legacy.strip_edges() != "":
		set_code(level, computer_id, legacy)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LEGACY_SAVE_PATH))
	return legacy


func _sql_escape(text: String) -> String:
	return str(text).replace("'", "''")
