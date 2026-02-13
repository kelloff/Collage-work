extends Node

var level_started_ms: int = 0
var completed_tasks: int = 0

func start_level() -> void:
	level_started_ms = Time.get_ticks_msec()
	completed_tasks = 0

func get_elapsed_seconds() -> float:
	if level_started_ms <= 0:
		return 0.0
	return float(Time.get_ticks_msec() - level_started_ms) / 1000.0

func get_elapsed_text() -> String:
	var sec_i: int = int(get_elapsed_seconds())
	var mm: int = sec_i / 60
	var ss: int = sec_i % 60
	return "%02d:%02d" % [mm, ss]

func add_completed_task(count: int = 1) -> void:
	completed_tasks += count

func get_completed_tasks() -> int:
	return completed_tasks

# Если захочешь подтягивать из БД — вставишь сюда query
func refresh_from_db() -> void:
	# пример-заглушка:
	# if DbMeneger and DbMeneger.db:
	#     DbMeneger.db.query("SELECT ...")
	#     completed_tasks = ...
	pass
