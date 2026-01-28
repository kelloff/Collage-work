extends Node
class_name DbLevers

var dbm: Node = null

func init(db_manager: Node) -> void:
	dbm = db_manager
	if dbm and dbm._ensure_db():
		_create_tables()

func _create_tables() -> void:
	var db = dbm.db
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
	db.query("""
		CREATE TABLE IF NOT EXISTS lever_doors (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			lever_id INTEGER,
			door_id INTEGER
		)
	""")
	print("DbLevers: tables ensured")

# --- links: lever <-> computer ---
func link_lever_to_computer(lever_id: int, computer_id: int) -> void:
	if lever_id <= 0 or computer_id <= 0:
		# игнорируем «пустые» объекты
		return
	if not dbm._ensure_db():
		return
	var db = dbm.db
	db.query("SELECT * FROM lever_links WHERE lever_id = %d AND computer_id = %d" % [lever_id, computer_id])
	if db.query_result.size() == 0:
		db.insert_row("lever_links", {"lever_id": lever_id, "computer_id": computer_id})
		print("DbLevers: linked lever %d -> computer %d" % [lever_id, computer_id])

# --- links: lever <-> door ---
func link_lever_to_door(lever_id: int, door_id: int) -> void:
	if lever_id <= 0 or door_id <= 0:
		# игнорируем «пустые» объекты
		return
	if not dbm._ensure_db():
		return
	var db = dbm.db
	db.query("SELECT * FROM lever_doors WHERE lever_id = %d AND door_id = %d" % [lever_id, door_id])
	if db.query_result.size() == 0:
		db.insert_row("lever_doors", {"lever_id": lever_id, "door_id": door_id})
		print("DbLevers: linked lever %d -> door %d" % [lever_id, door_id])

# --- state ---
func set_lever_state(lever_id: int, is_down: bool) -> void:
	if lever_id <= 0:
		# игнорируем «пустые» рычаги
		return
	if not dbm._ensure_db():
		return
	var db = dbm.db
	db.query("INSERT OR REPLACE INTO lever_states (lever_id, is_down) VALUES (%d, %d)" % [lever_id, (1 if is_down else 0)])
	print("DbLevers: set_lever_state lever=%d is_down=%d" % [lever_id, (1 if is_down else 0)])

func get_lever_state(lever_id: int) -> Variant:
	if lever_id <= 0:
		# для «пустых» рычагов возвращаем null
		return null
	if not dbm._ensure_db():
		return null
	var db = dbm.db
	db.query("SELECT is_down FROM lever_states WHERE lever_id = %d" % lever_id)
	if db.query_result.size() == 0:
		return null
	return int(db.query_result[0]["is_down"])

# --- helpers for debugging / queries ---
func get_doors_for_lever(lever_id: int) -> Array:
	if lever_id <= 0:
		return []
	if not dbm._ensure_db():
		return []
	var db = dbm.db
	db.query("SELECT door_id FROM lever_doors WHERE lever_id = %d" % lever_id)
	var out: Array = []
	for row in db.query_result:
		out.append(int(row["door_id"]))
	return out

func get_levers_for_door(door_id: int) -> Array:
	if door_id <= 0:
		return []
	if not dbm._ensure_db():
		return []
	var db = dbm.db
	db.query("SELECT lever_id FROM lever_doors WHERE door_id = %d" % door_id)
	var out: Array = []
	for row in db.query_result:
		out.append(int(row["lever_id"]))
	return out

# --- access check used by Computer.gd ---
func is_computer_accessible(computer_id: int) -> bool:
	if computer_id <= 0:
		# «пустой» компьютер всегда доступен
		return true
	if not dbm._ensure_db():
		return false
	var db = dbm.db
	db.query("SELECT lever_id FROM lever_links WHERE computer_id = %d" % computer_id)
	var rows = db.query_result
	if rows.size() == 0:
		# нет связанных рычагов — доступ открыт
		return true
	for row in rows:
		var lever_id = int(row["lever_id"])
		db.query("SELECT is_down FROM lever_states WHERE lever_id = %d" % lever_id)
		if db.query_result.size() == 0:
			print("DbLevers: is_computer_accessible -> lever", lever_id, "has no state -> denying")
			return false
		var is_down = int(db.query_result[0]["is_down"])
		if is_down == 0:
			print("DbLevers: is_computer_accessible -> lever", lever_id, "is UP -> denying")
			return false
	# все связанные рычаги опущены -> доступ разрешён
	return true
