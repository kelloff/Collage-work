# res://db/db_save.gd
extends Node
class_name DbSave

var core: Node = null
var db = null
const DEBUG_SAVE := true

func init(core_singleton: Node) -> void:
	core = core_singleton
	db = core.db
	_ensure_tables()
	_try_migrate_old_row()

func _ensure_tables() -> void:
	if core == null or core.db == null:
		if DEBUG_SAVE:
			print("DbSave._ensure_tables: core or db is null")
		return
	core.db.query("""
		CREATE TABLE IF NOT EXISTS save_state (
			id INTEGER PRIMARY KEY CHECK (id = 1),
			scene_path TEXT NOT NULL,
			data_json TEXT NOT NULL,
			saved_at TEXT DEFAULT (datetime('now'))
		);
	""")
	if DEBUG_SAVE:
		print("DbSave._ensure_tables: ensured save_state table")

func _try_migrate_old_row() -> void:
	if core == null or core.db == null:
		return
	core.db.query("SELECT name FROM sqlite_master WHERE type='table' AND name='save_state';")
	if core.db.query_result.size() == 0:
		return
	core.db.query("PRAGMA table_info('save_state');")
	var cols: Array = []
	for r in core.db.query_result:
		cols.append(str(r.get("name", "")))
	if "px" in cols and "py" in cols and not ("data_json" in cols):
		core.db.query("SELECT scene_path, px, py FROM save_state WHERE id=1 LIMIT 1;")
		if core.db.query_result.size() == 0:
			return
		var row = core.db.query_result[0]
		var scene_path = str(row.get("scene_path", ""))
		var px = float(row.get("px", 0.0))
		var py = float(row.get("py", 0.0))
		var payload = {
			"player_pos": [px, py],
			"player_hp": null,
			"maniacs": []
		}
		var json_text = JSON.stringify(payload)
		core.db.query("DELETE FROM save_state;")
		if core.db.has_method("insert_row"):
			var insert_row_data := {
				"id": 1,
				"scene_path": scene_path,
				"data_json": json_text
			}
			core.db.insert_row("save_state", insert_row_data)
		else:
			var scene_esc = scene_path.replace("'", "''")
			var json_esc = json_text.replace("'", "''")
			core.db.query("INSERT INTO save_state (id, scene_path, data_json, saved_at) VALUES (1, '%s', '%s', datetime('now'));" % [scene_esc, json_esc])
		core.db.query("SELECT scene_path, data_json FROM save_state LIMIT 1;")
		if DEBUG_SAVE:
			print("DbSave._try_migrate_old_row: migrated old px/py -> JSON, db row ->", core.db.query_result)

func set_save(save_data: Dictionary) -> void:
	if DEBUG_SAVE:
		print("DbSave.set_save called with:", save_data)
	if core == null or core.db == null:
		if DEBUG_SAVE:
			print("DbSave.set_save: core or db is null, abort")
		return
	if typeof(save_data) != TYPE_DICTIONARY:
		if DEBUG_SAVE:
			print("DbSave.set_save: expected Dictionary, got", typeof(save_data))
		return

	var scene_path: String = str(save_data.get("scene_path", ""))
	var raw_pos = save_data.get("player_pos", Vector2.ZERO)
	var px: float = 0.0
	var py: float = 0.0
	if typeof(raw_pos) == TYPE_VECTOR2:
		px = raw_pos.x
		py = raw_pos.y
	elif typeof(raw_pos) == TYPE_ARRAY and raw_pos.size() >= 2:
		px = float(raw_pos[0])
		py = float(raw_pos[1])
	elif typeof(raw_pos) == TYPE_STRING:
		var s = raw_pos.strip_edges()
		if s.begins_with("[") and s.ends_with("]"):
			s = s.substr(1, s.length() - 2)
		var parts = s.split(",")
		if parts.size() >= 2:
			px = float(parts[0])
			py = float(parts[1])
	else:
		px = 0.0
		py = 0.0

	var player_hp = save_data.get("player_hp", null)
	var maniacs = save_data.get("maniacs", [])
	var maniacs_serial: Array = []
	for m in maniacs:
		if typeof(m) == TYPE_VECTOR2:
			maniacs_serial.append([m.x, m.y])
		else:
			maniacs_serial.append(m)

	var payload = {
		"player_pos": [px, py],
		"player_hp": player_hp,
		"maniacs": maniacs_serial
	}
	var json_text: String = JSON.stringify(payload)
	if DEBUG_SAVE:
		print("DbSave.set_save: scene_path=", scene_path, " payload=", payload)
		print("DbSave.set_save: json_text =", json_text)

	core.db.query("DELETE FROM save_state;")

	if core.db.has_method("insert_row"):
		var insert_row_data := {
			"id": 1,
			"scene_path": scene_path,
			"data_json": json_text
		}
		core.db.insert_row("save_state", insert_row_data)
		if DEBUG_SAVE:
			print("DbSave.set_save: inserted via insert_row, db.query_result =", core.db.query_result)
	else:
		var scene_esc = scene_path.replace("'", "''")
		var json_esc = json_text.replace("'", "''")
		core.db.query("INSERT INTO save_state (id, scene_path, data_json, saved_at) VALUES (1, '%s', '%s', datetime('now'));" % [scene_esc, json_esc])
		if DEBUG_SAVE:
			print("DbSave.set_save: fallback insert executed, db.query_result =", core.db.query_result)

	core.db.query("SELECT scene_path, data_json, saved_at FROM save_state LIMIT 1;")
	if DEBUG_SAVE:
		print("DbSave.set_save: DB row after insert ->", core.db.query_result)

func has_save() -> bool:
	if core == null or core.db == null:
		return false
	core.db.query("SELECT 1 FROM save_state WHERE id=1 LIMIT 1;")
	return core.db.query_result.size() > 0

func get_save() -> Dictionary:
	if core == null or core.db == null:
		if DEBUG_SAVE:
			print("DbSave.get_save: core or db is null")
		return {}

	# Получаем строку из БД
	core.db.query("SELECT scene_path, data_json FROM save_state WHERE id=1 LIMIT 1;")
	if DEBUG_SAVE:
		print("DbSave.get_save: raw query_result ->", core.db.query_result)

	if core.db.query_result.size() == 0:
		if DEBUG_SAVE:
			print("DbSave.get_save: no rows")
		return {}

	var row = core.db.query_result[0]

	# Извлекаем data_json безопасно
	var json_text: String = "{}"
	if typeof(row) == TYPE_DICTIONARY:
		if row.has("data_json"):
			json_text = str(row.get("data_json", "{}"))
		elif row.has("datajson"):
			json_text = str(row.get("datajson", "{}"))
		else:
			json_text = str(row)
	else:
		json_text = str(row)

	if DEBUG_SAVE:
		print("DbSave.get_save: data_json raw ->", json_text)

	# Определяем версию движка (Godot 4 использует JSON.parse_string)
	var engine_info = Engine.get_version_info()
	var is_godot4 := false
	if engine_info.has("major"):
		is_godot4 = int(engine_info["major"]) >= 4

	var parsed: Dictionary = {}

	# Попытка парсинга для Godot 4 (JSON.parse_string)
	if is_godot4:
		var res4 = JSON.parse_string(json_text)
		# Если вернулся wrapper { "error":..., "result":... }
		if typeof(res4) == TYPE_DICTIONARY and res4.has("error"):
			if res4.get("error", 1) == OK:
				parsed = res4.get("result", {})
				if DEBUG_SAVE:
					print("DbSave.get_save: parsed via JSON.parse_string (wrapper) ->", parsed)
			else:
				if DEBUG_SAVE:
					print("DbSave.get_save: JSON.parse_string returned error ->", res4.get("error"))
		# Или parse_string мог вернуть уже распарсенный словарь напрямую
		elif typeof(res4) == TYPE_DICTIONARY:
			parsed = res4
			if DEBUG_SAVE:
				print("DbSave.get_save: parsed via JSON.parse_string (direct) ->", parsed)

	# Попытка парсинга для Godot 3 (JSON.new().parse) или если Godot4 не дал результата
	if parsed.size() == 0:
		var json_inst = JSON.new()
		var err_code = json_inst.parse(json_text)
		if err_code == OK:
			var data = json_inst.get_data()
			if typeof(data) == TYPE_DICTIONARY:
				parsed = data
				if DEBUG_SAVE:
					print("DbSave.get_save: parsed via JSON.new().parse ->", parsed)
			else:
				if DEBUG_SAVE:
					print("DbSave.get_save: JSON.new().parse returned non-dictionary ->", data)
		else:
			if DEBUG_SAVE:
				print("DbSave.get_save: JSON.new().parse error code ->", err_code)

	# Крайний случай: возможна двойная сериализация (строка внутри строки)
	if parsed.size() == 0:
		var s = json_text.strip_edges()
		if s.begins_with('"') and s.ends_with('"'):
			s = s.substr(1, s.length() - 2)
			s = s.replace('\\"', '"')
			if is_godot4:
				var r4 = JSON.parse_string(s)
				if typeof(r4) == TYPE_DICTIONARY and r4.has("error") and r4.get("error", 1) == OK:
					parsed = r4.get("result", {})
				elif typeof(r4) == TYPE_DICTIONARY:
					parsed = r4
			if parsed.size() == 0:
				var json_inst2 = JSON.new()
				var err2 = json_inst2.parse(s)
				if err2 == OK:
					var d2 = json_inst2.get_data()
					if typeof(d2) == TYPE_DICTIONARY:
						parsed = d2

	if parsed.size() == 0:
		if DEBUG_SAVE:
			print("DbSave.get_save: parsed is empty after all attempts")
		return {
			"scene_path": str(row.get("scene_path", "")),
			"player_pos": Vector2.ZERO,
			"player_hp": null,
			"maniacs": []
		}

	# Нормализуем player_pos
	var player_pos = Vector2.ZERO
	var raw_pos = parsed.get("player_pos", null)
	if raw_pos != null:
		if typeof(raw_pos) == TYPE_ARRAY and raw_pos.size() >= 2:
			player_pos = Vector2(float(raw_pos[0]), float(raw_pos[1]))
		elif typeof(raw_pos) == TYPE_VECTOR2:
			player_pos = raw_pos
		elif typeof(raw_pos) == TYPE_STRING:
			var s2 = raw_pos.strip_edges()
			if s2.begins_with("[") and s2.ends_with("]"):
				s2 = s2.substr(1, s2.length() - 2)
			var parts = s2.split(",")
			if parts.size() >= 2:
				player_pos = Vector2(float(parts[0]), float(parts[1]))

	var out := {
		"scene_path": str(row.get("scene_path", parsed.get("scene_path", ""))),
		"player_pos": player_pos,
		"player_hp": parsed.get("player_hp", null),
		"maniacs": parsed.get("maniacs", [])
	}
	if DEBUG_SAVE:
		print("DbSave.get_save: returning ->", out)
	return out

func clear_save() -> void:
	if core == null or core.db == null:
		if DEBUG_SAVE:
			print("DbSave.clear_save: core or db is null")
		return
	core.db.query("DELETE FROM save_state WHERE id=1;")
	if DEBUG_SAVE:
		print("DbSave.clear_save: deleted save_state row")
