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

# открыть терминал и сразу передать задание
func open_with_task(level: int, task: Dictionary):
	current_task = task
	show()
	if output_label:
		output_label.text = ""

	if current_task.has("description"):
		task_label.text = "Задание: " + current_task["description"]
	else:
		task_label.text = "Нет задания"

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
	var clean_stdout = result.get("stdout", "").replace("\r", "")
	var checker = preload("res://db/task_checker.gd").new()
	var success = checker.check_user_solution(code_edit.text, current_task, clean_stdout, output_label)

	# если решение правильное → открепляем задание через Computer.gd
	if success:
		var computer = get_parent()
		if computer and computer.has_method("unassign_task_if_completed"):
			computer.unassign_task_if_completed()

func _on_close_button_pressed():
	close()
