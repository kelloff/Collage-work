extends Control
## Круговой индикатор (правый нижний угол и т.п.)

var _angle := 0.0
@export var speed := 5.0
@export var color := Color(0.35, 1.0, 0.62, 0.95)


func _process(delta: float) -> void:
	_angle += delta * speed
	queue_redraw()


func _draw() -> void:
	var c: Vector2 = size * 0.5
	var r: float = min(size.x, size.y) * 0.38
	draw_arc(c, r, _angle, _angle + TAU * 0.72, 28, color, 3.0, true)
