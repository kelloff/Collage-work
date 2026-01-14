extends Node

@onready var db_manager = preload("res://db/db_meneger.gd").new()
@onready var task_checker = preload("res://db/task_checker.gd").new()

var current_task: Dictionary = {}

func _ready():
	print("База открыта")  # база открывается внутри db_manager._ready()

func assign_task(level: int, computer_id: int) -> Dictionary:
	current_task = db_manager.assign_task(level, computer_id)
	if current_task.is_empty():
		print("Нет доступных заданий для уровня %d" % level)
	return current_task

func check_solution(user_code: String, actual_output: String, output_label: RichTextLabel) -> Dictionary:
	if current_task.is_empty():
		return {"success": false, "message": "Нет активного задания"}
	var success = task_checker.check_user_solution(user_code, current_task, actual_output, output_label)
	return {"success": success, "message": output_label.text}
