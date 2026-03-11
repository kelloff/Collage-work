extends Node
signal run_finished(result: Dictionary)

# Можно оставить "py", но лучше пусть сам определит
@export var python_cmd: String = ""  # если пусто -> auto detect
@export var tmp_dir: String = "user://user_code_tmp"  # лучше user:// чем res://
@export var timeout_sec: float = 4.0
@export var keep_tmp_files: bool = true
@export var max_output_chars: int = 12000
@export var debug_logs: bool = false

var thread: Thread = null
var _queue: Array[Dictionary] = []
var _running: bool = false


func _ready() -> void:
	randomize()

	var abs_tmp_dir := ProjectSettings.globalize_path(tmp_dir)
	if not DirAccess.dir_exists_absolute(abs_tmp_dir):
		var err := DirAccess.make_dir_recursive_absolute(abs_tmp_dir)
		if err != OK:
			push_error("CodeRunner: cannot create tmp dir: %s (err=%d)" % [abs_tmp_dir, err])

	if python_cmd.strip_edges() == "":
		python_cmd = _detect_python_command()
		if debug_logs:
			print("CodeRunner: detected python_cmd =", python_cmd)


# ---------------- PUBLIC API ----------------
func run_code_async(code_text: String, filename_hint: String = "user_code.py") -> void:
	# Добавляем в очередь
	_queue.append({
		"code_text": code_text,
		"filename_hint": filename_hint
	})

	# Если уже идёт выполнение — просто ждём
	if _running:
		return

	_start_next_job()


# ---------------- INTERNAL: queue/thread ----------------
func _start_next_job() -> void:
	if _queue.is_empty():
		return

	_running = true
	var job: Dictionary = _queue.pop_front()

	# Стартуем новый поток
	if thread:
		# Если вдруг старый поток не очищен — не блокируем main thread
		thread = null

	thread = Thread.new()
	var callable := Callable(self, "_thread_run_code").bind(job)
	thread.start(callable)


func _thread_run_code(args: Dictionary) -> void:
	var start_time := Time.get_ticks_msec()

	var code_text: String = args.get("code_text", "")
	var filename_hint: String = args.get("filename_hint", "user_code.py")

	# --------- prepare file paths ----------
	var uid := str(Time.get_unix_time_from_system()) + "_" + str(randi())
	var safe_hint := _sanitize_filename(filename_hint)
	if not safe_hint.ends_with(".py"):
		safe_hint += ".py"

	var abs_tmp_dir := ProjectSettings.globalize_path(tmp_dir)
	if not DirAccess.dir_exists_absolute(abs_tmp_dir):
		var err := DirAccess.make_dir_recursive_absolute(abs_tmp_dir)
		if err != OK:
			_emit_from_thread({
				"exit_code": -1,
				"stdout": "",
				"stderr": "Cannot create tmp dir: " + abs_tmp_dir,
				"duration": 0.0,
				"tmp_path": tmp_dir + "/" + uid + "_" + safe_hint,
				"abs_path": ""
			})
			return

	var abs_path := abs_tmp_dir
	if not abs_path.ends_with("/") and not abs_path.ends_with("\\"):
		abs_path += "/"
	abs_path += uid + "_" + safe_hint

	var logical_path := tmp_dir.rstrip("/") + "/" + uid + "_" + safe_hint

	# --------- write file ----------
	var f := FileAccess.open(abs_path, FileAccess.WRITE)
	if f == null:
		_emit_from_thread({
			"exit_code": -1,
			"stdout": "",
			"stderr": "Cannot open temp file: " + abs_path,
			"duration": 0.0,
			"tmp_path": logical_path,
			"abs_path": abs_path
		})
		return

	f.store_string(code_text)
	f.close()

	# --------- execute python ----------
	if python_cmd.strip_edges() == "":
		_emit_from_thread({
			"exit_code": -1,
			"stdout": "",
			"stderr": "python_cmd is empty and auto-detect failed",
			"duration": 0.0,
			"tmp_path": logical_path,
			"abs_path": abs_path
		})
		return

	var exec_result := _run_python_with_timeout(abs_path, timeout_sec)

	var duration := float(Time.get_ticks_msec() - start_time) / 1000.0

	var stdout_text: String = exec_result.get("stdout", "")
	var stderr_text: String = exec_result.get("stderr", "")
	var exit_code: int = int(exec_result.get("exit_code", -1))
	var timed_out: bool = bool(exec_result.get("timed_out", false))

	# Ограничим объём вывода
	stdout_text = _clip_text(stdout_text, max_output_chars)
	stderr_text = _clip_text(stderr_text, max_output_chars)

	var result := {
		"exit_code": exit_code,
		"stdout": stdout_text,
		"stderr": stderr_text,
		"duration": duration,
		"tmp_path": logical_path,
		"abs_path": abs_path,
		"timed_out": timed_out
	}

	# удаление файла при желании
	if not keep_tmp_files:
		_try_delete(abs_path)

	_emit_from_thread(result)


func _emit_from_thread(result: Dictionary) -> void:
	call_deferred("_emit_result", result)


func _emit_result(result: Dictionary) -> void:
	emit_signal("run_finished", result)

	# завершаем поток аккуратно
	if thread:
		thread.wait_to_finish()
		thread = null

	_running = false
	_start_next_job()


# ---------------- EXECUTION ----------------
func _run_python_with_timeout(abs_py_file: String, timeout: float) -> Dictionary:
	# Предпочитаем create_process, чтобы можно было делать таймаут.
	# Если create_process недоступен в твоей версии, будет fallback на OS.execute.
	if OS.has_method("create_process"):
		return _run_with_process(abs_py_file, timeout)
	else:
		return _run_with_execute(abs_py_file)


func _run_with_execute(abs_py_file: String) -> Dictionary:
	var out_lines: Array = []
	var exit_code := OS.execute(python_cmd, _python_args(abs_py_file), out_lines, true)
	var joined := "\n".join(out_lines)
	# OS.execute не умеет разделять stdout/stderr, поэтому кладём всё в stderr при ошибке
	if exit_code == 0:
		return {"exit_code": exit_code, "stdout": joined, "stderr": "", "timed_out": false}
	return {"exit_code": exit_code, "stdout": "", "stderr": joined, "timed_out": false}


func _run_with_process(abs_py_file: String, timeout: float) -> Dictionary:
	# 1) запускаем процесс
	var pid := OS.create_process(python_cmd, _python_args(abs_py_file), false)
	if pid == 0:
		return {"exit_code": -1, "stdout": "", "stderr": "Failed to start python process", "timed_out": false}

	# 2) ждём завершение или таймаут
	var start := Time.get_ticks_msec()
	while true:
		var status := OS.is_process_running(pid)
		if not status:
			break

		var elapsed := float(Time.get_ticks_msec() - start) / 1000.0
		if elapsed >= timeout:
			OS.kill(pid)
			return {
				"exit_code": -2,
				"stdout": "",
				"stderr": "⏱ Timeout: program exceeded " + str(timeout) + " sec",
				"timed_out": true
			}

		OS.delay_msec(25)

	# 3) на этом этапе процесс завершился, но Godot не даёт stdout/stderr напрямую из create_process.
	# Поэтому используем редирект в файлы через оболочку.
	# Если ты на Windows — проще сразу запускать через cmd /c с редиректом.
	return _run_with_redirect_files(abs_py_file, timeout)


func _run_with_redirect_files(abs_py_file: String, timeout: float) -> Dictionary:
	var abs_tmp_dir := ProjectSettings.globalize_path(tmp_dir)
	var uid := str(Time.get_unix_time_from_system()) + "_" + str(randi())
	var out_path := abs_tmp_dir.rstrip("/\\") + "/out_" + uid + ".txt"
	var err_path := abs_tmp_dir.rstrip("/\\") + "/err_" + uid + ".txt"

	var cmd: String
	var args: Array

	if OS.get_name() == "Windows":
		# cmd /c python file 1>out 2>err
		cmd = "cmd"
		args = ["/c", python_cmd] + _python_args(abs_py_file) + ["1>", out_path, "2>", err_path]
	else:
		# sh -lc 'python file 1>out 2>err'
		cmd = "sh"
		var quoted = _shell_quote(python_cmd) + " " + _shell_quote(abs_py_file) + " 1>" + _shell_quote(out_path) + " 2>" + _shell_quote(err_path)
		args = ["-lc", quoted]

	var out_lines: Array = []
	var exit_code := OS.execute(cmd, args, out_lines, true)

	var stdout_text := _read_text_file(out_path)
	var stderr_text := _read_text_file(err_path)

	_try_delete(out_path)
	_try_delete(err_path)

	return {"exit_code": exit_code, "stdout": stdout_text, "stderr": stderr_text, "timed_out": false}


# ---------------- UTIL ----------------
func _python_args(abs_py_file: String) -> Array:
	# -B не пишет .pyc, -u делает вывод построчным
	return ["-B", "-u", abs_py_file]


func _detect_python_command() -> String:
	# Windows: лучше py -3 (почти всегда есть), fallback python
	if OS.get_name() == "Windows":
		if _can_run("py", ["-3", "--version"]):
			return "py"
		if _can_run("python", ["--version"]):
			return "python"
		return "py"  # последняя попытка

	# Linux/macOS: python3 обычно
	if _can_run("python3", ["--version"]):
		return "python3"
	if _can_run("python", ["--version"]):
		return "python"
	return "python3"


func _can_run(cmd: String, args: Array) -> bool:
	var out: Array = []
	var code := OS.execute(cmd, args, out, true)
	return code == 0


func _sanitize_filename(name: String) -> String:
	var s := name.strip_edges()
	if s == "":
		return "user_code.py"
	# вырежем опасные символы
	var bad := ["..", "/", "\\", ":", "*", "?", "\"", "<", ">", "|"]
	for b in bad:
		s = s.replace(b, "_")
	return s


func _clip_text(s: String, limit: int) -> String:
	if limit <= 0:
		return s
	if s.length() <= limit:
		return s
	return s.substr(0, limit) + "\n... (output clipped) ..."


func _read_text_file(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var t := f.get_as_text()
	f.close()
	return t


func _try_delete(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _shell_quote(s: String) -> String:
	# простая кавычка для sh
	return "'" + s.replace("'", "'\"'\"'") + "'"
