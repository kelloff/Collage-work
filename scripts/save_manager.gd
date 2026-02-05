# res://scripts/SaveManager.gd
extends Node
class_name SaveManager

# Сохраняет текущую сцену, позицию игрока, HP игрока и позиции всех маньяков
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

	# Получаем HP игрока безопасно
	var player_hp = _read_player_hp(player)

	# Позиция игрока
	var player_pos: Vector2 = player.global_position

	# Собираем позиции всех маньяков (узлы в группе "maniac")
	var maniacs_positions: Array = []
	for m in get_tree().get_nodes_in_group("maniac"):
		if m and m is Node2D:
			maniacs_positions.append([m.global_position.x, m.global_position.y])

	# Формируем структуру сохранения
	var save_data := {
		"scene_path": scene_path,
		"player_pos": player_pos,
		"player_hp": player_hp,
		"maniacs": maniacs_positions
	}

	# Сохраняем через DbManager (модуль db_save.gd ожидает словарь)
	DbManager.set_save(save_data)
	print("✅ SAVE OK:", scene_path, player_pos, " hp=", player_hp, " maniacs=", maniacs_positions)


func has_save() -> bool:
	return DbManager.has_save()


# Загружает сохранение: смена сцены, установка позиции игрока, HP и позиций маньяков
func continue_game() -> void:
	# Диагностика: покажем объекты DbManager/DbSave
	print("DBG: DbManager ->", DbManager, " DbManager.db ->", DbManager.db)
	print("DBG: calling DbManager.get_save() now...")
	var data := DbManager.get_save()
	print("DBG: DbManager.get_save() returned ->", data)

	# fallback: прямое чтение из таблицы, если data пустой
	if data == null or typeof(data) != TYPE_DICTIONARY or data.is_empty():
		print("DBG: DbManager.get_save empty, trying direct DB read...")
		if DbManager.db:
			DbManager.db.query("SELECT scene_path, data_json FROM save_state WHERE id=1 LIMIT 1;")
			print("DBG: direct DB query result ->", DbManager.db.query_result)
			if DbManager.db.query_result.size() > 0:
				var row = DbManager.db.query_result[0]
				var scene_path_db = str(row.get("scene_path", ""))
				var json_text = str(row.get("data_json", "{}"))
				var parsed_ok = JSON.parse_string(json_text)
				if parsed_ok.get("error", null) == OK:
					data = parsed_ok.get("result", {})
					print("DBG: parsed direct data ->", data)
				else:
					print("DBG: JSON parse error ->", parsed_ok)
	# дальше — как раньше, но с проверками
	if data == null or typeof(data) != TYPE_DICTIONARY or data.is_empty():
		push_warning("SaveManager: no save data after direct read")
		return


	var scene_path: String = ""
	if data.has("scene_path"):
		scene_path = data["scene_path"]
	elif data.has("scene"):
		scene_path = data["scene"]

	if scene_path == "":
		push_warning("SaveManager: saved data missing scene_path")
		return

	# Нормализуем позицию игрока — поддерживаем Vector2, [x,y], "x,y" и старый ключ pos
	var raw_pos = null
	if data.has("player_pos"):
		raw_pos = data["player_pos"]
	elif data.has("pos"):
		raw_pos = data["pos"]

	var pos: Vector2 = Vector2.ZERO
	if raw_pos != null:
		if typeof(raw_pos) == TYPE_VECTOR2:
			pos = raw_pos
		elif typeof(raw_pos) == TYPE_ARRAY and raw_pos.size() >= 2:
			pos = Vector2(float(raw_pos[0]), float(raw_pos[1]))
		elif typeof(raw_pos) == TYPE_STRING:
			# формат "x,y"
			var parts = raw_pos.split(",")
			if parts.size() >= 2:
				pos = Vector2(float(parts[0]), float(parts[1]))

	var saved_hp = null
	if data.has("player_hp"):
		saved_hp = data["player_hp"]
	elif data.has("hp"):
		saved_hp = data["hp"]

	var maniacs_positions: Array = []
	if data.has("maniacs") and typeof(data["maniacs"]) == TYPE_ARRAY:
		maniacs_positions = data["maniacs"]

	# Логируем то, что собираемся загрузить
	print("SaveManager: loading scene=", scene_path, " pos_raw=", raw_pos, " pos_norm=", pos, " hp=", saved_hp, " maniacs=", maniacs_positions)

	# Меняем сцену
	var err := get_tree().change_scene_to_file(scene_path)
	if err != OK:
		push_error("SaveManager: change_scene_to_file failed: %s" % scene_path)
		return

	# ждём, чтобы сцена и узлы инстансились
	await get_tree().process_frame
	await get_tree().process_frame

	# Восстанавливаем игрока
	var player := get_tree().get_first_node_in_group("player")
	if not player:
		print("SaveManager: player not found after scene load")
	else:
		# Устанавливаем позицию отложенно, чтобы не конфликтовать с _ready() игрока
		player.set_deferred("global_position", pos)
		# Немного логов для отладки: проверим позицию сразу и через кадр
		print("SaveManager: set_deferred global_position ->", pos, " node=", player.get_path())
		await get_tree().process_frame
		print("SaveManager: player.global_position after 1 frame ->", player.global_position)
		await get_tree().process_frame
		print("SaveManager: player.global_position after 2 frames ->", player.global_position)

		# hp
		if saved_hp != null:
			_write_player_hp(player, saved_hp)
			print("SaveManager: player HP set to", saved_hp)

	# Восстанавливаем позиции маньяков: если сохранено N позиций, применяем их к первым N маньякам в сцене
	if maniacs_positions.size() > 0:
		var maniacs := get_tree().get_nodes_in_group("maniac")
		for i in range(min(maniacs_positions.size(), maniacs.size())):
			var m = maniacs[i]
			if m and m is Node2D:
				var p = maniacs_positions[i]
				var mp = Vector2.ZERO
				if typeof(p) == TYPE_VECTOR2:
					mp = p
				elif typeof(p) == TYPE_ARRAY and p.size() >= 2:
					mp = Vector2(float(p[0]), float(p[1]))
				elif typeof(p) == TYPE_STRING:
					var parts = p.split(",")
					if parts.size() >= 2:
						mp = Vector2(float(parts[0]), float(parts[1]))
				# Отложенная установка для маньяков тоже безопаснее
				m.set_deferred("global_position", mp)
				print("SaveManager: set maniac", i, "->", mp, " node=", m.get_path())

	print("✅ LOAD OK:", scene_path, " player_pos=", pos, " player_hp=", saved_hp, " maniacs=", maniacs_positions)


func reset_save() -> void:
	if DbManager.has_method("clear_save"):
		DbManager.clear_save()
	elif DbManager.has_method("reset_all"):
		DbManager.reset_all()
	print("SaveManager: save reset")


# --------------------
# Вспомогательные: чтение/запись HP игрока (совместимость)
# --------------------
func _read_player_hp(player: Node) -> Variant:
	if player == null:
		return null
	if player.has_method("get_hp"):
		return player.call("get_hp")
	if player.has_method("get_health"):
		return player.call("get_health")
	if player.has("hp"):
		return player.get("hp")
	if player.has("health"):
		return player.get("health")
	# Если ничего не найдено — возвращаем null
	return null

func _write_player_hp(player: Node, hp_value: Variant) -> void:
	if player == null or hp_value == null:
		return
	if player.has_method("set_hp"):
		player.call("set_hp", hp_value)
		return
	if player.has_method("set_health"):
		player.call("set_health", hp_value)
		return
	if player.has("hp"):
		player.set("hp", hp_value)
		return
	if player.has("health"):
		player.set("health", hp_value)
		return
	# Если ничего не доступно — запишем в мета, чтобы не потерять значение
	player.set_meta("hp", hp_value)
