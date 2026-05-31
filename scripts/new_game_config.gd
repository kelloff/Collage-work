extends Node
## Настройки потока «Новая игра»: куда грузить после генерации, сколько задач запросить.

const DEFAULT_LEVEL_SCENE := "res://scenes/level_1/level_1.tscn"

## Сцена после успешной генерации и сброса БД
var next_level_scene: String = DEFAULT_LEVEL_SCENE

## Как в beck/generate_tasks_to_gd.py: LEVELS = [0, 1, 2, 3]
const GENERATE_LEVELS: Array[int] = [0, 1, 2, 3]

## Сколько задач запросить на каждый уровень (отдельный POST /generate_tasks на уровень).
@export var generate_task_count: int = 5

## Запас к запросу: сервер отдаёт больше, клиент фильтрует и берёт generate_task_count.
const GENERATE_OVERFETCH_EXTRA: int = 3


func server_request_count_per_level() -> int:
	var base := maxi(1, generate_task_count)
	return base + GENERATE_OVERFETCH_EXTRA


func server_topup_request_count(need: int) -> int:
	return maxi(need, need + 2)

## true — только res://db/task_data.gd (офлайн-тест). false — POST /generate_tasks_multi на BackendUrls.
var use_local_tasks_only: bool = false


func _ready() -> void:
	var e := OS.get_environment("COLLAGE_USE_LOCAL_TASKS").strip_edges().to_lower()
	if e == "1" or e == "true" or e == "yes":
		use_local_tasks_only = true
	elif e == "0" or e == "false" or e == "no":
		use_local_tasks_only = false
	var off := OS.get_environment("COLLAGE_OFFLINE").strip_edges().to_lower()
	if off in ["1", "true", "yes", "on"]:
		use_local_tasks_only = true
