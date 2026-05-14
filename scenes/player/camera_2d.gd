extends Camera2D

const BASE_RESOLUTION := Vector2(1920, 1080)

func _ready():
	update_zoom()

func _notification(what):
	if what == NOTIFICATION_WM_SIZE_CHANGED:
		update_zoom()

func update_zoom():
	var window_size = DisplayServer.window_get_size()

	var scale_x = window_size.x / BASE_RESOLUTION.x
	var scale_y = window_size.y / BASE_RESOLUTION.y
	var scale = min(scale_x, scale_y)

	zoom = Vector2(1.0 / scale, 1.0 / scale)
