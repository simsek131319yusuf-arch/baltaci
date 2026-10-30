extends Node2D
## Parallax backdrop: sky, sun, clouds, two hill bands, pine silhouettes, ground.
## Uses Art "bg/*" layers when they exist, otherwise draws a procedural placeholder.

const VIEW := Vector2(1600, 900)
const TILE := 1600.0
const HAZE_SHADER := """
shader_type canvas_item;
uniform vec4 haze : source_color = vec4(0.74, 0.86, 0.92, 1.0);
uniform float amount : hint_range(0.0, 1.0) = 0.5;
uniform float desat : hint_range(0.0, 1.0) = 0.3;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float g = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	vec3 rgb = mix(c.rgb, vec3(g), desat);
	rgb = mix(rgb, haze.rgb, amount);
	COLOR = vec4(rgb, c.a);
}
"""

# Depth layers (atmospheric perspective): further = slower, smaller, hazier.
@export_group("Depth")
@export var far_parallax: float = 0.04
@export var far_scale: float = 0.78
@export var far_bottom: float = 640.0
@export var far_haze: float = 0.62
@export var mid_parallax: float = 0.11
@export var mid_scale: float = 0.5
@export var mid_bottom: float = 722.0   # tucked behind the ground band
@export var mid_haze: float = 0.42
@export var mid_desat: float = 0.4

var cam_x: float = 0.0
var ground_y: float = 760.0

var _t: float = 0.0
var _pines: Array = []   # [x, height, width, shade]
var _tufts: Array = []   # [x, y, size]
var _clouds: Array = []  # [x, y, scale, speed]
var _far: Node2D
var _mid: Node2D
var _ground: Node2D
var _shake_off := Vector2.ZERO


func _ready() -> void:
	_far = _make_layer(far_haze, 0.3)
	_far.draw.connect(_draw_far)
	_mid = _make_layer(mid_haze, mid_desat)
	_mid.draw.connect(_draw_mid)
	_ground = Node2D.new()
	add_child(_ground)
	_ground.draw.connect(_draw_ground)
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	for i in 46:
		_pines.append([rng.randf() * TILE, rng.randf_range(110.0, 230.0), rng.randf_range(0.3, 0.42), rng.randf()])
	_pines.sort_custom(func(a, b): return a[3] < b[3])
	for i in 70:
		_tufts.append([rng.randf() * TILE, rng.randf_range(ground_y + 14.0, VIEW.y - 8.0), rng.randf_range(6.0, 14.0)])
	for i in 6:
		_clouds.append([rng.randf() * 2000.0, rng.randf_range(70.0, 280.0), rng.randf_range(0.8, 1.6), rng.randf_range(6.0, 16.0)])


func _make_layer(haze_amount: float, desat: float) -> Node2D:
	var n := Node2D.new()
	var sh := Shader.new()
	sh.code = HAZE_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("amount", haze_amount)
	m.set_shader_parameter("desat", desat)
	n.material = m
	add_child(n)
	return n


## Camera x for parallax, plus the screen-shake offset so the ground shakes with the trees.
func set_cam(x: float, shake: Vector2 = Vector2.ZERO) -> void:
	cam_x = x
	_shake_off = shake
	queue_redraw()
	if _far:
		_far.queue_redraw()
		_mid.queue_redraw()
		_ground.queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	_draw_sky()
	var have_art := Art.has("bg/mid") and Art.has("bg/far")
	if not have_art:
		# Placeholder scenery only when the painted layers are missing.
		_draw_hills(0.1, ground_y - 230.0, 55.0, Color("#a9cbb4"), 0.0, [2, 5, 9])
		_draw_hills(0.22, ground_y - 130.0, 45.0, Color("#79ab8a"), 1.7, [3, 7, 11])
		_draw_pines(0.42)


func _draw_far() -> void:
	var tex := Art.tex("bg/far")
	if tex:
		_draw_layer(_far, tex, far_parallax, far_scale, far_bottom)


func _draw_mid() -> void:
	var tex := Art.tex("bg/mid")
	if tex:
		_draw_layer(_mid, tex, mid_parallax, mid_scale, mid_bottom)


## Tiles `tex` horizontally at `sc`, bottom edge at `bottom_y`, scrolling at `factor` x camera.
func _draw_layer(node: Node2D, tex: Texture2D, factor: float, sc: float, bottom_y: float) -> void:
	var w := float(tex.get_width()) * sc
	var h := float(tex.get_height()) * sc
	var off := fposmod(cam_x * factor, w)
	var x := -off
	var y := bottom_y - h
	while x < VIEW.x:
		node.draw_texture_rect(tex, Rect2(x, y, w + 1.0, h), false)
		x += w


func _draw_sky() -> void:
	var sky := Art.tex("bg/sky")
	if sky:
		draw_texture_rect(sky, Rect2(Vector2.ZERO, VIEW), false)
		return
	var top := Color("#7cc3e6")
	var mid := Color("#bfe3ee")
	var low := Color("#f7e8c0")
	var split := ground_y * 0.55
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(VIEW.x, 0), Vector2(VIEW.x, split), Vector2(0, split)]),
		PackedColorArray([top, top, mid, mid]))
	draw_polygon(PackedVector2Array([Vector2(0, split), Vector2(VIEW.x, split), Vector2(VIEW.x, ground_y), Vector2(0, ground_y)]),
		PackedColorArray([mid, mid, low, low]))
	var sun := Vector2(1180.0 - cam_x * 0.02, 190.0)
	for i in 4:
		draw_circle(sun, 150.0 - 30.0 * i, Color(1.0, 0.95, 0.75, 0.07 + 0.05 * i))
	draw_circle(sun, 62.0, Color("#fff4c9"))
	for c in _clouds:
		var cx := fposmod(c[0] + _t * c[3] - cam_x * 0.05, VIEW.x + 500.0) - 250.0
		_cloud(Vector2(cx, c[1]), c[2])


func _cloud(p: Vector2, s: float) -> void:
	var col := Color(1, 1, 1, 0.82)
	draw_set_transform(p, 0.0, Vector2(1.0, 0.55))
	draw_circle(Vector2(-46, 0) * s, 38.0 * s, col)
	draw_circle(Vector2(0, -14) * s, 50.0 * s, col)
	draw_circle(Vector2(52, 2) * s, 36.0 * s, col)
	draw_circle(Vector2(8, 12) * s, 42.0 * s, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_hills(factor: float, base_y: float, amp: float, col: Color, phase: float, ks: Array) -> void:
	var pts := PackedVector2Array()
	var off := cam_x * factor
	var x := 0.0
	while x <= VIEW.x + 40.0:
		var p := (x + off) / TILE * TAU
		var y := base_y
		y -= amp * 0.55 * sin(float(ks[0]) * p + phase)
		y -= amp * 0.3 * sin(float(ks[1]) * p + phase * 2.0 + 1.0)
		y -= amp * 0.15 * sin(float(ks[2]) * p + 2.0)
		pts.append(Vector2(x, y))
		x += 40.0
	pts.append(Vector2(VIEW.x + 40.0, ground_y))
	pts.append(Vector2(0, ground_y))
	draw_colored_polygon(pts, col)


func _draw_pines(factor: float) -> void:
	var off := fposmod(cam_x * factor, TILE)
	var base := ground_y - 4.0
	for p in _pines:
		for wrap in 2:
			var sx: float = fposmod(p[0] - off, TILE) - float(wrap) * TILE
			if sx < -120.0 or sx > VIEW.x + 120.0:
				continue
			var h: float = p[1]
			var w: float = h * p[2]
			var col := Color("#3f6f52").lerp(Color("#2f5a45"), p[3])
			draw_rect(Rect2(sx - 3, base - h * 0.2, 6, h * 0.2), col.darkened(0.3))
			for layer in 3:
				var by := base - h * 0.2 - float(layer) * h * 0.26
				var half := w * (1.0 - 0.25 * layer)
				draw_colored_polygon(PackedVector2Array([Vector2(sx - half, by), Vector2(sx, by - h * 0.42), Vector2(sx + half, by)]), col)


func _draw_ground() -> void:
	var n := _ground
	var tex := Art.tex("bg/ground")
	if tex:
		# Soil colour underneath so the shaken ground never reveals a gap at the bottom edge.
		n.draw_rect(Rect2(0, VIEW.y - 40.0, VIEW.x, 80.0), Color("#6b4128"))
		_draw_tiled(n, tex, 1.0, VIEW.y + _shake_off.y, _shake_off.x)
		return
	var top := Color("#86b24e")
	var bot := Color("#4f6f34")
	var gy := ground_y - 10.0
	n.draw_polygon(PackedVector2Array([Vector2(0, gy), Vector2(VIEW.x, gy), Vector2(VIEW.x, VIEW.y), Vector2(0, VIEW.y)]),
		PackedColorArray([top, top, bot, bot]))
	n.draw_rect(Rect2(0, gy, VIEW.x, 5), Color("#a6cc63"))
	n.draw_rect(Rect2(0, gy + 5, VIEW.x, 4), Color("#6d9640"))
	var off := fposmod(cam_x, TILE)
	for t in _tufts:
		var sx: float = fposmod(t[0] - off, TILE)
		if sx > VIEW.x + 20.0:
			continue
		var s: float = t[2]
		var y: float = t[1]
		var c := Color("#5f8a3a").lerp(Color("#3e5b28"), (y - ground_y) / (VIEW.y - ground_y))
		for k in 3:
			var dx := (k - 1) * s * 0.5
			n.draw_colored_polygon(PackedVector2Array([Vector2(sx + dx - 2, y), Vector2(sx + dx + 2, y), Vector2(sx + dx * 1.6, y - s * (0.9 + 0.3 * k))]), c)


func _draw_tiled(n: Node2D, tex: Texture2D, factor: float, bottom_y: float, x_shift: float = 0.0) -> void:
	var w := float(tex.get_width())
	var h := float(tex.get_height())
	var off := fposmod(cam_x * factor - x_shift, w)
	var x := -off
	while x < VIEW.x:
		n.draw_texture(tex, Vector2(x, bottom_y - h))
		x += w
