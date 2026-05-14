extends Node

signal step_changed(step_id: String)
signal tutorial_finished

const OVERLAY_SCENE := preload("res://scenes/tutorial/tutorial_overlay.tscn")

const STEP_ORDER: Array[String] = [
	"movement",
	"chest_1",
	"chest_2",
	"pickup",
	"inventory",
	"note",
]

const STEP_TEXTS: Dictionary = {
	"movement": {
		"title": "Добро пожаловать",
		"text": "WASD — движение.\nE — взаимодействие с объектами.\n\nСледуйте за стрелкой к первому шкафчику.",
	},
	"chest_1": {
		"title": "Шкафчик",
		"text": "Это шкафчик с усилением.\nНажмите E, чтобы открыть.\n\nИз него может выпасть предмет — подберите его и используйте через инвентарь (Tab).",
	},
	"chest_2": {
		"title": "Второй шкафчик",
		"text": "Откройте и этот шкафчик — иногда выпадает другое усиление.\n\nПредметы из шкафчиков складываются в инвентарь.",
	},
	"pickup": {
		"title": "Подбор предмета",
		"text": "Подойдите к выпавшему усилению и нажмите E.\n\nОно попадёт в инвентарь — откройте его клавишей Tab.",
	},
	"inventory": {
		"title": "Инвентарь",
		"text": "Tab — открыть инвентарь.\n\nНажмите на слот, чтобы применить усиление (скорость или невидимость).",
	},
	"note": {
		"title": "Записка",
		"text": "На карте лежат записки с подсказками.\nНажмите E, чтобы сохранить записку в журнал (B).\n\nПосле этого обучение завершится — исследуйте карту дальше сами.",
	},
}

var enabled: bool = true
var active: bool = false

var _step_index: int = 0
var _overlay: CanvasLayer = null
var _popup_open: bool = false

func set_enabled(value: bool) -> void:
	enabled = value

func is_active() -> bool:
	return active and enabled

func get_current_step() -> String:
	if not is_active() or _step_index >= STEP_ORDER.size():
		return ""
	return STEP_ORDER[_step_index]

func start_on_level() -> void:
	if not enabled:
		return
	active = true
	_step_index = 0
	_ensure_overlay()
	_overlay.show_tutorial_ui()
	_advance_to_current_step()

func try_interact_step(step_id: String, proceed: Callable) -> bool:
	if not is_active() or get_current_step() != step_id or _popup_open:
		return false
	_show_step_popup(step_id, proceed)
	return true

func notify_inventory_opened() -> void:
	if get_current_step() == "inventory":
		_complete_step()

func notify_journal_opened() -> void:
	if get_current_step() == "journal":
		_complete_step()

func is_popup_open() -> bool:
	return _popup_open

func _ensure_overlay() -> void:
	if _overlay != null and is_instance_valid(_overlay):
		return
	_overlay = OVERLAY_SCENE.instantiate() as CanvasLayer
	get_tree().root.add_child(_overlay)

func _advance_to_current_step() -> void:
	if not is_active():
		return
	var step := get_current_step()
	if step == "":
		_finish_tutorial()
		return
	step_changed.emit(step)
	if step == "movement" or step == "inventory":
		_show_step_popup(step, Callable())
	elif step == "pickup":
		_point_arrow_at_pickup()
	else:
		_point_arrow_at_target(step)

func _show_step_popup(step_id: String, proceed: Callable) -> void:
	var data: Dictionary = STEP_TEXTS.get(step_id, {})
	var wait_for_action := step_id == "inventory"
	_popup_open = true
	_ensure_overlay()
	_overlay.show_popup(
		str(data.get("title", "Подсказка")),
		str(data.get("text", "")),
		func() -> void:
			_popup_open = false
			if proceed.is_valid():
				proceed.call()
			if not wait_for_action:
				_complete_step()
	)

func _complete_step() -> void:
	if _overlay and is_instance_valid(_overlay):
		_overlay.hide_arrow()
	var finished_step := get_current_step()
	_step_index += 1
	if finished_step == "note" or _step_index >= STEP_ORDER.size():
		_finish_tutorial()
		return
	_advance_to_current_step()

func _finish_tutorial() -> void:
	active = false
	if _overlay and is_instance_valid(_overlay):
		_overlay.hide_arrow()
		_overlay.hide_tutorial_ui()
	tutorial_finished.emit()

func _point_arrow_at_target(step_id: String) -> void:
	_ensure_overlay()
	var target := _find_target(step_id)
	_overlay.point_at(target)

func _point_arrow_at_pickup() -> void:
	_ensure_overlay()
	var best: Node2D = null
	var player := get_tree().get_first_node_in_group("player") as Node2D
	var best_dist := INF
	for n in get_tree().get_nodes_in_group("tutorial_pickup"):
		if n == null or not is_instance_valid(n) or not (n is Node2D):
			continue
		if not n.visible:
			continue
		var dist := player.global_position.distance_squared_to((n as Node2D).global_position) if player else 0.0
		if dist < best_dist:
			best_dist = dist
			best = n as Node2D
	_overlay.point_at(best)

func _find_target(step_id: String) -> Node2D:
	for n in get_tree().get_nodes_in_group("tutorial_target"):
		if n == null or not is_instance_valid(n):
			continue
		if "tutorial_step" in n and str(n.tutorial_step) == step_id:
			return n as Node2D
	return null

func _process(_delta: float) -> void:
	if not is_active():
		return
	if get_current_step() == "pickup":
		_point_arrow_at_pickup()
