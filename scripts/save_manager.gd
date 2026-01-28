extends Node

const SAVE_FILE := "user://player_pos.json"


func _enter_tree() -> void:
	print(">>> SaveMeneger _enter_tree called; script path:", get_script().resource_path, " node name:", name)

func _ready() -> void:
	print(">>> SaveMeneger _ready called; script path:", get_script().resource_path, " node name:", name)
func save_game() -> void:
	print("SaveMeneger: вызвано сохранение")
	var player = get_tree().get_first_node_in_group("player")
	if player:
		var data = { "player_pos": player.global_position }
		var file = FileAccess.open(SAVE_FILE, FileAccess.WRITE)
		file.store_string(JSON.stringify(data))
		file.close()
		print("✅ Позиция игрока сохранена:", data["player_pos"])
	else:
		print("❌ Игрок не найден")

func load_game() -> void:
	print("SaveMeneger: вызвана загрузка")
	if not FileAccess.file_exists(SAVE_FILE):
		print("❌ Файл сохранения не найден")
		return

	var file = FileAccess.open(SAVE_FILE, FileAccess.READ)
	var content = file.get_as_text()
	file.close()

	var data = JSON.parse_string(content)
	if typeof(data) == TYPE_DICTIONARY and data.has("player_pos"):
		var player = get_tree().get_first_node_in_group("player")
		if player:
			player.global_position = data["player_pos"]
			print("✅ Позиция игрока загружена:", data["player_pos"])
