extends Node

enum DeathCause { MANIAC, OTHER }

@export var screamer_scene: PackedScene = preload("res://scenes/screamer/screamer.tscn")
@export var stats_scene: PackedScene = preload("res://scenes/death_stats/death_stats.tscn")
@export var main_menu_scene_path: String = "res://scenes/main_menu/main_menu.tscn"

var _last_level_scene_path: String = ""
var _cause: int = DeathCause.OTHER

func start_death_flow(level_scene_path: String, cause: int) -> void:
	_last_level_scene_path = level_scene_path
	_cause = cause
	RunStats.record_death()

	# Важно: если смерть наступила внутри терминала/другого world-UI,
	# закрываем такие окна ДО паузы, иначе death-экран может оказаться "сзади".
	_close_world_overlays_before_death()
	_hide_level_hud()
	if typeof(GameState) != TYPE_NIL and GameState.has_method("clear_gameplay_freeze"):
		GameState.clear_gameplay_freeze()
	get_tree().paused = true

	# если вдруг забыли стартануть уровень — подстрахуемся
	if RunStats.level_started_ms <= 0:
		RunStats.start_level()

	RunStats.refresh_from_db()

	if _cause == DeathCause.MANIAC:
		_show_screamer_then_stats()
	else:
		_show_stats()

func _close_world_overlays_before_death() -> void:
	# 1) Закрываем терминалы через Computer API (снимает блок ввода и контроль игрока).
	for c in get_tree().get_nodes_in_group("computers"):
		if c != null and c.has_method("close_terminal"):
			c.close_terminal()

	# 2) Fallback: если где-то остался TerminalUI вне standard flow — просто прячем.
	var scene := get_tree().current_scene
	if scene == null:
		return
	for n in scene.find_children("TerminalUI", "", true, false):
		if n == null:
			continue
		if n.has_method("close"):
			n.call("close")
		elif n is CanvasItem:
			(n as CanvasItem).hide()

func _hide_level_hud() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var hud := scene.get_node_or_null("HUD")
	if hud is CanvasItem:
		(hud as CanvasItem).hide()

func _show_screamer_then_stats() -> void:
	var screamer: CanvasLayer = screamer_scene.instantiate() as CanvasLayer
	get_tree().root.add_child(screamer)
	screamer.process_mode = Node.PROCESS_MODE_ALWAYS

	screamer.finished.connect(func():
		screamer.queue_free()
		_show_stats()
	)

func _show_stats() -> void:
	var ui: CanvasLayer = stats_scene.instantiate() as CanvasLayer
	get_tree().root.add_child(ui)
	ui.process_mode = Node.PROCESS_MODE_ALWAYS

	var stats_text: String = RunStats.build_report_text(false)

	if ui.has_method("set_stats_text"):
		ui.call("set_stats_text", stats_text)

	ui.retry_pressed.connect(func():
		if typeof(TutorialManager) != TYPE_NIL and TutorialManager.has_method("skip_for_death_retry"):
			TutorialManager.skip_for_death_retry()
		if typeof(Savemeneger) != TYPE_NIL and Savemeneger.has_method("reset_run_after_death"):
			Savemeneger.reset_run_after_death()
		ui.queue_free()
		get_tree().paused = false
		get_tree().change_scene_to_file(_last_level_scene_path)
	)

	ui.menu_pressed.connect(func():
		if typeof(TutorialManager) != TYPE_NIL and TutorialManager.has_method("prepare_exit_to_main_menu"):
			TutorialManager.prepare_exit_to_main_menu()
		if typeof(Savemeneger) != TYPE_NIL and Savemeneger.has_method("reset_run_after_death"):
			Savemeneger.reset_run_after_death()
		ui.queue_free()
		get_tree().paused = false
		get_tree().change_scene_to_file(main_menu_scene_path)
	)
