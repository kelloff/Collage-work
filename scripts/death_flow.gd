extends Node

enum DeathCause { MANIAC, OTHER }

@export var screamer_scene: PackedScene = preload("res://scene/screamers/Screamer.tscn")
@export var stats_scene: PackedScene = preload("res://scene/DeathStats/death_stats.tscn")
@export var main_menu_scene_path: String = "res://scene/main-menu.tscn"

var _last_level_scene_path: String = ""
var _cause: int = DeathCause.OTHER

func start_death_flow(level_scene_path: String, cause: int) -> void:
	_last_level_scene_path = level_scene_path
	_cause = cause

	get_tree().paused = true

	# если вдруг забыли стартануть уровень — подстрахуемся
	if RunStats.level_started_ms <= 0:
		RunStats.start_level()

	RunStats.refresh_from_db()

	if _cause == DeathCause.MANIAC:
		_show_screamer_then_stats()
	else:
		_show_stats()

func _show_screamer_then_stats() -> void:
	var screamer: CanvasLayer = screamer_scene.instantiate() as CanvasLayer
	get_tree().root.add_child(screamer)
	screamer.process_mode = Node.PROCESS_MODE_ALWAYS

	screamer.finished.connect(func():
		screamer.queue_free()
		_show_stats()
	)

func _show_stats() -> void:
	var ui: Control = stats_scene.instantiate() as Control
	get_tree().root.add_child(ui)
	ui.process_mode = Node.PROCESS_MODE_ALWAYS

	var time_txt: String = RunStats.get_elapsed_text()
	var tasks_done: int = RunStats.get_completed_tasks()
	print("ELAPSED=", RunStats.get_elapsed_seconds())
	var stats_text: String = "Время: %s\nЗаданий выполнено: %d" % [time_txt, tasks_done]

	if ui.has_method("set_stats_text"):
		ui.call("set_stats_text", stats_text)

	ui.retry_pressed.connect(func():
		ui.queue_free()
		get_tree().paused = false
		get_tree().change_scene_to_file(_last_level_scene_path)
	)

	ui.menu_pressed.connect(func():
		ui.queue_free()
		get_tree().paused = false
		get_tree().change_scene_to_file(main_menu_scene_path)
	)
