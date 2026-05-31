extends CanvasLayer

@onready var code_edit = get_node_or_null("PanelContainer/HBoxContainer/CodeEditor")
@onready var run_button = get_node_or_null("PanelContainer/HBoxContainer/VBoxContainer/RunButton")
@onready var close_button = get_node_or_null("PanelContainer/HBoxContainer/VBoxContainer/CloseButton")
@onready var output_label = get_node_or_null("PanelContainer/HBoxContainer/VBoxContainer/OutputScroll/OutputCenter/OutputLabel")
@onready var task_label = get_node_or_null("PanelContainer/HBoxContainer/VBoxContainer/TaskLabel")
@onready var hint_label = get_node_or_null("PanelContainer/HBoxContainer/VBoxContainer/HintLabelSyntax")
@onready var sfx_player: AudioStreamPlayer = get_node_or_null("SfxPlayer")
@onready var panel_root: PanelContainer = get_node_or_null("PanelContainer")

const YES_SFX_PATH := "res://audio/sounds/yes.mp3"
const NO_SFX_PATH := "res://audio/sounds/no.mp3"

var current_task: Dictionary = {}
## Уровень компьютера на карте (для БД), не путать со сложностью задания.
var current_level: int = 1
var current_computer_id: int = 0
var _running := false
var _local_check_pending: bool = false
var _use_ai_checker: bool = true
var _yes_sfx: AudioStream = null
var _no_sfx: AudioStream = null
var _host_parent: Node = null
var _gameplay_frozen_by_terminal: bool = false

const TERM_GREEN := Color(0.45, 1.0, 0.58, 1.0)
const TERM_TEXT := Color(0.95, 0.98, 0.95, 1.0)

func _ready() -> void:
	add_to_group("gameplay_overlay_ui")
	layer = 100
	if panel_root:
		panel_root.theme = Theme.new()
		GameUiTheme.apply_horror_panel(panel_root)
	process_mode = Node.PROCESS_MODE_ALWAYS
	if run_button:
		run_button.pressed.connect(_on_run_button_pressed)
	if close_button:
		close_button.pressed.connect(close)
	if sfx_player == null:
		sfx_player = AudioStreamPlayer.new()
		sfx_player.name = "SfxPlayer"
		add_child(sfx_player)
	if ResourceLoader.exists(YES_SFX_PATH):
		_yes_sfx = load(YES_SFX_PATH)
	if ResourceLoader.exists(NO_SFX_PATH):
		_no_sfx = load(NO_SFX_PATH)
	_apply_readability_scale()
	set_process_unhandled_input(true)

	hide()

func open_with_task(level: int, computer_id: int, task: Dictionary) -> void:
	var tid = task.get("id", -1)
	var desc = task.get("description", "<no desc>")
	print(
		"TerminalUI.open_with_task: level=%d computer=%d id=%s desc=%s"
		% [level, computer_id, str(tid), desc]
	)

	current_task = task
	current_level = level
	current_computer_id = computer_id
	_mount_to_root()
	if not _gameplay_frozen_by_terminal and GameState.has_method("push_gameplay_freeze"):
		GameState.push_gameplay_freeze()
		_gameplay_frozen_by_terminal = true
	show()

	if output_label:
		_set_output("")

	if code_edit:
		code_edit.text = _load_saved_code()

	# Заголовок
	if current_task.has("message"):
		if task_label:
			task_label.text = str(current_task["message"])
		if code_edit and code_edit.text.strip_edges() == "":
			code_edit.text = "# " + str(current_task["message"])
		return

	if task_label:
		task_label.text = "Задание: " + current_task.get("description", "Нет описания")

	# Подсказка по синтаксису (если пусто)
	if code_edit and code_edit.text.strip_edges() == "":
		code_edit.text = """# Подсказки по синтаксису Python:
# ---------------------------------
# Пример:
# age = 20
# print(age)
#
# Решение:
"""

	if hint_label:
		hint_label.text = "Подсказка: print(), переменные, if/for, функции. Файлы/удаление запрещены."


func _load_saved_code() -> String:
	if current_computer_id <= 0:
		return ""
	if DbManager.has_method("get_terminal_code"):
		return DbManager.get_terminal_code(current_level, current_computer_id)
	return ""


func _save_code(code_text: String) -> void:
	if current_computer_id <= 0:
		return
	if DbManager.has_method("set_terminal_code"):
		DbManager.set_terminal_code(current_level, current_computer_id, code_text)


func close() -> void:
	_release_ui_focus()
	set_pause_input_passthrough(false)
	if _gameplay_frozen_by_terminal and GameState.has_method("pop_gameplay_freeze"):
		GameState.pop_gameplay_freeze()
		_gameplay_frozen_by_terminal = false
	hide()
	_restore_parent()
	current_task = {}
	current_computer_id = 0
	_running = false

	if code_edit:
		_save_code(code_edit.text)

	if run_button:
		run_button.text = "Проверить решение"
		run_button.disabled = false
	if output_label:
		_set_output("")
	if task_label:
		task_label.text = ""
	if hint_label:
		hint_label.text = ""

	# Кнопка «Закрыть» вызывает только close(), без Computer.close_terminal() — снимаем блок ввода здесь.
	var host: Node = _host_parent if _host_parent != null else get_parent()
	if host and host.has_method("_terminal_closed_cleanup"):
		host._terminal_closed_cleanup()

func _on_run_button_pressed() -> void:
	if _running:
		_play_result_sfx(false)
		return

	if not code_edit:
		_set_output("❌ Ошибка: CodeEditor не найден")
		_play_result_sfx(false)
		return

	var code_text: String = code_edit.text as String
	if code_text.strip_edges().is_empty():
		_set_output("❌ Код пустой. Напиши решение и нажми «Проверить решение».")
		_play_result_sfx(false)
		return
	if current_task.is_empty():
		_set_output("❌ Нет активного задания для проверки.")
		_play_result_sfx(false)
		return

	if _use_ai_checker:
		_run_with_ai_checker(code_text)
	else:
		_set_output("❌ AI-проверка выключена и CodeRunner не настроен")
		_play_result_sfx(false)

func _task_difficulty() -> int:
	## Сложность задания 0–3 из БД (для /check_task). Не computer.level на сцене.
	if current_task.is_empty():
		return 0
	return int(current_task.get("level", 0))


func _run_with_ai_checker(code_text: String) -> void:
	var diff := _task_difficulty()
	if diff < 2:
		_set_output("Проверка решения…")
		_run_local_check_async(code_text)
		return
	if _prefer_local_check_offline():
		_set_output("Офлайн: проверка на этом компьютере (нужен Python)…")
		_run_local_check_async(code_text)
		return
	_set_output("Проверка на сервере…")
	_run_remote_check_async(code_text)


func _prefer_local_check_offline() -> bool:
	if typeof(BackendUrls) == TYPE_NIL:
		return false
	return not BackendUrls.is_server_likely_online()


func _run_local_check_async(code_text: String) -> void:
	if run_button:
		run_button.disabled = true
	_running = true
	RunStats.begin_task_attempt()

	if not CodeRunner.has_signal("run_finished"):
		_finish_check(_fail_feedback("Локальный запуск кода недоступен"))
		return

	if _local_check_pending:
		_finish_check(_fail_feedback("Подождите, идёт проверка…"))
		return

	_local_check_pending = true
	if not CodeRunner.run_finished.is_connected(_on_local_run_finished):
		CodeRunner.run_finished.connect(_on_local_run_finished)
	CodeRunner.run_code_async(code_text, "terminal_check.py")


func _on_local_run_finished(result: Dictionary) -> void:
	if not _local_check_pending:
		return
	_local_check_pending = false
	if not is_inside_tree() or not visible:
		_running = false
		_local_check_pending = false
		return
	_finish_check(_evaluate_local_check(result))


func _evaluate_local_check(run_result: Dictionary) -> Dictionary:
	var stdout := str(run_result.get("stdout", ""))
	var stderr := str(run_result.get("stderr", ""))
	if bool(run_result.get("timed_out", false)):
		return _fail_feedback("Превышено время выполнения кода.")
	if int(run_result.get("exit_code", -1)) != 0 and stderr.strip_edges() != "":
		var err_line := stderr.strip_edges().split("\n")
		return _fail_feedback("Ошибка выполнения: %s" % err_line[-1])

	var expected := str(current_task.get("expected_output", "")).strip_edges()
	var patterns_raw := str(current_task.get("required_patterns", "")).strip_edges()
	var allow_direct := int(current_task.get("allow_direct_print", 0))
	var code_text: String = code_edit.text if code_edit != null else ""

	if expected != "":
		if _normalize_out(stdout) != _normalize_out(expected):
			return _fail_feedback(
				"Вывод не совпадает с ожидаемым.\nОжидалось: %s\nПолучено: %s"
				% [expected, stdout.strip_edges()]
			)
		if allow_direct == 0 and _looks_like_direct_print(code_text, expected):
			var has_logic := false
			for kw in ["=", "if", "for", "while"]:
				if kw in code_text:
					has_logic = true
					break
			if not has_logic:
				return _fail_feedback(
					"Нельзя просто печатать готовый ответ. Используй переменные, условия или циклы."
				)
	if patterns_raw != "":
		var missing: PackedStringArray = []
		for p in patterns_raw.split(";"):
			p = p.strip_edges()
			if p != "" and p not in code_text:
				missing.append(p)
		if not missing.is_empty():
			return _fail_feedback(
				"В коде не хватает обязательных фрагментов:\n- " + "\n- ".join(missing)
			)

	var ok_msg := "Решение корректное."
	if _task_difficulty() >= 2 and _prefer_local_check_offline():
		ok_msg += "\n(офлайн: без проверки ИИ на сервере)"
	return {
		"success": true,
		"feedback": ok_msg,
		"stdout": stdout,
		"stderr": stderr,
	}


func _normalize_out(text: String) -> String:
	var t := text.replace("\r", "").strip_edges()
	var lines: PackedStringArray = []
	for ln in t.split("\n"):
		lines.append(ln.strip_edges())
	return "\n".join(lines).strip_edges()


func _looks_like_direct_print(user_code: String, expected_output: String) -> bool:
	if "print" not in user_code:
		return false
	var exp := expected_output.strip_edges()
	if exp == "":
		return false
	if ("\"%s\"" % exp) in user_code or ("'%s'" % exp) in user_code:
		return true
	if exp.is_valid_int() and ("print(%s)" % exp) in user_code.replace(" ", ""):
		return true
	return false


func _fail_feedback(msg: String) -> Dictionary:
	return {"success": false, "feedback": msg, "stdout": "", "stderr": ""}


func _run_remote_check_async(code_text: String) -> void:
	if run_button:
		run_button.disabled = true
	_running = true
	RunStats.begin_task_attempt()
	var result: Dictionary = await AiCheckerSingleton.check_task_async(
		current_task, code_text, _task_difficulty()
	)
	if not is_inside_tree() or not visible:
		_running = false
		return
	if AiChecker.is_network_failure(result):
		_running = false
		_local_check_pending = false
		_set_output("Сервер недоступен — проверяем на этом ПК (Python)…")
		await get_tree().process_frame
		_run_local_check_async(code_text)
		return
	_finish_check(result)


func _finish_check(result: Dictionary) -> void:

	if not output_label:
		_running = false
		if run_button:
			run_button.disabled = false
		return

	var success: bool = bool(result.get("success", false))
	var feedback: String = str(result.get("feedback", ""))

	if success:
		RunStats.record_task_success()
		_set_output("Задание выполнено!\n" + feedback)
		_play_result_sfx(true)
		var computer = _host_parent if _host_parent != null else get_parent()
		if computer and computer.has_method("unassign_task_if_completed"):
			computer.unassign_task_if_completed()
	else:
		RunStats.record_task_failure()
		_set_output(feedback)
		_play_result_sfx(false)

	_running = false
	if run_button:
		run_button.disabled = false

func _play_result_sfx(success: bool) -> void:
	if sfx_player == null:
		return
	var stream: AudioStream = _yes_sfx if success else _no_sfx
	if stream == null:
		return
	sfx_player.stream = stream
	sfx_player.play()

func _apply_readability_scale() -> void:
	if code_edit:
		code_edit.add_theme_font_size_override("font_size", 22)
		code_edit.add_theme_color_override("font_color", TERM_GREEN)
		code_edit.add_theme_color_override("font_readonly_color", TERM_GREEN)
		code_edit.add_theme_color_override("background_color", Color(0.02, 0.05, 0.02, 1.0))
		code_edit.add_theme_color_override("current_line_color", Color(0.08, 0.14, 0.08, 1.0))
	if task_label:
		task_label.add_theme_font_size_override("font_size", 22)
		task_label.add_theme_color_override("font_color", TERM_TEXT)
	if hint_label:
		hint_label.add_theme_font_size_override("font_size", 18)
		hint_label.add_theme_color_override("font_color", TERM_GREEN)
	if run_button:
		run_button.add_theme_font_size_override("font_size", 22)
		run_button.add_theme_color_override("font_color", TERM_TEXT)
	if output_label:
		output_label.modulate = Color(1, 1, 1, 1)
		output_label.bbcode_enabled = true
		output_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		output_label.scroll_active = false
		output_label.fit_content = true
		output_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		output_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		output_label.add_theme_font_size_override("normal_font_size", 30)
		output_label.add_theme_color_override("default_color", TERM_GREEN)
	if close_button:
		close_button.add_theme_font_size_override("font_size", 22)
		close_button.add_theme_color_override("font_color", TERM_TEXT)

func _set_output(text: String) -> void:
	if output_label == null:
		return
	output_label.text = text
	output_label.queue_redraw()

func _mount_to_root() -> void:
	var root := get_tree().root
	if get_parent() == root:
		return
	if _host_parent == null or not is_instance_valid(_host_parent):
		_host_parent = get_parent()
	var parent := get_parent()
	if parent:
		parent.remove_child(self)
	root.add_child(self)

func _restore_parent() -> void:
	if _host_parent == null or not is_instance_valid(_host_parent):
		return
	if get_parent() == _host_parent:
		return
	var parent := get_parent()
	if parent:
		parent.remove_child(self)
	_host_parent.add_child(self)

func _release_ui_focus() -> void:
	if code_edit:
		code_edit.release_focus()
	var vp := get_viewport()
	if vp:
		vp.gui_release_focus()


func set_pause_input_passthrough(enabled: bool) -> void:
	if not visible:
		return
	if panel_root:
		panel_root.mouse_filter = (
			Control.MOUSE_FILTER_IGNORE if enabled else Control.MOUSE_FILTER_STOP
		)
	if enabled:
		_release_ui_focus()


func _unhandled_input(event: InputEvent) -> void:
	# Allow pause menu while terminal is focused/open.
	if not visible:
		return
	if event.is_action_pressed("pause_menu"):
		_release_ui_focus()
		set_pause_input_passthrough(true)
		var root: Node = get_tree().current_scene
		if root:
			var pause_menu: Node = root.find_child("PauseMenu", true, false)
			if pause_menu and pause_menu.has_method("toggle_menu"):
				pause_menu.toggle_menu()
				get_viewport().set_input_as_handled()
