extends Node
## Настройки потока «Новая игра»: куда грузить после генерации, сколько задач запросить.

const DEFAULT_LEVEL_SCENE := "res://scenes/level_1/level_1.tscn"

## Сцена после успешной генерации и сброса БД
var next_level_scene: String = DEFAULT_LEVEL_SCENE

## Как в beck/generate_tasks_to_gd.py: LEVELS = [0, 1, 2, 3]
const GENERATE_LEVELS: Array[int] = [0, 1, 2, 3]

## Сколько задач запросить на каждый уровень (отдельный POST /generate_tasks на уровень).
@export var generate_task_count: int = 5
