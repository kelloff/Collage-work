# res://scripts/GameState.gd
extends Node

# --- Статистика текущей попытки ---
var hits_taken: int = 0
var start_time: float = 0.0
var death_count: int = 0

# --- Дополнительные метрики (по желанию) ---
var pickups_collected: int = 0
var distance_traveled: float = 0.0

# --------------------
# Вспомогательная функция получения текущего времени в секундах
# --------------------
func _now_seconds() -> float:
	# Попробуем несколько вариантов динамически, чтобы избежать ошибок компиляции
	# 1) Engine.get_time_in_seconds (если доступен)
	if Engine.has_method("get_time_in_seconds"):
		var v = Engine.call("get_time_in_seconds")
		if typeof(v) in [TYPE_INT, TYPE_FLOAT]:
			return float(v)
	# 2) OS.get_unix_time (секунды)
	if OS.has_method("get_unix_time"):
		var v2 = OS.call("get_unix_time")
		if typeof(v2) in [TYPE_INT, TYPE_FLOAT]:
			return float(v2)
	# 3) OS.get_ticks_msec (миллисекунды)
	if OS.has_method("get_ticks_msec"):
		var v3 = OS.call("get_ticks_msec")
		if typeof(v3) in [TYPE_INT, TYPE_FLOAT]:
			return float(v3) / 1000.0
	# 4) Time.get_ticks_msec (если класс Time доступен)
	if typeof(Time) != TYPE_NIL and Time.has_method("get_ticks_msec"):
		var v4 = Time.call("get_ticks_msec")
		if typeof(v4) in [TYPE_INT, TYPE_FLOAT]:
			return float(v4) / 1000.0
	# 5) fallback: попытаться получить unix time через Engine singleton динамически
	if Engine.has_method("get_unix_time"):
		var v5 = Engine.call("get_unix_time")
		if typeof(v5) in [TYPE_INT, TYPE_FLOAT]:
			return float(v5)
	# Если ничего не доступно — вернуть 0.0 (без падения)
	return 0.0

# --------------------
# API для управления попыткой
# --------------------
func start_run() -> void:
	#"""Вызывать при старте уровня/попытки."""
	hits_taken = 0
	start_time = _now_seconds()
	pickups_collected = 0
	distance_traveled = 0.0

func record_hit() -> void:
	hits_taken += 1

func record_death() -> void:
	death_count += 1

func add_pickup(count: int = 1) -> void:
	pickups_collected += count

func add_distance(delta: float) -> void:
	distance_traveled += delta

# --------------------
# Получение статистики
# --------------------
func get_time_survived() -> float:
	if start_time == 0.0:
		return 0.0
	return _now_seconds() - start_time

func get_summary() -> Dictionary:
	return {
		"hits_taken": hits_taken,
		"time_survived": get_time_survived(),
		"death_count": death_count,
		"pickups_collected": pickups_collected,
		"distance_traveled": distance_traveled
	}

# --------------------
# Утилиты
# --------------------
func reset_all() -> void:
	hits_taken = 0
	start_time = 0.0
	death_count = 0
	pickups_collected = 0
	distance_traveled = 0.0
