extends Control
## Экран загрузки: HTTP /generate_tasks_multi (или 4× /generate_tasks) → wipe БД → вставка задач.

@onready var _status: Label = $BottomRight/VBox/Status
@onready var _error: Label = $ErrorLayer/CenterContainer/VBox/ErrorLabel
@onready var _btn_menu: Button = $ErrorLayer/CenterContainer/VBox/BtnToMenu

var _http: HTTPRequest
const SERVER_TASK_TIMEOUT_S: float = 35.0
const LOCAL_TASKS_PATH := "res://db/task_data.gd"


func _ready() -> void:
	_error.visible = false
	_btn_menu.visible = false
	_btn_menu.pressed.connect(_on_to_menu)
	_run_flow.call_deferred()


func _on_to_menu() -> void:
	get_tree().change_scene_to_file("res://scene/main-menu.tscn")


func _set_status(t: String) -> void:
	if _status:
		_status.text = t


func _http_post_json(url: String, payload: String) -> Dictionary:
	## { "ok": bool, "code": int, "text": String }
	_http = HTTPRequest.new()
	_http.timeout = SERVER_TASK_TIMEOUT_S
	add_child(_http)
	var err := _http.request(
		url,
		PackedStringArray(["Content-Type: application/json"]),
		HTTPClient.METHOD_POST,
		payload
	)
	if err != OK:
		_http.queue_free()
		_http = null
		return {"ok": false, "code": err, "text": ""}
	var result: Array = await _http.request_completed
	_http.queue_free()
	_http = null
	if result.size() < 4:
		return {"ok": false, "code": -1, "text": ""}
	return {"ok": true, "code": int(result[1]), "text": result[3].get_string_from_utf8()}

func _load_local_tasks_into_db() -> bool:
	if DbManager.tasks and DbManager.tasks.has_method("load_default_tasks_from_file"):
		DbManager.tasks.load_default_tasks_from_file(LOCAL_TASKS_PATH)
		return true
	return false


func _parse_tasks_response(text: String, err_ctx: String) -> Array:
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("new_game_loading: %s — не JSON" % err_ctx)
		return []
	var tasks_raw: Variant = parsed.get("tasks", [])
	if typeof(tasks_raw) != TYPE_ARRAY:
		push_error("new_game_loading: %s — нет tasks[]" % err_ctx)
		return []
	return tasks_raw


func _run_flow() -> void:
	var levels: Array = NewGameConfig.GENERATE_LEVELS
	var per_level: int = NewGameConfig.generate_task_count

	_set_status("Запрос заданий у сервера…")
	await get_tree().process_frame

	var tasks_arr: Array = []
	var url_multi := BackendUrls.url("/generate_tasks_multi")
	var payload_multi := JSON.stringify({
		"levels": levels,
		"count_per_level": per_level,
	})

	var r: Dictionary = await _http_post_json(url_multi, payload_multi)
	if r.get("ok", false) and int(r.get("code", 0)) == 200:
		tasks_arr = _parse_tasks_response(str(r.get("text", "")), "/generate_tasks_multi")
	elif int(r.get("code", 0)) == 404:
		tasks_arr = []
	else:
		push_warning("new_game_loading: /generate_tasks_multi failed. fallback to per-level. r=%s" % str(r))
		tasks_arr = []

	if tasks_arr.is_empty():
		_set_status("Батч недоступен, запрос по уровням…")
		await get_tree().process_frame
		var url_one := BackendUrls.url("/generate_tasks")
		var idx := 0
		for lvl in levels:
			idx += 1
			_set_status("Запрос заданий: уровень %s (%d/%d)…" % [str(lvl), idx, levels.size()])
			await get_tree().process_frame
			var payload := JSON.stringify({"level": int(lvl), "count": per_level})
			var rr: Dictionary = await _http_post_json(url_one, payload)
			if not rr.get("ok", false):
				push_warning("new_game_loading: level=%s request failed -> local fallback" % str(lvl))
				tasks_arr.clear()
				break
			if int(rr.get("code", 0)) != 200:
				push_warning("new_game_loading: level=%s non-200=%d -> local fallback" % [str(lvl), int(rr.get("code", 0))])
				tasks_arr.clear()
				break
			var batch: Array = _parse_tasks_response(str(rr.get("text", "")), "/generate_tasks")
			if batch.is_empty():
				push_warning("new_game_loading: level=%s returned 0 tasks -> local fallback" % str(lvl))
				tasks_arr.clear()
				break
			tasks_arr.append_array(batch)

	if tasks_arr.is_empty():
		_set_status("Сервер недоступен, загружаем локальные задания…")
		await get_tree().process_frame

	_set_status("Сброс сохранения и мира…")
	await get_tree().process_frame

	if DbManager.has_method("new_game_database_wipe"):
		DbManager.new_game_database_wipe()

	_set_status("Запись заданий в базу…")
	await get_tree().process_frame

	var inserted: int = 0
	if DbManager.has_method("apply_generated_tasks"):
		inserted = DbManager.apply_generated_tasks(tasks_arr)

	if tasks_arr.is_empty() or inserted <= 0:
		push_warning("new_game_loading: using local tasks fallback")
		if not _load_local_tasks_into_db():
			_fail("Не удалось загрузить ни серверные, ни локальные задания")
			return

	GameState.reset_all()
	RunStats.reset_session()

	_set_status("Готово")
	await get_tree().process_frame

	var next := NewGameConfig.next_level_scene
	if next.is_empty():
		next = NewGameConfig.DEFAULT_LEVEL_SCENE
	get_tree().change_scene_to_file(next)


func _fail(msg: String) -> void:
	push_error("new_game_loading: %s" % msg)
	_set_status("Ошибка")
	if _error:
		_error.text = msg
		_error.visible = true
	if _btn_menu:
		_btn_menu.visible = true
