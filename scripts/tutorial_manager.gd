extends Node

signal tutorial_finished

const OVERLAY_SCENE := preload("res://scenes/tutorial/tutorial_overlay.tscn")

enum Phase { ROOM, COMPUTER, EXIT }

const REQUIRED_TOPICS: Array[String] = [
	"chest", "buff", "note", "inventory", "journal",
]

const LESSONS: Dictionary = {
	"intro": {
		"title": "Обучение",
		"text": "Вы в стартовой комнате.\n\nПодсвеченные объекты можно изучить: подойдите и нажмите E (или Tab / B, где указано).\n\nКогда разберётесь со всем важным — подскажем, куда идти дальше.",
	},
	"chest": {
		"title": "Шкаф и сундук",
		"text": "Шкафчики и сундуки с усилениями.\n\nКак пользоваться:\n• подойдите вплотную;\n• нажмите E — откроется;\n• если на пол выпал предмет — подберите его на E.",
	},
	"buff": {
		"title": "Усиление на полу",
		"text": "Выпавший предмет — бафф (скорость, невидимость или лечение).\n\n• E — подобрать в инвентарь;\n• Tab — открыть инвентарь;\n• клик по слоту — применить.",
	},
	"note": {
		"title": "Записка",
		"text": "Записки хранят подсказки по игре.\n\n• E рядом с запиской — сохранить;\n• B — журнал, вкладка «Записки».",
	},
	"inventory": {
		"title": "Инвентарь",
		"text": "Инвентарь — Tab.\n\nТуда попадают подобранные усиления.\nКликните по иконке в слоте, чтобы активировать эффект.",
	},
	"journal": {
		"title": "Журнал",
		"text": "Журнал — клавиша B.\n\nВкладки:\n• «Руководство» — подсказки по управлению;\n• «Записки» — собранные записки.",
	},
	"lever": {
		"title": "Рычаг",
		"text": "Рычаги переключаются на E.\n\nОни могут открывать двери или включать доступ к компьютерам — смотрите, что изменилось после переключения.",
	},
	"room_done": {
		"title": "Комната изучена",
		"text": "Отлично, вы разобрались с основами в стартовой комнате!\n\nКомпьютер для обучения — в комнате ниже.\n\n1) Спуститесь через дверь вниз (E).\n2) Подойдите к компьютеру и откройте терминал (E).",
	},
	"path_door": {
		"title": "Дверь вниз",
		"text": "Эта дверь ведёт в нижнюю комнату, где стоит учебный компьютер.\n\nНажмите E, чтобы открыть и пройти.",
	},
	"computer": {
		"title": "Компьютер",
		"text": "Терминал с заданиями.\n\n• подойдите и нажмите E;\n• пишите код и «Проверить решение»;\n• подсказки: журнал B → «Python: база» и записки на уровне;\n• после успеха откроется связанная дверь.\n\nСейчас откройте терминал хотя бы один раз.",
	},
	"exit_door": {
		"title": "Дверь дальше",
		"text": "Эта дверь ведёт дальше по уровню.\n\nСначала выполните задание на компьютере (если дверь закрыта — она откроется после успеха).\n\nЗатем E у двери, чтобы пройти.",
	},
	"finale": {
		"title": "Удачи!",
		"text": "Обучение завершено.\n\nДальше исследуйте карту сами: компьютеры, двери, записки и маньяк.\n\nУдачи!",
	},
}

@export var intro_room_id: int = 1
## Комната с учебным компьютером (Room2 на уровне, metadata/room_id = 4).
@export var tutorial_computer_room_id: int = 4
@export var tutorial_path_door_id: int = 1
## Учебный ПК (comp, computer_id=1) → после задания открывает дверь 2.
@export var tutorial_computer_id: int = 1
@export var tutorial_exit_door_id: int = 2

var enabled: bool = true
var active: bool = false

var _phase: int = Phase.ROOM
var _overlay: CanvasLayer = null
var _popup_open: bool = false
var _discovered: Dictionary = {}
var _room_polygon_global: PackedVector2Array = PackedVector2Array()
var _computer_room_polygon_global: PackedVector2Array = PackedVector2Array()
var _room_targets: Array[Dictionary] = []
var _terminal_opened_in_phase: bool = false
var _path_to_computer_cleared: bool = false

func set_enabled(value: bool) -> void:
	enabled = value


## После смерти и «Заново» — игрок уже видел обучение, не запускаем снова.
func skip_for_death_retry() -> void:
	prepare_exit_to_main_menu()


## Выход в главное меню = конец попытки: убрать обучение и весь UI с root.
func prepare_exit_to_main_menu() -> void:
	enabled = false
	active = false
	_popup_open = false
	_discovered.clear()
	_terminal_opened_in_phase = false
	_path_to_computer_cleared = false
	_phase = Phase.ROOM
	cleanup_overlays()


## Снять плашку/попап (без сброса enabled — для подстраховки в меню).
func cleanup_overlays() -> void:
	active = false
	_popup_open = false
	if typeof(GameState) != TYPE_NIL and GameState.has_method("clear_gameplay_freeze"):
		GameState.clear_gameplay_freeze()
	_teardown_overlay()
	_purge_loose_overlays()
	if get_tree().current_scene != null:
		_restore_interaction_highlights()


func shutdown(preserve_enabled: bool = true) -> void:
	if preserve_enabled:
		cleanup_overlays()
	else:
		prepare_exit_to_main_menu()

func is_active() -> bool:
	return active and enabled

func is_popup_open() -> bool:
	return _popup_open

func allows_tutorial_door(door_id: int) -> bool:
	if not is_active():
		return false
	# Дверь вниз — всегда доступна во время обучения (не ждём задание на ПК).
	if door_id == tutorial_path_door_id:
		return true
	if door_id == tutorial_exit_door_id:
		return _phase == Phase.EXIT and _terminal_opened_in_phase
	return false

func allows_tutorial_computer(computer_id: int) -> bool:
	if not is_active():
		return false
	return computer_id == tutorial_computer_id and _phase in [Phase.COMPUTER, Phase.EXIT]

func get_current_step() -> String:
	match _phase:
		Phase.ROOM:
			return "room_explore"
		Phase.COMPUTER:
			return "computer"
		Phase.EXIT:
			return "exit_door"
	return ""

func start_on_level() -> void:
	if not enabled:
		return
	active = true
	_phase = Phase.ROOM
	_discovered.clear()
	_terminal_opened_in_phase = false
	_path_to_computer_cleared = false
	_cache_room_polygon()
	_cache_computer_room_polygon()
	_collect_room_targets()
	_ensure_overlay()
	_overlay.show_tutorial_ui()
	_update_banner()
	_apply_room_highlights()
	call_deferred("_show_intro")

func _show_intro() -> void:
	_show_lesson("intro", Callable())

func try_lesson_then(topic: String, proceed: Callable) -> bool:
	if not is_active():
		if proceed.is_valid():
			proceed.call()
		return false
	if _popup_open:
		return true

	if _phase == Phase.ROOM:
		if topic in REQUIRED_TOPICS or topic == "lever":
			if not _discovered.get(topic, false):
				_show_lesson(topic, proceed)
				return true
		proceed.call() if proceed.is_valid() else null
		return false

	if _phase == Phase.COMPUTER and topic == "path_door":
		if not _discovered.get("path_door", false):
			_show_lesson("path_door", proceed)
			return true
		proceed.call() if proceed.is_valid() else null
		return false

	if _phase == Phase.COMPUTER and topic == "computer":
		if not _terminal_opened_in_phase:
			_show_lesson("computer", proceed)
			return true
		proceed.call() if proceed.is_valid() else null
		return false

	if _phase == Phase.EXIT and topic == "exit_door":
		if not _discovered.get("exit_door", false):
			_show_lesson("exit_door", proceed)
			return true
		proceed.call() if proceed.is_valid() else null
		return false

	proceed.call() if proceed.is_valid() else null
	return false

func notify_tab_pressed() -> void:
	if not is_active() or _phase != Phase.ROOM:
		return
	try_lesson_then("inventory", Callable())

func notify_journal_opened() -> void:
	if not is_active() or _phase != Phase.ROOM:
		return
	try_lesson_then("journal", Callable())

func notify_terminal_opened() -> void:
	if not is_active() or _phase != Phase.COMPUTER:
		return
	_terminal_opened_in_phase = true
	_advance_after_computer()

func notify_door_opened(door_id: int) -> void:
	if not is_active():
		return
	if door_id == tutorial_path_door_id:
		_on_path_door_opened()
		return
	if _phase != Phase.EXIT or door_id != tutorial_exit_door_id:
		return
	_show_lesson("finale", func() -> void:
		_finish_tutorial()
	)

func notify_item_added_to_inventory() -> void:
	if is_active() and _phase == Phase.ROOM:
		_mark_discovered("buff")

func notify_inventory_item_used() -> void:
	pass

func notify_inventory_opened() -> void:
	notify_tab_pressed()

func notify_note_collected(_note_id: String = "") -> void:
	if is_active() and _phase == Phase.ROOM:
		_mark_discovered("note")

func notify_chest_opened(_chest_id: String = "") -> void:
	if is_active() and _phase == Phase.ROOM:
		_mark_discovered("chest")

## Урок по двери — отдельно от E, чтобы «Понятно» не дёргало дверь повторно.
func try_door_interact(door_id: int) -> void:
	if not is_active() or _popup_open:
		return
	if door_id == tutorial_path_door_id:
		if _phase == Phase.COMPUTER and not _discovered.get("path_door", false):
			_show_lesson("path_door", Callable())
		return
	if door_id == tutorial_exit_door_id and _phase == Phase.EXIT:
		if not _discovered.get("exit_door", false):
			_show_lesson("exit_door", Callable())

func _on_path_door_opened() -> void:
	_path_to_computer_cleared = true
	if not _discovered.get("path_door", false):
		_mark_discovered("path_door")
	_update_banner()
	_refresh_phase_arrow()

# Совместимость со старыми вызовами
func try_interact_step(_step_id: String, proceed: Callable) -> bool:
	var topic := _step_id
	if _step_id == "chest_1" or _step_id == "chest_2":
		topic = "chest"
	return try_lesson_then(topic, proceed)

func notify_wrong_action(_kind: String = "") -> void:
	pass

func allows_step(_step_id: String) -> bool:
	return true

func allows_pickup() -> bool:
	return true

func allows_inventory() -> bool:
	return true

func allows_journal() -> bool:
	return true

func _mark_discovered(topic: String) -> void:
	if topic == "":
		return
	_discovered[topic] = true
	_update_banner()
	if _phase == Phase.ROOM:
		_apply_room_highlights()
		_try_finish_room_phase()

func _show_lesson_once(topic: String) -> void:
	if _discovered.get(topic, false) and LESSONS.has(topic):
		return
	_show_lesson(topic, Callable())

func _show_lesson(topic: String, proceed: Callable) -> void:
	var data: Dictionary = LESSONS.get(topic, {})
	_popup_open = true
	_ensure_overlay()
	_overlay.hide_arrow()
	_overlay.show_popup(
		str(data.get("title", "Подсказка")),
		str(data.get("text", "")),
		func() -> void:
			_popup_open = false
			if topic in REQUIRED_TOPICS or topic in ["lever", "path_door", "exit_door"]:
				_mark_discovered(topic)
			elif topic == "room_done":
				_clear_room_highlights()
			if proceed.is_valid():
				proceed.call()
			_update_banner()
			_refresh_phase_arrow()
	)

func _try_finish_room_phase() -> void:
	if _phase != Phase.ROOM:
		return
	for t in REQUIRED_TOPICS:
		if not _discovered.get(t, false):
			return
	_phase = Phase.COMPUTER
	_show_lesson("room_done", func() -> void:
		_clear_room_highlights()
		_enter_computer_phase()
	)

func _advance_after_computer() -> void:
	if _phase != Phase.COMPUTER:
		return
	_phase = Phase.EXIT
	_update_banner()
	_refresh_phase_arrow()

func _finish_tutorial() -> void:
	active = false
	_phase = Phase.ROOM
	_popup_open = false
	# Нельзя free() из колбэка Popup/BtnOk — объект ещё «locked».
	call_deferred("_teardown_overlay")
	call_deferred("_restore_interaction_highlights")
	tutorial_finished.emit()


func _teardown_overlay() -> void:
	var overlay := _overlay
	_overlay = null
	if overlay != null and is_instance_valid(overlay):
		if overlay.has_method("force_hide_all"):
			overlay.call("force_hide_all")
		overlay.queue_free()


func _purge_loose_overlays() -> void:
	var root := get_tree().root
	if root == null:
		return
	var remove_list: Array[Node] = []
	for child in root.get_children():
		if child.name == "TutorialOverlay":
			remove_list.append(child)
	for node in remove_list:
		if is_instance_valid(node):
			node.queue_free()


func _release_popup_blocks() -> void:
	if typeof(GameState) == TYPE_NIL:
		return
	if GameState.has_method("pop_gameplay_freeze"):
		GameState.pop_gameplay_freeze()
	if GameState.has_method("pop_world_input_block"):
		GameState.pop_world_input_block()

func _ensure_overlay() -> void:
	if _overlay != null and is_instance_valid(_overlay):
		return
	_overlay = OVERLAY_SCENE.instantiate() as CanvasLayer
	get_tree().root.add_child(_overlay)

func _update_banner() -> void:
	if _overlay == null or not is_instance_valid(_overlay):
		return
	match _phase:
		Phase.ROOM:
			var n := _count_discovered_required()
			var total := REQUIRED_TOPICS.size()
			_overlay.set_step_banner(
				n + 1,
				total + 1,
				"Осмотрите подсвеченные объекты (%d/%d)\n\nE — взаимодействие\nTab — инвентарь\nB — журнал" % [n, total]
			)
		Phase.COMPUTER:
			if not _path_to_computer_cleared:
				_overlay.set_step_banner(
					1, 2,
					"Спуститесь в нижнюю комнату\nE — дверь вниз (следуйте за стрелкой)"
				)
			else:
				_overlay.set_step_banner(
					2, 2,
					"Компьютер в нижней комнате\nE — открыть терминал"
				)
		Phase.EXIT:
			_overlay.set_step_banner(1, 1, "Выполните задание и откройте дверь (E)")

func _count_discovered_required() -> int:
	var n := 0
	for t in REQUIRED_TOPICS:
		if _discovered.get(t, false):
			n += 1
	return n

func _cache_room_polygon() -> void:
	_room_polygon_global = _polygon_for_room_id(intro_room_id)

func _cache_computer_room_polygon() -> void:
	_computer_room_polygon_global = _polygon_for_room_id(tutorial_computer_room_id)

func _polygon_for_room_id(room_id: int) -> PackedVector2Array:
	var poly := PackedVector2Array()
	for room in get_tree().get_nodes_in_group("rooms"):
		if room.get_meta("room_id", -1) != room_id:
			continue
		var col := room.get_node_or_null("CollisionPolygon2D") as CollisionPolygon2D
		if col == null:
			continue
		var xf: Transform2D = col.global_transform
		for p in col.polygon:
			poly.append(xf * p)
		return poly
	return poly

func _enter_computer_phase() -> void:
	if not _path_to_computer_cleared:
		var path_door := _find_door(tutorial_path_door_id)
		if path_door != null and path_door is Door and (path_door as Door).is_open:
			_path_to_computer_cleared = true
	_update_banner()
	_refresh_phase_arrow()

func _point_in_computer_room(world_pos: Vector2) -> bool:
	if _computer_room_polygon_global.is_empty():
		return false
	return Geometry2D.is_point_in_polygon(world_pos, _computer_room_polygon_global)

func _update_computer_phase_travel() -> void:
	if _phase != Phase.COMPUTER or _path_to_computer_cleared:
		return
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return
	if _point_in_computer_room(player.global_position):
		_path_to_computer_cleared = true
		_update_banner()
		_refresh_phase_arrow()

func _point_in_intro_room(world_pos: Vector2) -> bool:
	if _room_polygon_global.is_empty():
		return true
	return Geometry2D.is_point_in_polygon(world_pos, _room_polygon_global)

func _collect_room_targets() -> void:
	_room_targets.clear()
	_add_room_nodes_in_group("tutorial_target", func(n: Node) -> String:
		var step := str(n.get("tutorial_step")) if "tutorial_step" in n else ""
		if step.begins_with("chest"):
			return "chest"
		if step == "note":
			return "note"
		return ""
	)
	_add_room_nodes_in_group("tutorial_pickup", func(_n: Node) -> String:
		return "buff"
	)
	_add_room_nodes_in_group("levers", func(_n: Node) -> String:
		return "lever"
	)

func _add_room_nodes_in_group(group_name: String, topic_fn: Callable) -> void:
	for n in get_tree().get_nodes_in_group(group_name):
		if n == null or not is_instance_valid(n):
			continue
		var pos := _node_world_pos(n)
		if not _point_in_intro_room(pos):
			continue
		var topic: String = topic_fn.call(n)
		if topic == "":
			continue
		_room_targets.append({"node": n, "topic": topic})

func _node_world_pos(n: Node) -> Vector2:
	if n is Node2D:
		return (n as Node2D).global_position
	return Vector2.ZERO

func _prune_invalid_room_targets() -> void:
	var kept: Array[Dictionary] = []
	for entry in _room_targets:
		var obj: Variant = entry.get("node")
		if obj != null and is_instance_valid(obj):
			kept.append(entry)
	_room_targets = kept

func _entry_node(entry: Dictionary) -> Node:
	var obj: Variant = entry.get("node")
	if obj == null or not is_instance_valid(obj):
		return null
	return obj as Node

func _apply_room_highlights() -> void:
	# Только подсвечиваем ещё не изученное. Уже изученное — не трогаем:
	# иначе каждый кадр гасится подсветка от подхода игрока (body_entered).
	_prune_invalid_room_targets()
	for entry in _room_targets:
		var n := _entry_node(entry)
		if n == null:
			continue
		var topic: String = entry.get("topic", "")
		if bool(_discovered.get(topic, false)):
			continue
		if n.has_method("set_highlight"):
			n.set_highlight(true)
		if n.has_method("set_outline"):
			n.set_outline(true)

func _clear_room_highlights() -> void:
	_restore_interaction_highlights()

func _restore_interaction_highlights() -> void:
	for group_name in ["tutorial_target", "tutorial_pickup", "levers", "computers", "doors"]:
		for n in get_tree().get_nodes_in_group(group_name):
			if n == null or not is_instance_valid(n):
				continue
			if n.has_method("refresh_interaction_highlight"):
				n.refresh_interaction_highlight()

func _refresh_phase_arrow() -> void:
	if _overlay == null or not is_instance_valid(_overlay) or _popup_open:
		return
	match _phase:
		Phase.ROOM:
			_overlay.hide_arrow()
		Phase.COMPUTER:
			if _path_to_computer_cleared:
				_overlay.point_at(_find_computer())
			else:
				_overlay.point_at(_find_door(tutorial_path_door_id))
		Phase.EXIT:
			_overlay.point_at(_find_door(tutorial_exit_door_id))

func _find_computer() -> Node2D:
	for c in get_tree().get_nodes_in_group("computers"):
		if c != null and "computer_id" in c and int(c.computer_id) == tutorial_computer_id:
			return c as Node2D
	return null

func _find_door(door_id: int) -> Node2D:
	for d in get_tree().get_nodes_in_group("doors"):
		if d != null and "door_id" in d and int(d.door_id) == door_id:
			return d as Node2D
	return null

func _process(_delta: float) -> void:
	_sync_popup_state()
	if not is_active():
		return
	if _popup_open:
		return
	if _phase == Phase.ROOM:
		_apply_room_highlights()
	elif _phase == Phase.COMPUTER:
		_update_computer_phase_travel()
		_refresh_phase_arrow()
	elif _phase == Phase.EXIT:
		_refresh_phase_arrow()

func _sync_popup_state() -> void:
	if not _popup_open:
		return
	if _overlay == null or not is_instance_valid(_overlay):
		_popup_open = false
		return
	if not _overlay.popup.visible:
		_popup_open = false

func _on_room_phase_complete_popup_closed() -> void:
	_clear_room_highlights()
	_update_banner()
	_refresh_phase_arrow()
