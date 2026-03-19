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
var _use_ai_checker: bool = true

func _ready() -> void:
	if run_button:
		run_button.pressed.connect(_on_run_button_pressed)
	if close_button:
		close_button.pressed.connect(close)

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

	if _use_ai_checker:
		_run_with_ai_checker(code_text)
	else:
		if output_label:
			output_label.text = "❌ AI-проверка выключена и CodeRunner не настроен"

func _run_with_ai_checker(code_text: String) -> void:
	if output_label:
		output_label.text = "🤖 Проверка решения ИИ..."
	if run_button:
		run_button.disabled = true
	_running = true

	_run_with_ai_checker_async(code_text)

func _run_with_ai_checker_async(code_text: String) -> void:
	var result: Dictionary = await AiCheckerSingleton.check_task_async(current_task, code_text)

	_running = false
	if run_button:
		run_button.disabled = false

	if not output_label:
		return

	var success: bool = bool(result.get("success", false))
	var feedback: String = str(result.get("feedback", ""))

	if success:
		output_label.text = "🎉 Задание выполнено!\n" + feedback
		var computer = get_parent()
		if computer and computer.has_method("unassign_task_if_completed"):
			computer.unassign_task_if_completed()
	else:
		output_label.text = feedback
