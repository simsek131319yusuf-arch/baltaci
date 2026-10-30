extends Control
## Pooled coin particles that fly along a curved path from one point to another and accelerate
## into the target (ease-in). One node draws the whole pool; nothing is allocated per frame.
##   burst(from_global, to_global, count)   ->  emits `arrived` once per coin that lands.

signal arrived

const Juice := preload("res://scenes/ui/juice.gd")
const CAP := 28

@export var flight_time: float = 0.62
@export var coin_px: float = 30.0

var _a := PackedVector2Array()
var _b := PackedVector2Array()
var _c := PackedVector2Array()     # bezier control point
var _t := PackedFloat32Array()     # < 0 = waiting (delay), 0..1 = flying
var _on := PackedByteArray()
var _spin := PackedFloat32Array()
var _tex: Texture2D
var _live := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_a.resize(CAP); _b.resize(CAP); _c.resize(CAP); _t.resize(CAP); _on.resize(CAP); _spin.resize(CAP)
	_tex = Art.tex("ui/coin")
	set_process(false)


## `lift` scales the upward bow of the flight path (1 = tossed up, lower = flatter, for downward flights).
func burst(from_global: Vector2, to_global: Vector2, count: int, lift: float = 1.0) -> void:
	var inv := get_global_transform_with_canvas().affine_inverse()
	var a := inv * from_global
	var b := inv * to_global
	var n := 0
	for i in CAP:
		if n >= count:
			break
		if _on[i] != 0:
			continue
		n += 1
		_on[i] = 1
		_a[i] = a + Vector2(randf_range(-14, 14), randf_range(-8, 8))
		_b[i] = b
		var mid := (a + b) * 0.5
		_c[i] = mid + Vector2(randf_range(-120.0, 120.0) * (1.4 - 0.4 * lift), -randf_range(90.0, 200.0) * lift)
		_t[i] = -0.05 * float(n)   # staggered take-off
		_spin[i] = randf_range(-6.0, 6.0)
		_live += 1
	set_process(true)


func _process(delta: float) -> void:
	for i in CAP:
		if _on[i] == 0:
			continue
		_t[i] += delta / flight_time
		if _t[i] >= 1.0:
			_on[i] = 0
			_live -= 1
			arrived.emit()
	if _live <= 0:
		set_process(false)
	queue_redraw()


func _draw() -> void:
	for i in CAP:
		if _on[i] == 0 or _t[i] < 0.0:
			continue
		var k := Juice.in_cubic(_t[i])          # accelerates towards the target
		var p := _a[i].lerp(_c[i], k).lerp(_c[i].lerp(_b[i], k), k)   # quadratic bezier
		var sc := lerpf(1.0, 0.55, _t[i]) * (0.7 + 0.3 * Juice.out_back(clampf(_t[i] * 5.0, 0.0, 1.0)))
		var half := coin_px * 0.5 * sc
		var squeeze := absf(cos(_t[i] * _spin[i] * 3.0))      # coin flip
		draw_set_transform(p, 0.0, Vector2(0.35 + 0.65 * squeeze, 1.0))
		if _tex != null:
			draw_texture_rect(_tex, Rect2(-half, -half, half * 2.0, half * 2.0), false)
		else:
			draw_circle(Vector2.ZERO, half, Color("#ffd35a"))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
