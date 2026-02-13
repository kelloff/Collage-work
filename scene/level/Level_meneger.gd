extends Node2D
class_name LevelManager

@onready var pause_menu = $PauseMenu
@onready var journal = $Journal

@export var clear_existing: bool = true
@export var verbose: bool = true
@export var wait_frames: int = 2

func _unhandled_input(event: InputEvent) -> void:
	var pause_open: bool = pause_menu != null and pause_menu.is_open()
	var journal_open: bool = journal != null and journal.is_open()

	if event.is_action_pressed("pause_menu"):
		if journal_open:
			return
		pause_menu.toggle_menu()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("journal"):
		if pause_open:
			return
		journal.toggle()
		get_viewport().set_input_as_handled()
		return

func _ready() -> void:
	RunStats.start_level()
	call_deferred("_init_links")	

	# Попробуем вызвать загрузку через SaveManager (поддерживаем старые/новые имена)
	var save_singleton = _find_save_singleton()
	if save_singleton != null and save_singleton.has_method("load_game"):
		save_singleton.load_game()
		if verbose:
			print("-------------------------------------")
	else:
		if verbose:
			print("LevelManager: Save singleton not found or has no load_game()")

# --- Поиск singleton SaveManager (поддерживает SaveManager и SaveMeneger) ---
func _find_save_singleton() -> Object:
	if Engine.has_singleton("SaveManager"):
		return Engine.get_singleton("SaveManager")
	if Engine.has_singleton("SaveMeneger"):
		return Engine.get_singleton("SaveMeneger")
	# также попробуем получить через root node (если автoload добавлен как node)
	var root = get_tree().get_root()
	if root.has_node("SaveManager"):
		return root.get_node("SaveManager")
	if root.has_node("SaveMeneger"):
		return root.get_node("SaveMeneger")
	return null

# --- Поиск DB singleton / менеджера базы данных ---
func _find_db_manager() -> Node:
	# 1) Попробуем автолоады с разными именами
	if Engine.has_singleton("DbManager"):
		return Engine.get_singleton("DbManager")
	if Engine.has_singleton("DbMeneger"):
		return Engine.get_singleton("DbMeneger")
	# 2) Попробуем root node по имени
	var root = get_tree().get_root()
	if root.has_node("DbManager"):
		return root.get_node("DbManager")
	if root.has_node("DbMeneger"):
		return root.get_node("DbMeneger")
	# 3) Группа db_managers (если менеджеры добавлены в группу)
	var nodes = get_tree().get_nodes_in_group("db_managers")
	if nodes.size() > 0:
		return nodes[0]
	return null

func _init_links() -> void:
	var db = _find_db_manager()
	if db == null:
		push_error("LevelManager: DbManager/DbMeneger not found.")
		return

	# Очистка существующих связей (рычаги и двери) при необходимости
	if clear_existing:
		if db.has_method("clear_lever_links"):
			if verbose:
				print("LevelManager: clearing existing lever_links...")
			db.clear_lever_links()
		if db.has_method("clear_computer_door_links"):
			if verbose:
				print("LevelManager: clearing existing computer_doors...")
			db.clear_computer_door_links()

	# компьютеры — собираем карту (id -> node)
	var comp_map: Dictionary = {}
	var comps = get_tree().get_nodes_in_group("computers")
	for c in comps:
		var cid_val = null
		# если в скрипте Computer.gd есть @export var computer_id
		if "computer_id" in c:
			cid_val = c.computer_id
		elif c.has_meta("computer_id"):
			cid_val = c.get_meta("computer_id")
		if cid_val != null:
			comp_map[int(cid_val)] = c
	if verbose:
		print("LevelManager: found %d computer(s)." % comps.size())

	# ждём несколько кадров, чтобы сцена полностью инициализировалась
	for i in range(wait_frames):
		await get_tree().process_frame

	# рычаги — существующая логика
	var levers = get_tree().get_nodes_in_group("levers")
	if verbose:
		print("LevelManager: found %d lever(s)." % levers.size())

	for lever in levers:
		if lever.has_method("register_links"):
			lever.register_links()
			continue

		var lid_val = null
		if "lever_id" in lever:
			lid_val = lever.lever_id
		elif lever.has_meta("lever_id"):
			lid_val = lever.get_meta("lever_id")

		var linked_val = null
		if "linked_computers" in lever:
			linked_val = lever.linked_computers
		elif lever.has_meta("linked_computers"):
			linked_val = lever.get_meta("linked_computers")

		if lid_val == null or linked_val == null:
			continue

		var lid = int(lid_val)
		for comp_id in linked_val:
			if typeof(comp_id) == TYPE_INT and comp_id > 0 and db.has_method("link_lever_to_computer"):
				db.link_lever_to_computer(lid, comp_id)

	# Автоматическая привязка компьютеров <-> дверей по полям инспектора
	_auto_link_computers_and_doors(db)

	if verbose:
		print("LevelManager: initialization complete.")
	if db.has_method("debug_dump_all"):
		db.debug_dump_all()

# --- Вспомогательная функция: привязать компьютеры и двери по инспекторным полям ---
func _auto_link_computers_and_doors(db: Node) -> void:
	if db == null:
		return

	var comps = get_tree().get_nodes_in_group("computers")
	for c in comps:
		if not ("computer_id" in c):
			continue
		var cid = int(c.computer_id)

		# Если linked_doors нет — пропускаем
		if not ("linked_doors" in c):
			continue

		# Проходим по элементам массива linked_doors
		for raw in c.linked_doors:
			var did: int = -1

			# 1) Если это число — используем напрямую
			if typeof(raw) == TYPE_INT:
				did = int(raw)

			# 2) Если это строка — попробуем распарсить число
			elif typeof(raw) == TYPE_STRING:
				var s = String(raw).strip_edges()
				if s.is_valid_integer():
					did = int(s)

			# 3) Если это NodePath — пытаемся получить узел и его door_id
			elif typeof(raw) == TYPE_NODE_PATH:
				var np = raw as NodePath
				var node = get_node_or_null(np)
				if node != null and ("door_id" in node):
					did = int(node.door_id)

			# 4) Если это Node (в инспекторе могли перетащить узел) — используем его door_id
			elif typeof(raw) == TYPE_OBJECT and raw is Node:
				var node2 = raw as Node
				if ("door_id" in node2):
					did = int(node2.door_id)

			# 5) Если не получилось — пропускаем
			if did <= 0:
				if verbose:
					print("LevelManager: skipping invalid linked_doors entry:", raw, "for computer", cid)
				continue

			# Наконец, создаём связь в БД
			if db.has_method("link_computer_to_door"):
				db.link_computer_to_door(cid, did)

	if verbose:
		print("LevelManager: auto-linking from computers -> computer_doors complete")
