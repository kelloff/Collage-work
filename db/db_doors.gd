# res://db/db_doors.gd
extends Node
class_name DbDoors

var dbm: Node = null

func init(db_manager: Node) -> void:
	dbm = db_manager
	if dbm and dbm._ensure_db():
		_create_tables()

func _create_tables() -> void:
	var db = dbm.db
	db.query("""
		CREATE TABLE IF NOT EXISTS computer_doors (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			computer_id INTEGER,
			door_id INTEGER
		)
	""")
	db.query("""
		CREATE TABLE IF NOT EXISTS door_states (
			door_id INTEGER PRIMARY KEY,
			is_open INTEGER
		)
	""")
	print("DbDoors: tables ensured")

func link_computer_to_door(computer_id: int, door_id: int) -> void:
	# игнорируем «пустые» объекты
	if computer_id <= 0 or door_id <= 0:
		return
	if not dbm._ensure_db():
		return
	var db = dbm.db
	db.query("SELECT * FROM computer_doors WHERE computer_id = %d AND door_id = %d" % [computer_id, door_id])
	if db.query_result.size() == 0:
		db.insert_row("computer_doors", {"computer_id": computer_id, "door_id": door_id})
		print("DbDoors: linked computer %d -> door %d" % [computer_id, door_id])

func get_doors_for_computer(computer_id: int) -> Array:
	if computer_id <= 0:
		return []
	if not dbm._ensure_db():
		return []
	var db = dbm.db
	db.query("SELECT door_id FROM computer_doors WHERE computer_id = %d" % computer_id)
	var doors: Array = []
	for row in db.query_result:
		doors.append(int(row["door_id"]))
	return doors

func is_door_accessible(door_id: int) -> bool:
	# пустая дверь всегда доступна (визуально работает, но не участвует в логике)
	if door_id <= 0:
		return true
	if not dbm._ensure_db():
		return false
	var db = dbm.db

	# 1. Проверяем связи рычаг -> дверь
	db.query("SELECT lever_id FROM lever_doors WHERE door_id = %d" % door_id)
	if db.query_result.size() > 0:
		for row in db.query_result:
			var lid = int(row["lever_id"])
			db.query("SELECT is_down FROM lever_states WHERE lever_id = %d" % lid)
			if db.query_result.size() == 0:
				# если нет состояния — считаем дверь заблокированной
				return false
			var is_down = int(db.query_result[0]["is_down"])
			if is_down == 0:
				# рычаг поднят → дверь заблокирована
				return false
		# все связанные рычаги опущены → дверь доступна
		return true

	# 2. Если нет связей рычагов — проверяем связи компьютер -> дверь
	db.query("SELECT computer_id FROM computer_doors WHERE door_id = %d" % door_id)
	if db.query_result.size() == 0:
		# дверь не привязана ни к чему → доступна по умолчанию
		return true
	for row in db.query_result:
		var cid = int(row["computer_id"])
		if cid <= 0:
			continue
		db.query("SELECT status FROM progress WHERE computer_id = %d AND status = 'done'" % cid)
		if db.query_result.size() > 0:
			# хотя бы один связанный компьютер завершён → дверь доступна
			return true

	# ни один связанный компьютер не завершён → дверь заблокирована
	return false


# ---------- Persistent open/close state ----------

func set_door_state(door_id: int, opened: bool) -> void:
	if door_id <= 0:
		# "пустые" двери не пишем в БД
		return
	if not dbm._ensure_db():
		return
	var db = dbm.db
	var opened_i := 1 if opened else 0
	db.query("INSERT OR REPLACE INTO door_states (door_id, is_open) VALUES (%d, %d)" % [door_id, opened_i])


func get_door_state(door_id: int) -> Variant:
	if door_id <= 0:
		return null
	if not dbm._ensure_db():
		return null
	var db = dbm.db
	db.query("SELECT is_open FROM door_states WHERE door_id = %d" % door_id)
	if db.query_result.size() == 0:
		return null
	return int(db.query_result[0]["is_open"])
