extends Node
class_name AiChecker

## Если пусто — берётся BackendUrls + /check_task (тот же хост, что и /generate_tasks).
@export var api_url: String = ""
const CHECK_TIMEOUT_S: float = 12.0


func _ready() -> void:
	# Терминал ставит get_tree().paused — без ALWAYS HTTP не завершится до выхода.
	process_mode = Node.PROCESS_MODE_ALWAYS

# Асинхронная проверка решения через Python backend.
# Backend должен принимать JSON:
#   { description, expected_output, user_code }
# и возвращать:
#   { success: bool, feedback: String, stdout: String, stderr: String }
func check_task_async(task: Dictionary, user_code: String, level: int = 1) -> Dictionary:
	var url: String = api_url.strip_edges()
	if url.is_empty():
		url = BackendUrls.url("/check_task")

	var http: HTTPRequest = HTTPRequest.new()
	http.timeout = CHECK_TIMEOUT_S
	http.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(http)

	var payload: Dictionary = {
		"description": str(task.get("description", "")),
		"expected_output": str(task.get("expected_output", "")),
		"user_code": user_code,
		"required_patterns": str(task.get("required_patterns", "")),
		"allow_direct_print": int(task.get("allow_direct_print", 0)),
		"level": level
	}

	var json_body: String = JSON.stringify(payload)
	var headers: PackedStringArray = PackedStringArray([
		"Content-Type: application/json"
	])

	var err: int = http.request(url, headers, HTTPClient.METHOD_POST, json_body)
	if err != OK:
		http.queue_free()
		return {
			"success": false,
			"feedback": "❌ Не удалось отправить запрос на сервер проверки (код %d)" % err,
			"stdout": "",
			"stderr": ""
		}

	var result: Array = await http.request_completed
	http.queue_free()

	if result.size() < 4:
		return {
			"success": false,
			"feedback": "❌ Некорректный ответ от HTTPRequest",
			"stdout": "",
			"stderr": ""
		}

	var request_result: int = int(result[0])
	var status_code: int = int(result[1])
	var body_bytes: PackedByteArray = result[3]
	var response_body: String = body_bytes.get_string_from_utf8()

	if request_result != HTTPRequest.RESULT_SUCCESS:
		var net_msg := "❌ Сервер проверки недоступен/таймаут (result=%d)" % request_result
		if request_result == HTTPRequest.RESULT_TIMEOUT:
			net_msg = "❌ Таймаут проверки. Сервер отвечает слишком долго."
		return {
			"success": false,
			"feedback": net_msg,
			"stdout": "",
			"stderr": response_body
		}

	if status_code != 200:
		return {
			"success": false,
			"feedback": "❌ Ошибка сервера проверки HTTP %d" % status_code,
			"stdout": "",
			"stderr": response_body
		}

	var parsed: Variant = JSON.parse_string(response_body)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {
			"success": false,
			"feedback": "❌ Некорректный JSON от сервера проверки",
			"stdout": "",
			"stderr": response_body
		}

	return {
		"success": bool(parsed.get("success", false)),
		"feedback": str(parsed.get("feedback", "")),
		"stdout": str(parsed.get("stdout", "")),
		"stderr": str(parsed.get("stderr", ""))
	}
