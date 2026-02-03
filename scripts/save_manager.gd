# res://scripts/save_manager.gd
extends Node
class_name SaveManager

func save_now() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		push_warning("SaveManager: player not found in group 'player'")
		return

	var scene := get_tree().current_scene
	if scene == null:
		push_warning("SaveManager: current_scene is null")
		return

	var scene_path := scene.scene_file_path
	if scene_path == "":
		push_warning("SaveManager: scene_file_path is empty (scene not saved as .tscn?)")
		return

	DbMeneger.set_save(scene_path, player.global_position)
	print("✅ SAVE OK:", scene_path, player.global_position)

func has_save() -> bool:
	return DbMeneger.has_save()

func continue_game() -> void:
	var data := DbMeneger.get_save()
	if data.is_empty():
		push_warning("SaveManager: no save data")
		return

	var scene_path: String = data["scene_path"]
	var pos: Vector2 = data["pos"]

	var err := get_tree().change_scene_to_file(scene_path)
	if err != OK:
		push_error("SaveManager: change_scene_to_file failed: %s" % scene_path)
		return

	# ждём пока сцена реально появится и игрок инстанснется
	await get_tree().process_frame
	await get_tree().process_frame

	var player := get_tree().get_first_node_in_group("player")
	if player:
		player.global_position = pos
		
func reset_save() -> void:
	if DbMeneger.has_method("reset_all"):
		DbMeneger.reset_all()
	print("SaveManager: save reset")
