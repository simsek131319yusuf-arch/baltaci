extends Control
## Tiny drawn placeholder icon used when Art has no sprite yet. kind: coin | chain | runs.

@export var kind: String = "coin"
@export var icon_size: float = 32.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	custom_minimum_size = Vector2(icon_size, icon_size)


func _draw() -> void:
	var c := Vector2(icon_size, icon_size) * 0.5
	var r := icon_size * 0.44
	match kind:
		"coin":
			draw_circle(c, r, Color("a8741a"))
			draw_circle(c, r * 0.86, Color("f2c14e"))
			draw_arc(c, r * 0.58, 0.0, TAU, 24, Color("c08a22"), 2.0)
			draw_circle(c + Vector2(-r * 0.3, -r * 0.3), r * 0.14, Color(1, 1, 1, 0.6))
		"chain":
			draw_arc(c + Vector2(-r * 0.35, 0), r * 0.55, 0.0, TAU, 20, Color("cfd6d0"), 4.0)
			draw_arc(c + Vector2(r * 0.35, 0), r * 0.55, 0.0, TAU, 20, Color("9aa59e"), 4.0)
		_:
			draw_circle(c, r, Color("6aa13f"))
			draw_circle(c, r * 0.78, Color("2b1d14"))
			draw_line(c, c + Vector2(0, -r * 0.55), Color("f6ead0"), 2.5)
			draw_line(c, c + Vector2(r * 0.4, 0), Color("f6ead0"), 2.5)
