extends Control
## Анимированный фон экрана загрузки (градиент + «частицы»).

var _t: float = 0.0

const _BASE_TOP := Color(0.05, 0.07, 0.14, 1.0)
const _BASE_BOT := Color(0.02, 0.03, 0.08, 1.0)
const _GLOW_A := Color(0.9, 0.28, 0.22, 0.14)
const _GLOW_B := Color(0.2, 0.85, 0.55, 0.1)
const _GLOW_C := Color(0.35, 0.45, 0.95, 0.08)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	if w < 1.0 or h < 1.0:
		return

	# Вертикальный градиент
	var steps := 24
	for i in range(steps):
		var t0 := float(i) / float(steps)
		var t1 := float(i + 1) / float(steps)
		var c := _BASE_TOP.lerp(_BASE_BOT, (t0 + t1) * 0.5)
		var y0 := t0 * h
		var y1 := t1 * h
		draw_rect(Rect2(0.0, y0, w, y1 - y0 + 1.0), c)

	# Мягкие «орбы»
	var pulse := 0.5 + 0.5 * sin(_t * 0.7)
	_draw_glow(Vector2(w * 0.18, h * 0.32 + sin(_t * 0.4) * 24.0), w * 0.42, _GLOW_A, pulse)
	_draw_glow(Vector2(w * 0.82, h * 0.55 + cos(_t * 0.35) * 20.0), w * 0.38, _GLOW_B, 1.0 - pulse * 0.35)
	_draw_glow(Vector2(w * 0.5, h * 0.88), w * 0.55, _GLOW_C, 0.65 + pulse * 0.2)

	# Сетка «терминала»
	var grid_col := Color(0.35, 0.55, 0.95, 0.04)
	var grid_step := 48.0
	var off := fmod(_t * 12.0, grid_step)
	var x := -grid_step + off
	while x < w + grid_step:
		draw_line(Vector2(x, 0.0), Vector2(x, h), grid_col, 1.0)
		x += grid_step
	var y := -grid_step + off * 0.6
	while y < h + grid_step:
		draw_line(Vector2(0.0, y), Vector2(w, y), grid_col, 1.0)
		y += grid_step

	# Плавающие точки
	var n := 28
	for i in range(n):
		var fi := float(i)
		var px := fmod(fi * 137.5 + _t * (12.0 + fi * 0.3), w + 40.0) - 20.0
		var py := fmod(fi * 89.3 + _t * (8.0 + fi * 0.2), h + 40.0) - 20.0
		var a := 0.08 + 0.12 * (0.5 + 0.5 * sin(_t * 1.1 + fi))
		var dot_c := Color(0.9, 0.95, 1.0, a)
		if i % 5 == 0:
			dot_c = Color(1.0, 0.75, 0.35, a * 1.4)
		draw_circle(Vector2(px, py), 1.5 + (fi * 0.07), dot_c)

	# Виньетка по краям
	var vig := Color(0.0, 0.0, 0.0, 0.35)
	draw_rect(Rect2(0.0, 0.0, w, h * 0.12), vig)
	draw_rect(Rect2(0.0, h * 0.88, w, h * 0.12), Color(0.0, 0.0, 0.0, 0.5))


func _draw_glow(center: Vector2, radius: float, col: Color, strength: float) -> void:
	var rings := 6
	for i in range(rings):
		var t := float(i) / float(rings)
		var r := radius * (0.35 + t * 0.95)
		var c := col
		c.a *= strength * (1.0 - t) * 0.55
		draw_circle(center, r, c)
