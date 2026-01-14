extends CanvasLayer

@onready var code_edit = get_node_or_null("PanelContainer/HBoxContainer/CodeEditor")
@onready var run_button = get_node_or_null("PanelContainer/HBoxContainer/VBoxContainer/RunButton")
@onready var close_button = get_node_or_null("PanelContainer/HBoxContainer/VBoxContainer/CloseButton")
@onready var output_label = get_node_or_null("PanelContainer/HBoxContainer/VBoxContainer/OutputScroll/OutputLabel")
@onready var task_label = get_node_or_null("PanelContainer/HBoxContainer/VBoxContainer/TaskLabel")

var current_task: Dictionary = {}   # сюда Computer.gd передаёт задание

func _ready():
	CodeRunner.connect("run_finished", Callable(self, "_on_run_finished"))
	if run_button:
		run_button.pressed.connect(_on_run_button_pressed)
	if close_button:
		close_button.pressed.connect(_on_close_button_pressed)
	hide()

# открыть терминал и сразу передать задание/сообщение
func open_with_task(level: int, task: Dictionary):
	if current_task.is_empty():
		current_task = task
	show()
	if output_label:
		output_label.text = ""

	# если это сообщение, а не задание
	if current_task.has("message"):
		task_label.text = current_task["message"]
		if code_edit:
			code_edit.text = "# " + current_task["message"]
		return

	# иначе это нормальное задание
	if current_task.has("description"):
		task_label.text = "Задание: " + current_task["description"]
	else:
		task_label.text = "Нет задания"

	if code_edit:
		code_edit.text = """# Подсказки по синтаксису Python:
# ---------------------------------
# Переменные:
#   x = 10
#   name = "Python"
#
# Вывод на экран:
#   print("текст")
#   print(x)
#
# Условные конструкции:
#   if x > 5:
#       print("Больше")
#   else:
#       print("Меньше")
#
# Проверка чётности:
#   if x % 2 == 0:
#       print("Even")
#   else:
#       print("Odd")
#
# Циклы:
#   for i in range(3):
#       print(i)
#
#   for item in [1,2,3]:
#       print(item)
#
# Работа со списками:
#   nums = [5,2,9,1]
#   nums.sort()
#   print(nums)
#
#   print(len(nums))   # количество элементов
#   print(sum(nums))   # сумма элементов
#   print(max(nums))   # максимум
#   print(min(nums))   # минимум
#
# Важно:
# - Отступы имеют значение! После if/for ставьте 4 пробела.
# - Используйте переменные и операции, а не просто готовый ответ.
#
# ---------------------------------
# Решение:
"""

func close():
	hide()
	current_task = {}

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
	var clean_stdout = result.get("stdout", "").replace("\r", "")
	var checker = preload("res://db/task_checker.gd").new()

	# если это сообщение, проверку не запускаем
	if current_task.has("message"):
		output_label.text = current_task["message"]
		return

	var success = checker.check_user_solution(code_edit.text, current_task, clean_stdout, output_label)

	if success:
		var computer = get_parent()
		if computer and computer.has_method("unassign_task_if_completed"):
			computer.unassign_task_if_completed()

func _on_close_button_pressed():
	close()
