extends Node

## Сбор метрик прохождения и расчёт итоговой оценки 0–100.

const BEST_SCORE_PATH := "user://best_run_score.json"

## Среднее время на задание (сек), при котором даётся полный блок «Скорость».
const PAR_SECONDS_PER_TASK := 90.0
const MIN_SOLVE_SECONDS := 8.0

var level_started_ms: int = 0
var level_number: int = 1
var total_tasks_on_level: int = 0
var completed_tasks: int = 0

var failed_attempts: int = 0
var successful_checks: int = 0
var death_count: int = 0

var _solve_times_sec: Array[float] = []
var _attempt_started_ms: int = 0

func start_level(level: int = 1) -> void:
	level_number = level
	level_started_ms = Time.get_ticks_msec()
	completed_tasks = 0
	failed_attempts = 0
	successful_checks = 0
	death_count = 0
	_solve_times_sec.clear()
	_attempt_started_ms = 0


func reset_session() -> void:
	level_started_ms = 0
	level_number = 1
	total_tasks_on_level = 0
	completed_tasks = 0
	failed_attempts = 0
	successful_checks = 0
	death_count = 0
	_solve_times_sec.clear()
	_attempt_started_ms = 0


func set_total_tasks_on_level(count: int) -> void:
	total_tasks_on_level = maxi(count, 1)


func register_level_computers_from_tree(tree: SceneTree) -> void:
	if tree == null:
		return
	var n := 0
	for c in tree.get_nodes_in_group("computers"):
		if c == null or not is_instance_valid(c):
			continue
		if "computer_id" in c and int(c.computer_id) > 0:
			n += 1
	set_total_tasks_on_level(n)


func add_completed_task(count: int = 1) -> void:
	completed_tasks += count


func get_completed_tasks() -> int:
	return completed_tasks


func record_death() -> void:
	death_count += 1


func begin_task_attempt() -> void:
	_attempt_started_ms = Time.get_ticks_msec()


func record_task_failure() -> void:
	failed_attempts += 1
	_attempt_started_ms = 0


func record_task_success() -> void:
	successful_checks += 1
	if _attempt_started_ms > 0:
		var dt := float(Time.get_ticks_msec() - _attempt_started_ms) / 1000.0
		_solve_times_sec.append(maxf(dt, MIN_SOLVE_SECONDS))
	_attempt_started_ms = 0


func get_elapsed_seconds() -> float:
	if level_started_ms <= 0:
		return 0.0
	return float(Time.get_ticks_msec() - level_started_ms) / 1000.0


func get_elapsed_text() -> String:
	return _format_duration(int(get_elapsed_seconds()))


func refresh_from_db() -> void:
	if typeof(DbManager) == TYPE_NIL or DbManager.db == null:
		return
	var lvl := level_number
	DbManager.db.query(
		"SELECT COUNT(DISTINCT computer_id) AS c FROM progress WHERE level = %d AND status = 'done'" % lvl
	)
	var rows: Array = DbManager.db.query_result
	if rows.is_empty():
		return
	var row: Variant = rows[0]
	var n := 0
	if typeof(row) == TYPE_DICTIONARY:
		n = int((row as Dictionary).get("c", 0))
	completed_tasks = maxi(completed_tasks, n)


func get_score_breakdown(victory: bool = false) -> Dictionary:
	refresh_from_db()
	var total: int = maxi(total_tasks_on_level, 1)
	var done: int = mini(completed_tasks, total)
	var deaths: int = death_count
	if typeof(GameState) != TYPE_NIL and GameState.death_count > deaths:
		deaths = GameState.death_count

	var task_pts: float = 50.0 * float(done) / float(total)
	if victory and done >= total:
		task_pts = 50.0

	var avg_solve: float = _average_solve_seconds()
	var speed_pts: float = 0.0
	if successful_checks > 0 and avg_solve > 0.0:
		var speed_ratio: float = clampf(PAR_SECONDS_PER_TASK / avg_solve, 0.0, 1.25)
		speed_pts = 25.0 * speed_ratio
	elif done > 0:
		var elapsed: float = maxf(get_elapsed_seconds(), 1.0)
		var est_avg: float = elapsed / float(maxi(done, 1))
		speed_pts = 25.0 * clampf(PAR_SECONDS_PER_TASK / est_avg, 0.0, 1.25)

	var attempts_total: int = successful_checks + failed_attempts
	var accuracy_pts: float = 0.0
	if attempts_total > 0:
		accuracy_pts = 15.0 * float(successful_checks) / float(attempts_total)
	elif done > 0:
		accuracy_pts = 12.0

	var survival_pts: float = clampf(10.0 - float(deaths) * 4.0, 0.0, 10.0)

	var total_score: int = int(round(clampf(task_pts + speed_pts + accuracy_pts + survival_pts, 0.0, 100.0)))

	return {
		"total_score": total_score,
		"grade_label": _grade_label(total_score),
		"task_points": int(round(task_pts)),
		"speed_points": int(round(speed_pts)),
		"accuracy_points": int(round(accuracy_pts)),
		"survival_points": int(round(survival_pts)),
		"tasks_done": done,
		"tasks_total": total,
		"failed_attempts": failed_attempts,
		"successful_checks": successful_checks,
		"avg_solve_seconds": avg_solve,
		"elapsed_text": get_elapsed_text(),
		"deaths": deaths,
		"victory": victory,
	}


func build_report_text(victory: bool = false) -> String:
	var b: Dictionary = get_score_breakdown(victory)
	var lines: PackedStringArray = PackedStringArray()

	if victory:
		lines.append("Итоговая оценка: %d / 100 — %s" % [b.total_score, b.grade_label])
	else:
		lines.append("Оценка попытки: %d / 100 — %s" % [b.total_score, b.grade_label])

	lines.append("")
	lines.append("Задания: %d из %d  (+%d баллов)" % [b.tasks_done, b.tasks_total, b.task_points])
	lines.append("Время прохождения: %s" % b.elapsed_text)

	if b.successful_checks > 0 or b.failed_attempts > 0:
		lines.append(
			"Проверки: успешно %d, ошибок %d  (+%d баллов точность)" % [
				b.successful_checks, b.failed_attempts, b.accuracy_points
			]
		)
	else:
		lines.append("Проверки: данных пока нет")

	if float(b.avg_solve_seconds) > 0.0:
		lines.append(
			"Среднее на задание: %s  (+%d баллов скорость)" % [
				_format_duration(int(b.avg_solve_seconds)), b.speed_points
			]
		)
	else:
		lines.append("Скорость: +%d баллов" % b.speed_points)

	lines.append("Смерти: %d  (+%d баллов выживание)" % [b.deaths, b.survival_points])
	lines.append("")
	lines.append(_score_hint(b.total_score, victory))

	var best: int = load_best_score()
	if best > 0:
		if b.total_score >= best:
			lines.append("Новый рекорд! (было %d)" % best)
		else:
			lines.append("Лучший результат: %d / 100" % best)

	return "\n".join(lines)


func try_save_best_score(victory: bool = true) -> void:
	if not victory:
		return
	var score: int = int(get_score_breakdown(true).get("total_score", 0))
	var prev := load_best_score()
	if score > prev:
		var f := FileAccess.open(BEST_SCORE_PATH, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify({"best_score": score, "saved_at": Time.get_unix_time_from_system()}))


func load_best_score() -> int:
	if not FileAccess.file_exists(BEST_SCORE_PATH):
		return 0
	var f := FileAccess.open(BEST_SCORE_PATH, FileAccess.READ)
	if f == null:
		return 0
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return 0
	return int((parsed as Dictionary).get("best_score", 0))


func _average_solve_seconds() -> float:
	if _solve_times_sec.is_empty():
		return 0.0
	var sum := 0.0
	for t in _solve_times_sec:
		sum += t
	return sum / float(_solve_times_sec.size())


func _format_duration(sec_i: int) -> String:
	var mm: int = sec_i / 60
	var ss: int = sec_i % 60
	return "%02d:%02d" % [mm, ss]


func _grade_label(score: int) -> String:
	if score >= 90:
		return "Отлично!"
	if score >= 75:
		return "Хорошо"
	if score >= 60:
		return "Неплохо"
	if score >= 40:
		return "Средне"
	return "Есть куда расти"


func _score_hint(score: int, victory: bool) -> String:
	if victory and score >= 90:
		return "Ты прошёл игру блестяще. Попробуй ускориться или пройти без ошибок?"
	if victory:
		return "Пройди быстрее, с меньшим числом ошибок и без смертей — оценка вырастет."
	if score < 50:
		return "Доделай задания на компьютерах и ищи выход."
	return "Ты уже близко — выполни оставшиеся задания и доберись до выхода."
