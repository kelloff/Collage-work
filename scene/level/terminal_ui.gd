extends CanvasLayer

@onready var code_edit = get_node_or_null("PanelContainer/HBoxContainer/CodeEditor")
@onready var run_button = get_node_or_null("PanelContainer/HBoxContainer/VBoxContainer/RunButton")
@onready var close_button = get_node_or_null("PanelContainer/HBoxContainer/VBoxContainer/CloseButton")
@onready var output_label = get_node_or_null("PanelContainer/HBoxContainer/VBoxContainer/OutputScroll/OutputLabel")
@onready var task_label = get_node_or_null("PanelContainer/HBoxContainer/VBoxContainer/TaskLabel")

var current_task: Dictionary = {}

func _ready():
	CodeRunner.connect("run_finished", Callable(self, "_on_run_finished"))
	if run_button:
		run_button.pressed.connect(_on_run_button_pressed)
	if close_button:
		close_button.pressed.connect(_on_close_button_pressed)
	hide()

# новый метод: открытие с уровнем
func open_with_level(level: int):
	if visible:
		return

	show()
	if output_label:
		output_label.text = ""

	# Загружаем случайное задание по уровню
	current_task = DbMeneger.get_random_task_by_level(level)
	if task_label:
		task_label.text = "Задание: " + current_task.get("description", "Нет задания")

	if code_edit:
		code_edit.text = """# Подсказки по синтаксису:
# - Переменные: x = 10
# - Вывод: print("текст")
# - Отступы важны! После if/for ставьте 4 пробела
# - Пример if:
#   if x > 5:
#       print("Больше")
#   else:
#       print("Меньше")
# - Пример цикла:
#   for i in range(3):
#       print(i)

# Решение:
"""

func close():
	hide()

func _on_run_button_pressed():
	if not code_edit:
		if output_label:
			output_label.text = "CodeEdit не найден"
		return

	var code_text = code_edit.text
	if output_label:
		output_label.text = "Запуск..."
	CodeRunner.run_code_async(code_text, "user_code.py")

func _on_run_finished(result: Dictionary) -> void:
	var out = ""
	out += "Exit code: %s\n" % str(result.get("exit_code", -1))
	out += "Duration: %s s\n\n" % str(result.get("duration", 0.0))

	var clean_stdout = result.get("stdout", "").replace("\r", "")
	if clean_stdout != "":
		out += "STDOUT:\n" + clean_stdout + "\n\n"

		# --- Проверка решения через task_checker ---
		if current_task and current_task.has("expected_output"):
			var checker = preload("res://db/task_checker.gd").new()
			checker.check_user_solution(code_edit.text, current_task, clean_stdout, output_label)
			# check_user_solution сам пишет результат в output_label
			return

	var clean_stderr = result.get("stderr", "").replace("\r", "")
	if clean_stderr != "":
		out += "STDERR:\n" + clean_stderr + "\n\n"

	out += "Temp file: " + str(result.get("tmp_path", "")) + "\n"

	if output_label:
		output_label.text = out


func _on_close_button_pressed():
	close()
