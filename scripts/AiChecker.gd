extends Node
class_name AiChecker

@export var api_url: String = "http://127.0.0.1:8000/check_task"

# Асинхронная проверка решения через Python backend.
# Backend должен принимать JSON:
#   { description, expected_output, user_code }
# и возвращать:
#   { success: bool, feedback: String, stdout: String, stderr: String }
func check_task_async(task: Dictionary, user_code: String) -> Dictionary:
	var http: HTTPRequest = HTTPRequest.new()
	add_child(http)

	var payload: Dictionary = {
		"description": str(task.get("description", "")),
		"expected_output": str(task.get("expected_output", "")),
		"user_code": user_code,
		"required_patterns": str(task.get("required_patterns", ""))
	}

	var json_body: String = JSON.stringify(payload)
	var headers: PackedStringArray = PackedStringArray([
		"Content-Type: application/json"
	])

	var err: int = http.request(api_url, headers, HTTPClient.METHOD_POST, json_body)
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

	var status_code: int = int(result[1])
	var body_bytes: PackedByteArray = result[3]
	var response_body: String = body_bytes.get_string_from_utf8()

	if status_code != 200:
		return {
			"success": false,
			"feedback": "❌ Ошибка сервера проверки (%d)" % status_code,
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
