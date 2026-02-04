extends Node
class_name AudioManager

var music_volume: float = 0.8 # 0.0 .. 1.0

func _ready():
	_apply_music_volume()

func set_music_volume(value: float) -> void:
	music_volume = clamp(value, 0.0, 1.0)
	_apply_music_volume()

func _apply_music_volume() -> void:
	var db := linear_to_db(music_volume)
	AudioServer.set_bus_volume_db(
		AudioServer.get_bus_index("Music"),
		db
	)
