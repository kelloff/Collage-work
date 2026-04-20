extends Node
## База URL HTTP API без слэша в конце.
## Продакшен: kellofff.me. Локально: задайте COLLAGE_BACKEND_URL=http://127.0.0.1:8000

var base_url: String = "https://kellofff.me"


func _ready() -> void:
	var e := OS.get_environment("COLLAGE_BACKEND_URL").strip_edges()
	if e != "":
		base_url = e.trim_suffix("/")


func url(path: String) -> String:
	if path.begins_with("/"):
		return base_url + path
	return base_url + "/" + path
