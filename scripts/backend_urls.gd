extends Node
## База URL HTTP API без слэша в конце.
## Продакшен: kellofff.me. Локально: COLLAGE_BACKEND_URL=http://127.0.0.1:8000
## Принудительный офлайн: COLLAGE_OFFLINE=1

var base_url: String = "https://kellofff.me"
## Кэш: можно ли ходить на backend (обновляется probe_backend_async).
var server_reachable: bool = true

var _last_probe_unix: int = 0
const PROBE_CACHE_SEC: int = 45
const PROBE_TIMEOUT_S: float = 4.0


func _ready() -> void:
	var e := OS.get_environment("COLLAGE_BACKEND_URL").strip_edges()
	if e != "":
		base_url = e.trim_suffix("/")
	var off := OS.get_environment("COLLAGE_OFFLINE").strip_edges().to_lower()
	if off in ["1", "true", "yes", "on"]:
		server_reachable = false


func url(path: String) -> String:
	if path.begins_with("/"):
		return base_url + path
	return base_url + "/" + path


func is_server_likely_online() -> bool:
	return server_reachable


func mark_server_offline() -> void:
	server_reachable = false
	_last_probe_unix = Time.get_unix_time_from_system()


func mark_server_online() -> void:
	server_reachable = true
	_last_probe_unix = Time.get_unix_time_from_system()


## Быстрый GET /health. Возвращает true, если сервер ответил 200.
func probe_backend_async(timeout_sec: float = PROBE_TIMEOUT_S, force: bool = false) -> bool:
	if not force:
		var now := int(Time.get_unix_time_from_system())
		if now - _last_probe_unix < PROBE_CACHE_SEC:
			return server_reachable

	if not is_inside_tree():
		return false

	var http := HTTPRequest.new()
	http.timeout = timeout_sec
	http.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(http)

	var health_url := url("/health")
	var err := http.request(health_url, PackedStringArray(), HTTPClient.METHOD_GET)
	if err != OK:
		http.queue_free()
		mark_server_offline()
		return false

	var result: Array = await http.request_completed
	http.queue_free()

	if result.size() < 4:
		mark_server_offline()
		return false

	var request_result: int = int(result[0])
	var status_code: int = int(result[1])
	var ok := request_result == HTTPRequest.RESULT_SUCCESS and status_code == 200
	if ok:
		mark_server_online()
	else:
		mark_server_offline()
	return ok
