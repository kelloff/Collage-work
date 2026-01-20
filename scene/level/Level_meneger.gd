extends Node

@export var clear_existing: bool = true
@export var verbose: bool = true

func _ready() -> void:
	call_deferred("_init_links")

func _init_links() -> void:
	if typeof(DbMeneger) == TYPE_NIL:
		push_error("DbMeneger not found. Add DbMeneger as Autoload or node before LevelManager.")
		return

	if clear_existing:
		if verbose:
			print("LevelManager: clearing existing lever_links...")
		DbMeneger.clear_lever_links()

	var comp_map = {}
	var comps = get_tree().get_nodes_in_group("computers")
	for c in comps:
		var cid_val = c.get("computer_id")
		if cid_val != null:
			var cid = int(cid_val)
			comp_map[cid] = c
	if verbose:
		print("LevelManager: found %d computer(s) in group 'computers'." % comps.size())

	await get_tree().process_frame

	var levers = get_tree().get_nodes_in_group("levers")
	if verbose:
		print("LevelManager: found %d lever(s) in group 'levers'." % levers.size())

	for lever in levers:
		if lever.has_method("register_links"):
			if verbose:
				print("LevelManager: calling register_links on %s" % lever.name)
			lever.register_links()
			continue

		var lid_val = lever.get("lever_id")
		var linked_val = lever.get("linked_computers")
		if lid_val == null or linked_val == null:
			continue

		var lid = int(lid_val)
		for comp_id in linked_val:
			if typeof(comp_id) == TYPE_INT and comp_id > 0:
				DbMeneger.link_lever_to_computer(lid, comp_id)
				if verbose:
					print("LevelManager: linked lever %d -> computer %d" % [lid, comp_id])

	if verbose:
		print("LevelManager: initialization complete.")
	DbMeneger.debug_dump_all()
