extends CanvasLayer

@onready var code_edit = get_node_or_null("PanelContainer/HBoxContainer/CodeEditor")
@onready var run_button = get_node_or_null("PanelContainer/HBoxContainer/VBoxContainer/RunButton")
@onready var close_button = get_node_or_null("PanelContainer/HBoxContainer/VBoxContainer/CloseButton")
@onready var output_label = get_node_or_null("PanelContainer/HBoxContainer/VBoxContainer/OutputScroll/OutputLabel")
@onready var task_label = get_node_or_null("PanelContainer/HBoxContainer/VBoxContainer/TaskLabel")
@onready var hint_label = get_node_or_null("PanelContainer/HBoxContainer/VBoxContainer/HintLabelSyntax")

const SAVE_PATH := "user://terminal_last_code.txt"

var current_task: Dictionary = {}
var _running := false

func _ready() -> void:
	if run_button:
		run_button.pressed.connect(_on_run_button_pressed)
	if close_button:
		close_button.pressed.connect(close)

	# Подключаемся к CodeRunner один раз
	var cr = get_tree().get_root().get_node_or_null("CodeRunner")
	if cr and cr.has_signal("run_finished"):
		if not cr.is_connected("run_finished", Callable(self, "_on_run_finished")):
			cr.connect("run_finished", Callable(self, "_on_run_finished"))

	hide()

func open_with_task(level: int, task: Dictionary) -> void:
	var tid = task.get("id", -1)
	var desc = task.get("description", "<no desc>")
	print("TerminalUI.open_with_task: level=%d id=%s desc=%s" % [level, str(tid), desc])

	current_task = task
	show()

	if output_label:
		output_label.text = ""

	# Восстановим последний код (если редактор пустой)
	if code_edit and code_edit.text.strip_edges() == "" and FileAccess.file_exists(SAVE_PATH):
		var f = FileAccess.open(SAVE_PATH, FileAccess.READ)
		if f:
			code_edit.text = f.get_as_text()
			f.close()

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

func close() -> void:
	hide()
	current_task = {}
	_running = false

	# Сохраняем код на будущее
	if code_edit:
		var f = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		if f:
			f.store_string(code_edit.text)
			f.close()

	if run_button:
		run_button.disabled = false
	if output_label:
		output_label.text = ""
	if task_label:
		task_label.text = ""
	if hint_label:
		hint_label.text = ""

func _on_run_button_pressed() -> void:
	if _running:
		return

	if not code_edit:
		if output_label:
			output_label.text = "❌ Ошибка: CodeEditor не найден"
		return

	var code_text: String = code_edit.text as String

	if output_label:
		output_label.text = "⏳ Запуск..."
	if run_button:
		run_button.disabled = true

	_running = true

	var cr = get_tree().get_root().get_node_or_null("CodeRunner")
	if cr == null:
		_running = false
		if run_button:
			run_button.disabled = false
		if output_label:
			output_label.text = "❌ Ошибка: CodeRunner не найден"
		return

	# ВАЖНО: просим CodeRunner запускать в "песочнице" (tmp_dir)
	# Код-раннер сам добавит защиту от файлов (см. патч ниже)
	cr.run_code_async(code_text, "user_code.py")

func _on_run_finished(result: Dictionary) -> void:
	_running = false
	if run_button:
		run_button.disabled = false

	if not output_label:
		return

	var stdout := str(result.get("stdout", "")).replace("\r", "")
	var stderr := str(result.get("stderr", "")).replace("\r", "")
	var exit_code := int(result.get("exit_code", -1))
	var tmp_path := str(result.get("tmp_path", ""))
	var timed_out := bool(result.get("timed_out", false))

	var text := ""

	if timed_out:
		text += "⏱ Таймаут: код выполнялся слишком долго\n\n"
	if stdout.strip_edges() != "":
		text += "✅ STDOUT:\n" + stdout.strip_edges() + "\n\n"
	if stderr.strip_edges() != "":
		text += "⚠️ STDERR:\n" + stderr.strip_edges() + "\n\n"

	text += "exit=" + str(exit_code) + "\n"
	text += "tmp_path: " + tmp_path

	output_label.text = text

	# task_checker
	if ResourceLoader.exists("res://db/task_checker.gd"):
		var checker = preload("res://db/task_checker.gd").new()
		var success = checker.check_user_solution(code_edit.text, current_task, stdout, output_label)
		if success:
			output_label.text = "🎉 Задание выполнено!\n\n" + output_label.text
			var computer = get_parent()
			if computer and computer.has_method("unassign_task_if_completed"):
				computer.unassign_task_if_completed()
