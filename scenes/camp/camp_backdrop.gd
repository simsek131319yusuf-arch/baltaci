extends Control
## Camp scenery. Uses Art "bg/*" layers when present, otherwise a painted-feeling
## placeholder: warm sky, sun, clouds, two hill layers, pine silhouettes, meadow and dirt yard.

const GROUND_FROM_BOTTOM := 200.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func ground_y() -> float:
	return size.y - GROUND_FROM_BOTTOM


func _draw() -> void:
	var gy := ground_y()
	_draw_sky(size.x, gy)
	_draw_hills(size.x, gy)
	_draw_ground(size.x, size.y, gy)


func _draw_sky(w: float, gy: float) -> void:
	var sky := Art.tex("bg/sky")
	if sky != null:
		draw_texture_rect(sky, Rect2(0, 0, w, gy + 40), false)
		return
	var top := Color("7db4c8")
	var mid := Color("cfe0c8")
	var low := Color("f7e2b0")
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, gy * 0.55), Vector2(0, gy * 0.55)]),
		PackedColorArray([top, top, mid, mid]))
	draw_polygon(PackedVector2Array([Vector2(0, gy * 0.55), Vector2(w, gy * 0.55), Vector2(w, gy + 40), Vector2(0, gy + 40)]),
		PackedColorArray([mid, mid, low, low]))
	var sun := Vector2(w * 0.62, gy * 0.42)
	for i in 6:
		draw_circle(sun, 150.0 - i * 20.0, Color(1.0, 0.93, 0.7, 0.07 + i * 0.012))
	draw_circle(sun, 46.0, Color("fff3c4"))
	for c in [[0.12, 0.16, 1.0], [0.42, 0.1, 0.8], [0.8, 0.2, 1.1], [0.26, 0.3, 0.7]]:
		_cloud(Vector2(w * c[0], gy * c[1]), c[2])


func _cloud(p: Vector2, s: float) -> void:
	var col := Color(1, 1, 1, 0.78)
	for part in [[0, 0, 36], [38, 8, 28], [-38, 10, 26], [70, 16, 20], [-68, 18, 18]]:
		draw_circle(p + Vector2(part[0], part[1]) * s, part[2] * s, col)
	draw_rect(Rect2(p + Vector2(-70, 12) * s, Vector2(140, 20) * s), col)


func _hill(w: float, base: float, amp: float, freq: float, phase: float, color: Color) -> void:
	var pts := PackedVector2Array()
	var steps := 48
	for i in steps + 1:
		var x := w * i / steps
		var y := base - amp * (0.55 + 0.45 * sin(x * freq + phase)) - amp * 0.3 * sin(x * freq * 2.3 + phase * 1.7)
		pts.append(Vector2(x, y))
	pts.append(Vector2(w, base + 400))
	pts.append(Vector2(0, base + 400))
	draw_colored_polygon(pts, color)


func _pine(base: Vector2, height: float, color: Color) -> void:
	draw_rect(Rect2(base.x - height * 0.03, base.y - height * 0.2, height * 0.06, height * 0.2), color.darkened(0.45))
	var tiers := 4
	for t in tiers:
		var f := float(t) / tiers
		var y := base.y - height * (0.18 + f * 0.62)
		var half := height * 0.24 * (1.0 - f * 0.7)
		draw_colored_polygon(PackedVector2Array([Vector2(base.x - half, y + height * 0.22), Vector2(base.x + half, y + height * 0.22), Vector2(base.x, y - height * 0.12)]), color)


func _layer(tex: Texture2D, w: float, gy: float, lift: float) -> void:
	var h := tex.get_height() * w / tex.get_width()
	draw_texture_rect(tex, Rect2(0, gy - h + lift, w, h), false)


func _draw_hills(w: float, gy: float) -> void:
	var far := Art.tex("bg/far")
	var mid := Art.tex("bg/mid")
	if far != null:
		_layer(far, w, gy, 30.0)
	else:
		_hill(w, gy - 80, 150, 0.0042, 1.2, Color("8fb59a"))
	if mid != null:
		_layer(mid, w, gy, 20.0)
		return
	_hill(w, gy - 30, 110, 0.0058, 3.1, Color("5f9068"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 26:
		var x := rng.randf_range(0.0, w)
		_pine(Vector2(x, gy - 40 + rng.randf_range(-10.0, 20.0)), rng.randf_range(90.0, 150.0),
			Color("3f7a52").lerp(Color("2d5e44"), rng.randf()))


func _draw_ground(w: float, h: float, gy: float) -> void:
	var ground := Art.tex("bg/ground")
	if ground != null:
		draw_texture_rect(ground, Rect2(0, gy - 20, w, h - gy + 20), false)
		return
	draw_polygon(PackedVector2Array([Vector2(0, gy - 6), Vector2(w, gy - 6), Vector2(w, gy + 26), Vector2(0, gy + 26)]),
		PackedColorArray([Color("7fb04a"), Color("7fb04a"), Color("5f8f3a"), Color("5f8f3a")]))
	draw_rect(Rect2(0, gy + 26, w, 6), Color("4a6f2c"))
	draw_polygon(PackedVector2Array([Vector2(0, gy + 32), Vector2(w, gy + 32), Vector2(w, h), Vector2(0, h)]),
		PackedColorArray([Color("7d5a38"), Color("7d5a38"), Color("523620"), Color("523620")]))
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 40:
		var p := Vector2(rng.randf_range(0.0, w), gy + rng.randf_range(44.0, GROUND_FROM_BOTTOM - 20.0))
		draw_circle(p, rng.randf_range(2.0, 5.0), Color("5e422a"))
	for i in 30:
		var x := rng.randf_range(0.0, w)
		draw_line(Vector2(x, gy + 8), Vector2(x - 3, gy - 6), Color("a8d26a"), 2.0)
		draw_line(Vector2(x, gy + 8), Vector2(x + 4, gy - 4), Color("a8d26a"), 2.0)
	# Foreground pines framing the left edge, and a log pile beside the cat.
	_pine(Vector2(60, gy + 30), 380, Color("2d5e44"))
	_pine(Vector2(150, gy + 22), 270, Color("3f7a52"))
	for i in 3:
		draw_circle(Vector2(560 + i * 34, gy + 56), 18, Color("8a6a4a"))
		draw_circle(Vector2(560 + i * 34, gy + 56), 11, Color("c9a574"))
	draw_circle(Vector2(577, gy + 24), 18, Color("8a6a4a"))
	draw_circle(Vector2(577, gy + 24), 11, Color("c9a574"))
