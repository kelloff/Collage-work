# res://db/db_save.gd
extends Node

var core = null

func init(core_singleton) -> void:
	core = core_singleton
	_ensure_tables()

func _ensure_tables() -> void:
	if core == null or core.db == null:
		return

	core.db.query("""
		CREATE TABLE IF NOT EXISTS save_state (
			id INTEGER PRIMARY KEY CHECK (id = 1),
			scene_path TEXT NOT NULL,
			px REAL NOT NULL,
			py REAL NOT NULL,
			saved_at TEXT DEFAULT (datetime('now'))
		);
	""")

func has_save() -> bool:
	if core == null or core.db == null:
		return false
	core.db.query("SELECT 1 FROM save_state WHERE id=1 LIMIT 1;")
	return core.db.query_result.size() > 0

func set_save(scene_path: String, pos: Vector2) -> void:
	if core == null or core.db == null:
		return

	core.db.query("""
		INSERT INTO save_state (id, scene_path, px, py)
		VALUES (1, '%s', %f, %f)
		ON CONFLICT(id) DO UPDATE SET
			scene_path=excluded.scene_path,
			px=excluded.px,
			py=excluded.py,
			saved_at=datetime('now');
	""" % [scene_path, pos.x, pos.y])

func get_save() -> Dictionary:
	if core == null or core.db == null:
		return {}

	core.db.query("SELECT scene_path, px, py FROM save_state WHERE id=1 LIMIT 1;")
	if core.db.query_result.size() == 0:
		return {}

	var row = core.db.query_result[0]
	return {
		"scene_path": str(row["scene_path"]),
		"pos": Vector2(float(row["px"]), float(row["py"]))
	}

func clear_save() -> void:
	if core == null or core.db == null:
		return
	core.db.query("DELETE FROM save_state WHERE id=1;")
