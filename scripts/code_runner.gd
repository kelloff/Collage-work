extends Node

signal run_finished(result : Dictionary)

@export var python_cmd : String = "py"
@export var tmp_dir : String = "res://user_code_tmp"

var thread: Thread = null

func _ready() -> void:
	# Убедимся, что папка существует (используем абсолютный путь)
	var abs_tmp_dir = ProjectSettings.globalize_path(tmp_dir)
	if not DirAccess.dir_exists_absolute(abs_tmp_dir):
		var err = DirAccess.make_dir_recursive_absolute(abs_tmp_dir)
		if err != OK:
			push_error("CodeRunner: cannot create tmp dir: %s (err=%d)" % [abs_tmp_dir, err])

func run_code_async(code_text: String, filename_hint: String = "user_code.py") -> void:
	# Дождёмся предыдущего потока, если он ещё жив
	if thread:
		thread.wait_to_finish()
		thread = null

	thread = Thread.new()
	var callable = Callable(self, "_thread_run_code").bind({"code_text": code_text, "filename_hint": filename_hint})
	thread.start(callable)

func _thread_run_code(args: Dictionary) -> Dictionary:
	var start_time = Time.get_ticks_msec()
	var code_text = args.get("code_text", "")
	var filename_hint = args.get("filename_hint", "user_code.py")

	# Уникальное имя файла
	var uid = str(Time.get_unix_time_from_system()) + "_" + str(randi())

	# Логический (res://) и абсолютный пути
	var base: String
	if tmp_dir.ends_with("/"):
		base = tmp_dir
	else:
		base = tmp_dir + "/"
	var logical_path = base + uid + "_" + filename_hint

	var abs_tmp_dir = ProjectSettings.globalize_path(tmp_dir)
	if not DirAccess.dir_exists_absolute(abs_tmp_dir):
		var err = DirAccess.make_dir_recursive_absolute(abs_tmp_dir)
		if err != OK:
			var err_res_dir = {
				"exit_code": -1,
				"stdout": "",
				"stderr": "Cannot create tmp dir: " + abs_tmp_dir,
				"duration": 0.0,
				"tmp_path": logical_path
			}
			call_deferred("_emit_result", err_res_dir)
			return err_res_dir

	var abs_path = abs_tmp_dir
	if not abs_path.ends_with("/") and not abs_path.ends_with("\\"):
		abs_path += "/"
	abs_path += uid + "_" + filename_hint

	# Запись файла
	var f = FileAccess.open(abs_path, FileAccess.WRITE)
	if f == null:
		var err_res = {
			"exit_code": -1,
			"stdout": "",
			"stderr": "Cannot open temp file: " + abs_path,
			"duration": 0.0,
			"tmp_path": logical_path
		}
		call_deferred("_emit_result", err_res)
		return err_res

	f.store_string(code_text)
	f.close()

	# Выполнение внешнего python с абсолютным путём
	var output_lines: Array = []
	if python_cmd == "" or python_cmd == null:
		var err_res2 = {
			"exit_code": -1,
			"stdout": "",
			"stderr": "python_cmd is empty",
			"duration": 0.0,
			"tmp_path": logical_path
		}
		call_deferred("_emit_result", err_res2)
		return err_res2

	var exit_code = OS.execute(python_cmd, [abs_path], output_lines, true)

	var duration = float(Time.get_ticks_msec() - start_time) / 1000.0
	var joined = "\n".join(output_lines).strip_edges()

	var stdout_text = ""
	var stderr_text = ""
	if exit_code == 0:
		stdout_text = joined
	else:
		stderr_text = joined

	var result = {
		"exit_code": exit_code,
		"stdout": stdout_text,
		"stderr": stderr_text,
		"duration": duration,
		"tmp_path": logical_path,
		"abs_path": abs_path
	}

	call_deferred("_emit_result", result)
	return result

func _emit_result(result: Dictionary) -> void:
	emit_signal("run_finished", result)
	if thread:
		thread = null
