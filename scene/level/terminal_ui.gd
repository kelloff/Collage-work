extends CanvasLayer

@onready var code_edit = get_node_or_null("PanelContainer/HBoxContainer/CodeEditor")
@onready var run_button = get_node_or_null("PanelContainer/HBoxContainer/VBoxContainer/RunButton")
@onready var output_label = get_node_or_null("PanelContainer/HBoxContainer/VBoxContainer/OutputScroll/OutputLabel")
@onready var task_label = get_node_or_null("PanelContainer/HBoxContainer/VBoxContainer/TaskLabel")

var current_task: Dictionary = {}

func _ready() -> void:
	if run_button:
		run_button.pressed.connect(_on_run_button_pressed)

	# Надёжно ищем Autoload CodeRunner в корне (/root/CodeRunner)
	var root = get_tree().get_root()
	var cr = root.get_node_or_null("CodeRunner")
	if cr and cr.has_signal("run_finished"):
		cr.connect("run_finished", Callable(self, "_on_run_finished"))

	hide()

func open_with_task(level: int, task: Dictionary) -> void:
	# Короткий лог — не печатаем весь словарь
	var tid = task.get("id", -1)
	var desc = task.get("description", "<no desc>")
	print("TerminalUI.open_with_task: level=%d id=%s desc=%s" % [level, str(tid), desc])

	current_task = task
	show()

	if output_label:
		output_label.text = ""

	if current_task.has("message"):
		if task_label:
			task_label.text = current_task["message"]
		if code_edit:
			code_edit.text = "# " + current_task["message"]
		return

	if task_label:
		task_label.text = "Задание: " + current_task.get("description", "Нет описания")

	if code_edit and code_edit.text.strip_edges() == "":
		code_edit.text = """# Подсказки по синтаксису Python:
# ---------------------------------
# Пример:
# age = 20
# print(age)
#
# Решение:
"""

func close() -> void:
	hide()
	current_task = {}
	if code_edit:
		code_edit.text = ""
	if output_label:
		output_label.text = ""
	if task_label:
		task_label.text = ""

func _on_run_button_pressed() -> void:
	if not code_edit:
		if output_label:
			output_label.text = "❌ Ошибка: CodeEditor не найден"
		return

	var code_text = code_edit.text
	if output_label:
		output_label.text = "⏳ Запуск..."

	# Получаем CodeRunner из /root
	var root = get_tree().get_root()
	var cr = root.get_node_or_null("CodeRunner")
	if cr == null:
		if output_label:
			output_label.text = "❌ Ошибка: CodeRunner не найден"
		return

	cr.run_code_async(code_text, "user_code.py")

func _on_run_finished(result: Dictionary) -> void:
	var stdout = result.get("stdout", "").replace("\r", "")
	var stderr = result.get("stderr", "").replace("\r", "")
	var exit_code = int(result.get("exit_code", -1))
	var tmp_path = result.get("tmp_path", "")

	# Показываем подробный вывод и путь к временному файлу
	if exit_code != 0:
		if output_label:
			output_label.text = "✘ Ошибка выполнения (exit=" + str(exit_code) + ")\n" + stderr + "\n\ntmp_path: " + tmp_path
	else:
		if output_label:
			output_label.text = stdout + "\n\ntmp_path: " + tmp_path

	# Проверяем решение через task_checker (если есть)
	if ResourceLoader.exists("res://db/task_checker.gd"):
		var checker = preload("res://db/task_checker.gd").new()
		var success = checker.check_user_solution(code_edit.text, current_task, stdout, output_label)
		if success:
			var computer = get_parent()
			if computer and computer.has_method("unassign_task_if_completed"):
				computer.unassign_task_if_completed()
