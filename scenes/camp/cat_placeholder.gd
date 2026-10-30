extends Control
## Painted-style lumberjack cat drawn in code; used until Art provides "cat/idle".

const FUR := Color("d98a3d")
const FUR_DARK := Color("a8621f")
const BELLY := Color("f3d9a8")
const SHIRT := Color("b5482f")
const SHIRT_DARK := Color("7e2e1d")


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ellipse(center: Vector2, radii: Vector2, color: Color) -> void:
	draw_set_transform(center, 0.0, radii)
	draw_circle(Vector2.ZERO, 1.0, color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw() -> void:
	var o := Vector2(size.x * 0.5, size.y)   # bottom-center
	_ellipse(o + Vector2(0, -6), Vector2(110, 18), Color(0, 0, 0, 0.22))
	# Tail
	var tail := PackedVector2Array()
	for i in 14:
		var t := float(i) / 13.0
		tail.append(o + Vector2(70 + sin(t * 3.0) * 26 + t * 36, -70 - t * 110))
	draw_polyline(tail, FUR_DARK, 20.0, true)
	draw_polyline(tail, FUR, 14.0, true)
	# Axe leaning on the right
	draw_line(o + Vector2(120, -10), o + Vector2(96, -190), Color("7a5232"), 9.0)
	draw_colored_polygon(PackedVector2Array([o + Vector2(92, -196), o + Vector2(52, -208), o + Vector2(54, -150), o + Vector2(94, -160)]), Color("aab4b8"))
	# Body (plaid shirt)
	_ellipse(o + Vector2(0, -78), Vector2(66, 74), SHIRT_DARK)
	_ellipse(o + Vector2(0, -80), Vector2(62, 70), SHIRT)
	for k in range(-2, 3):
		draw_line(o + Vector2(k * 22, -140), o + Vector2(k * 22, -22), SHIRT_DARK, 4.0)
	draw_line(o + Vector2(-56, -90), o + Vector2(56, -90), SHIRT_DARK, 4.0)
	draw_line(o + Vector2(-60, -60), o + Vector2(60, -60), SHIRT_DARK, 4.0)
	# Feet
	_ellipse(o + Vector2(-30, -10), Vector2(26, 14), FUR_DARK)
	_ellipse(o + Vector2(30, -10), Vector2(26, 14), FUR_DARK)
	# Arm
	_ellipse(o + Vector2(66, -86), Vector2(15, 36), FUR)
	# Head
	var h := o + Vector2(0, -176)
	draw_colored_polygon(PackedVector2Array([h + Vector2(-58, -22), h + Vector2(-44, -76), h + Vector2(-14, -48)]), FUR_DARK)
	draw_colored_polygon(PackedVector2Array([h + Vector2(58, -22), h + Vector2(14, -48), h + Vector2(44, -76)]), FUR_DARK)
	draw_colored_polygon(PackedVector2Array([h + Vector2(-48, -30), h + Vector2(-42, -62), h + Vector2(-22, -44)]), Color("e7a9a0"))
	draw_colored_polygon(PackedVector2Array([h + Vector2(48, -30), h + Vector2(22, -44), h + Vector2(42, -62)]), Color("e7a9a0"))
	_ellipse(h, Vector2(64, 54), FUR_DARK)
	_ellipse(h + Vector2(0, -2), Vector2(61, 51), FUR)
	_ellipse(h + Vector2(0, 20), Vector2(30, 22), BELLY)
	# Eyes, nose, whiskers
	for s in [-1, 1]:
		_ellipse(h + Vector2(s * 24, -6), Vector2(8, 10), Color("1d130c"))
		draw_circle(h + Vector2(s * 24 + 2, -10), 2.5, Color.WHITE)
		draw_line(h + Vector2(s * 34, 16), h + Vector2(s * 70, 8), Color(1, 1, 1, 0.8), 2.0)
		draw_line(h + Vector2(s * 34, 22), h + Vector2(s * 70, 26), Color(1, 1, 1, 0.8), 2.0)
	draw_colored_polygon(PackedVector2Array([h + Vector2(-6, 8), h + Vector2(6, 8), h + Vector2(0, 16)]), Color("c4584a"))
	draw_arc(h + Vector2(-8, 18), 8, 0.2, PI * 0.8, 8, Color("5a3a22"), 2.0)
	draw_arc(h + Vector2(8, 18), 8, PI * 0.2, PI * 0.8, 8, Color("5a3a22"), 2.0)
	# Beanie
	draw_colored_polygon(PackedVector2Array([h + Vector2(-58, -28), h + Vector2(-40, -62), h + Vector2(0, -74), h + Vector2(40, -62), h + Vector2(58, -28), h + Vector2(0, -38)]), Color("3f6b26"))
	draw_rect(Rect2(h + Vector2(-58, -34), Vector2(116, 12)), Color("6aa13f"))
