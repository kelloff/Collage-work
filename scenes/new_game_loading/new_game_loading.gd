extends Control
## Экран загрузки: HTTP /generate_tasks_multi (или 4× /generate_tasks) → wipe БД → вставка задач.

@onready var _status: Label = $BottomRight/VBox/Status
@onready var _tip_prefix: Label = $BottomTips/VBox/TipPrefix
@onready var _tip_label: Label = $BottomTips/VBox/TipLabel
@onready var _game_title: Label = $CenterTitle/GameTitle
@onready var _subtitle: Label = $CenterTitle/Subtitle
@onready var _error: Label = $ErrorLayer/CenterContainer/VBox/ErrorLabel
@onready var _btn_menu: Button = $ErrorLayer/CenterContainer/VBox/BtnToMenu

var _http: HTTPRequest
var _tip_timer: Timer
var _tip_index: int = 0
var _tip_tween: Tween

## Пул на сервере — секунды; при пустом пуле ответ fallback обычно < 5 с.
const SERVER_TASK_TIMEOUT_S: float = 120.0
const LOCAL_TASKS_PATH := "res://db/task_data.gd"
const TIP_ROTATE_SEC: float = 5.5

const LOADING_TIPS: PackedStringArray = [
	"«Новая игра» берёт задания с сервера (пул kellofff.me); при сбое — локальный запас.",
	"В терминале пиши код на Python: print(), переменные, if и циклы пригодятся сразу.",
	"Если застрял — открой журнал (B): вкладки «Руководство» и «Python: база», записки на уровне.",
	"Маньяк слышит шум: беги тихо, когда нужно спрятаться.",
	"Баффы в коридорах дают скорость, невидимость или лечение — не проходи мимо.",
	"Уровни 0–1: проверка на твоём ПК. Уровни 2–3: проверка на сервере — решения в записках note_03.",
	"Сохраняйся у компьютера, когда нашёл безопасное место.",
	"Инвентарь ограничен — бери только то, что реально пригодится.",
	"Рычаги и двери часто связаны: ищи, что открылось после действия.",
	"Совет по коду: сначала набросай решение на бумаге, потом переноси в терминал.",
]


func _ready() -> void:
	_error.visible = false
	_btn_menu.visible = false
	_btn_menu.pressed.connect(_on_to_menu)
	_style_ui()
	_start_loading_tips()
	_run_flow.call_deferred()


func _exit_tree() -> void:
	if _tip_timer and is_instance_valid(_tip_timer):
		_tip_timer.stop()
	if _tip_tween and _tip_tween.is_valid():
		_tip_tween.kill()


func _style_ui() -> void:
	if _game_title:
		_game_title.label_settings = GameUiTheme.make_title_settings(34)
	if _subtitle:
		_subtitle.label_settings = _make_loading_body_settings(17, GameUiTheme.C_TEXT_DIM)
	if _tip_prefix:
		_tip_prefix.label_settings = GameUiTheme.make_subtitle_settings(15, GameUiTheme.C_TITLE)
	if _tip_label:
		_tip_label.label_settings = _make_loading_body_settings(16, GameUiTheme.C_TEXT)
	if _status:
		_status.label_settings = _make_loading_body_settings(15, GameUiTheme.C_TEXT)
	if _error:
		_error.add_theme_color_override("font_color", GameUiTheme.C_DANGER)
		_apply_loading_font(_error, 17)
	if _btn_menu:
		_btn_menu.custom_minimum_size = Vector2(220, 48)


func _make_loading_body_settings(size: int, color: Color) -> LabelSettings:
	## Читаемый текст без жирной обводки (советы, подзаголовок).
	var ls := LabelSettings.new()
	if ResourceLoader.exists(GameUiTheme.FONT_BODY):
		var ff: FontFile = load(GameUiTheme.FONT_BODY)
		ff.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		ff.hinting = TextServer.HINTING_LIGHT
		ls.font = ff
	ls.font_size = size
	ls.font_color = color
	ls.shadow_size = 4
	ls.shadow_color = Color(0.0, 0.0, 0.0, 0.65)
	ls.shadow_offset = Vector2(1, 2)
	return ls


func _apply_loading_font(label: Label, size: int) -> void:
	if label == null:
		return
	if ResourceLoader.exists(GameUiTheme.FONT_BODY):
		label.add_theme_font_override("font", load(GameUiTheme.FONT_BODY))
	label.add_theme_font_size_override("font_size", size)


func _start_loading_tips() -> void:
	if LOADING_TIPS.is_empty() or _tip_label == null:
		return
	_tip_index = randi() % LOADING_TIPS.size()
	_tip_label.text = LOADING_TIPS[_tip_index]
	_tip_label.modulate.a = 1.0
	_tip_timer = Timer.new()
	_tip_timer.wait_time = TIP_ROTATE_SEC
	_tip_timer.autostart = true
	_tip_timer.timeout.connect(_rotate_loading_tip)
	add_child(_tip_timer)


func _rotate_loading_tip() -> void:
	if _tip_label == null or LOADING_TIPS.is_empty():
		return
	if _tip_tween and _tip_tween.is_valid():
		_tip_tween.kill()
	_tip_tween = create_tween()
	_tip_tween.tween_property(_tip_label, "modulate:a", 0.0, 0.35)
	_tip_tween.tween_callback(_apply_next_tip)
	_tip_tween.tween_property(_tip_label, "modulate:a", 1.0, 0.45)


func _apply_next_tip() -> void:
	_tip_index = (_tip_index + 1) % LOADING_TIPS.size()
	if randf() < 0.25:
		_tip_index = randi() % LOADING_TIPS.size()
	_tip_label.text = LOADING_TIPS[_tip_index]


func _on_to_menu() -> void:
	if typeof(TutorialManager) != TYPE_NIL and TutorialManager.has_method("prepare_exit_to_main_menu"):
		TutorialManager.prepare_exit_to_main_menu()
	get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")


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


func _parse_tasks_response(text: String, err_ctx: String) -> Dictionary:
	## { "tasks": Array, "source": String }
	var empty := {"tasks": [], "source": ""}
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("new_game_loading: %s — не JSON" % err_ctx)
		return empty
	var source: String = str(parsed.get("source", ""))
	var tasks_raw: Variant = parsed.get("tasks", [])
	if typeof(tasks_raw) != TYPE_ARRAY:
		push_error("new_game_loading: %s — нет tasks[]" % err_ctx)
		return empty
	return {"tasks": tasks_raw, "source": source}


func _run_flow() -> void:
	if NewGameConfig.use_local_tasks_only:
		await _run_flow_local_only()
		return

	var levels: Array = NewGameConfig.GENERATE_LEVELS
	var per_level: int = NewGameConfig.generate_task_count

	_set_status("Запрос заданий у сервера…")
	await get_tree().process_frame

	var tasks_arr: Array = []
	var task_source: String = ""
	var url_multi := BackendUrls.url("/generate_tasks_multi")
	var payload_multi := JSON.stringify({
		"levels": levels,
		"count_per_level": per_level,
	})

	for attempt in range(2):
		if attempt > 0:
			_set_status("Повтор запроса заданий…")
			await get_tree().process_frame

		var r: Dictionary = await _http_post_json(url_multi, payload_multi)
		if r.get("ok", false) and int(r.get("code", 0)) == 200:
			var parsed: Dictionary = _parse_tasks_response(str(r.get("text", "")), "/generate_tasks_multi")
			tasks_arr = parsed.get("tasks", [])
			task_source = str(parsed.get("source", ""))
			if not tasks_arr.is_empty():
				print("new_game_loading: tasks from server source=", task_source, " count=", tasks_arr.size())
				var src_hint := task_source
				if src_hint.is_empty():
					src_hint = "server"
				_set_status("Задания с сервера (%s), %d шт.…" % [src_hint, tasks_arr.size()])
				await get_tree().process_frame
				break
		elif int(r.get("code", 0)) == 503:
			push_warning("new_game_loading: server 503 (pool/LLM busy), attempt=%d" % attempt)
		elif int(r.get("code", 0)) == 404:
			break
		else:
			push_warning("new_game_loading: /generate_tasks_multi failed. r=%s" % str(r))

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
			var code := int(rr.get("code", 0))
			if code == 503:
				push_warning("new_game_loading: level=%s 503 -> local fallback" % str(lvl))
				tasks_arr.clear()
				break
			if code != 200:
				push_warning("new_game_loading: level=%s non-200=%d -> local fallback" % [str(lvl), code])
				tasks_arr.clear()
				break
			var batch_parsed: Dictionary = _parse_tasks_response(str(rr.get("text", "")), "/generate_tasks")
			var batch: Array = batch_parsed.get("tasks", [])
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


func _run_flow_local_only() -> void:
	_set_status("Локальные задания (тест, без сервера)…")
	await get_tree().process_frame
	print("new_game_loading: use_local_tasks_only — ", LOCAL_TASKS_PATH)

	_set_status("Сброс сохранения и мира…")
	await get_tree().process_frame

	if DbManager.has_method("new_game_database_wipe"):
		DbManager.new_game_database_wipe()

	_set_status("Загрузка task_data.gd…")
	await get_tree().process_frame

	if not _load_local_tasks_into_db():
		_fail("Не удалось загрузить %s" % LOCAL_TASKS_PATH)
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
