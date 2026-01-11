extends Node

signal run_finished(result : Dictionary)

@export var python_cmd : String = "C:/Program Files/Python312/python.exe"
@export var tmp_dir : String = "user_code_tmp"

var thread: Thread = null

func _ready():
	if not DirAccess.dir_exists_absolute(tmp_dir):
		DirAccess.make_dir_recursive_absolute(tmp_dir)

func run_code_async(code_text: String, filename_hint: String = "user_code.py") -> void:
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

	var uid = str(Time.get_unix_time_from_system()) + "_" + str(randi())
	var tmp_path = tmp_dir + "/" + uid + "_" + filename_hint

	var f = FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		return {
			"exit_code": -1,
			"stdout": "",
			"stderr": "Cannot open temp file",
			"duration": 0.0,
			"tmp_path": tmp_path
		}
	f.store_string(code_text)
	f.close()

	var output_lines: Array = []
	# СИНХРОННЫЙ запуск — ждём завершения и собираем весь stdout/stderr
	var exit_code = OS.execute("cmd.exe", ["/C", python_cmd, tmp_path], output_lines, true)

	var duration = float(Time.get_ticks_msec() - start_time) / 1000.0
	var joined = "\n".join(output_lines).strip_edges()

	var stdout_text = joined if exit_code == 0 else ""
	var stderr_text = "" if exit_code == 0 else joined

	var result = {
		"exit_code": exit_code,
		"stdout": stdout_text,
		"stderr": stderr_text,
		"duration": duration,
		"tmp_path": tmp_path
	}

	call_deferred("_emit_result", result)
	return result

func _emit_result(result: Dictionary) -> void:
	emit_signal("run_finished", result)
	if thread:
		thread = null
