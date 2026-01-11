extends Node

@onready var db_manager = preload("res://db/db_meneger.gd").new()
@onready var task_checker = preload("res://db/task_checker.gd").new()

var current_task: Dictionary = {}

func _ready():
	if db_manager.open_db():
		print("База открыта")

func assign_task(level: int) -> Dictionary:
	current_task = db_manager.get_random_task_by_level(level)
	if current_task.is_empty():
		print("Нет доступных заданий для уровня %d" % level)
	return current_task

func check_solution(user_code: String, actual_output: String) -> Dictionary:
	if current_task.is_empty():
		return {"success": false, "message": "Нет активного задания"}
	return task_checker.check_user_solution(user_code, current_task, actual_output)
