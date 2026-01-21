extends Node2D

@export var clear_existing: bool = true
@export var verbose: bool = true
@export var wait_frames: int = 2

func _ready() -> void:
	call_deferred("_init_links")

func _find_dbmeneger() -> Node:
	var root = get_tree().get_root()
	var cr = root.get_node_or_null("DbMeneger")
	if cr:
		return cr
	var nodes = get_tree().get_nodes_in_group("db_managers")
	if nodes.size() > 0:
		return nodes[0]
	return null

func _init_links() -> void:
	var db = _find_dbmeneger()
	if db == null:
		push_error("LevelManager: DbMeneger not found.")
		return

	if clear_existing and db.has_method("clear_lever_links"):
		if verbose:
			print("LevelManager: clearing existing lever_links...")
		db.clear_lever_links()

	# компьютеры
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

	for i in range(wait_frames):
		await get_tree().process_frame

	# рычаги
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

	if verbose:
		print("LevelManager: initialization complete.")
	if db.has_method("debug_dump_all"):
		db.debug_dump_all()
