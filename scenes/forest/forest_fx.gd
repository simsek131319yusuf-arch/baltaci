extends Node2D
## Pooled world-space effects: chips, drifting leaves, soft dust, log pops and floating damage
## numbers. Everything lives in fixed struct-of-arrays pools and is drawn from one _draw(),
## so a hit or a felling allocates nothing per frame. Driven by tick(dt) from the forest
## (dt is already hit-stop scaled, so effects freeze together with the axe and trees).

enum Kind { CHIP, LEAF, DUST, LOG }

const CAP := 360
const NUM_CAP := 32

@export var gravity: float = 1100.0
@export var floor_offset: float = 14.0       # chips/logs rest this far below the root line

var ground_y: float = 760.0

# --- particle pool -----------------------------------------------------------
var _kind := PackedByteArray()
var _px := PackedFloat32Array()
var _py := PackedFloat32Array()
var _vx := PackedFloat32Array()
var _vy := PackedFloat32Array()
var _rot := PackedFloat32Array()
var _vr := PackedFloat32Array()
var _age := PackedFloat32Array()
var _life := PackedFloat32Array()   # <= 0 means free
var _size := PackedFloat32Array()
var _ph := PackedFloat32Array()     # phase / extra
var _delay := PackedFloat32Array()
var _bounces := PackedByteArray()
var _next := 0

# --- damage numbers ----------------------------------------------------------
var _n_text := PackedStringArray()
var _n_pos := PackedVector2Array()
var _n_vx := PackedFloat32Array()
var _n_age := PackedFloat32Array()
var _n_life := PackedFloat32Array()
var _n_kind := PackedByteArray()     # 0 normal, 1 crit, 2 secondary
var _n_half := PackedFloat32Array()  # half text width at its font size
var _n_rot := PackedFloat32Array()
var _n_next := 0

var _chip: Texture2D
var _leaf: Texture2D
var _logt: Texture2D
var _soft: Texture2D
var _font: Font
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_kind.resize(CAP); _px.resize(CAP); _py.resize(CAP); _vx.resize(CAP); _vy.resize(CAP)
	_rot.resize(CAP); _vr.resize(CAP); _age.resize(CAP); _life.resize(CAP); _size.resize(CAP)
	_ph.resize(CAP); _delay.resize(CAP); _bounces.resize(CAP)
	_n_text.resize(NUM_CAP); _n_pos.resize(NUM_CAP); _n_vx.resize(NUM_CAP); _n_age.resize(NUM_CAP)
	_n_life.resize(NUM_CAP); _n_kind.resize(NUM_CAP); _n_half.resize(NUM_CAP); _n_rot.resize(NUM_CAP)
	_rng.seed = 90210
	_chip = Art.tex("fx/chip")
	_leaf = Art.tex("fx/leaf")
	_logt = Art.tex("fx/log")
	_font = ThemeDB.fallback_font
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 64
	gt.height = 64
	_soft = gt


func _slot() -> int:
	for i in CAP:
		var k := (_next + i) % CAP
		if _life[k] <= 0.0:
			_next = (k + 1) % CAP
			return k
	var k2 := _next
	_next = (_next + 1) % CAP
	return k2


func _emit(kind: int, pos: Vector2, vel: Vector2, life: float, size: float, rot: float = 0.0, vr: float = 0.0, ph: float = 0.0, delay: float = 0.0) -> void:
	var i := _slot()
	_kind[i] = kind
	_px[i] = pos.x
	_py[i] = pos.y
	_vx[i] = vel.x
	_vy[i] = vel.y
	_rot[i] = rot
	_vr[i] = vr
	_age[i] = 0.0
	_life[i] = life
	_size[i] = size
	_ph[i] = ph
	_delay[i] = delay
	_bounces[i] = 0


# --- spawners ----------------------------------------------------------------

func chips(pos: Vector2, side: int, count: int) -> void:
	for n in count:
		var ang := deg_to_rad(_rng.randf_range(-52.0, 52.0))
		var spd := _rng.randf_range(170.0, 380.0)
		var v := Vector2(float(side) * cos(ang) * spd, -absf(sin(ang)) * spd * 0.9 - 90.0)
		_emit(Kind.CHIP, pos, v, _rng.randf_range(0.55, 0.85), _rng.randf_range(0.45, 0.8),
			_rng.randf() * TAU, _rng.randf_range(-12.0, 12.0))


func leaves(pos: Vector2, spread: float, count: int) -> void:
	for n in count:
		var p := pos + Vector2(_rng.randf_range(-spread, spread), _rng.randf_range(-spread * 0.4, spread * 0.4))
		_emit(Kind.LEAF, p, Vector2(_rng.randf_range(-30.0, 30.0), _rng.randf_range(-20.0, 20.0)),
			_rng.randf_range(1.4, 2.4), _rng.randf_range(0.5, 0.9), _rng.randf() * TAU,
			_rng.randf_range(-2.0, 2.0), _rng.randf() * TAU)


## Soft dust puffs along a trunk lying on the ground from `root` towards `dir`.
func dust_line(root: Vector2, dir: int, length: float, count: int) -> void:
	for n in count:
		var k := (float(n) + _rng.randf()) / float(count)
		var p := root + Vector2(float(dir) * length * k, _rng.randf_range(-4.0, 6.0))
		var v := Vector2(float(dir) * _rng.randf_range(10.0, 50.0), _rng.randf_range(-70.0, -25.0))
		_emit(Kind.DUST, p, v, _rng.randf_range(0.7, 1.1), _rng.randf_range(28.0, 52.0),
			0.0, 0.0, _rng.randf_range(0.0, 1.0), (1.0 - k) * 0.07)


func log_pop(pos: Vector2, dir: int) -> void:
	_emit(Kind.LOG, pos, Vector2(float(dir) * _rng.randf_range(30.0, 90.0), _rng.randf_range(-430.0, -340.0)),
		1.35, 0.5, _rng.randf_range(-0.4, 0.4), float(dir) * _rng.randf_range(3.0, 6.0))


## Floating damage number. kind: 0 normal, 1 crit, 2 secondary (fall damage).
func number(pos: Vector2, text: String, kind: int) -> void:
	if _n_text.is_empty():
		return
	var i := _n_next
	_n_next = (_n_next + 1) % NUM_CAP
	_n_text[i] = text
	_n_pos[i] = pos
	_n_vx[i] = _rng.randf_range(-22.0, 22.0)
	_n_age[i] = 0.0
	_n_life[i] = 1.05 if kind == 1 else 0.85
	_n_kind[i] = kind
	_n_rot[i] = _rng.randf_range(-0.12, 0.12) if kind == 1 else _rng.randf_range(-0.05, 0.05)
	_n_half[i] = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, _num_font_size(kind)).x * 0.5


static func _num_font_size(kind: int) -> int:
	return 60 if kind == 1 else (26 if kind == 2 else 38)


func active_count() -> int:
	var n := 0
	for i in _life.size():
		if _life[i] > 0.0:
			n += 1
	return n


# --- simulation --------------------------------------------------------------

func tick(dt: float) -> void:
	if _life.is_empty():
		return
	var floor_y := ground_y + floor_offset
	var any := false
	for i in CAP:
		if _life[i] <= 0.0:
			continue
		any = true
		if _delay[i] > 0.0:
			_delay[i] -= dt
			continue
		_age[i] += dt
		if _age[i] >= _life[i]:
			_life[i] = 0.0
			continue
		match _kind[i]:
			Kind.CHIP, Kind.LOG:
				_vy[i] += gravity * dt
				_px[i] += _vx[i] * dt
				_py[i] += _vy[i] * dt
				_rot[i] += _vr[i] * dt
				if _py[i] > floor_y and _vy[i] > 0.0:
					_py[i] = floor_y
					if _bounces[i] < 2:
						_bounces[i] += 1
						_vy[i] *= -0.32
						_vx[i] *= 0.55
						_vr[i] *= 0.4
					else:
						_vy[i] = 0.0
						_vx[i] *= 0.8
						_vr[i] *= 0.5
			Kind.LEAF:
				# Terminal-velocity drift with a lateral sway; drag pulls the burst velocity down.
				_vx[i] *= exp(-3.0 * dt)
				_vy[i] = lerpf(_vy[i], 62.0 + 18.0 * sin(_ph[i]), 1.0 - exp(-2.5 * dt))
				_ph[i] += dt * 3.2
				_px[i] += (_vx[i] + cos(_ph[i]) * 46.0) * dt
				_py[i] += _vy[i] * dt
				_rot[i] += (_vr[i] + cos(_ph[i]) * 1.6) * dt
				if _py[i] > floor_y:
					_py[i] = floor_y
					_vy[i] = 0.0
			Kind.DUST:
				var d2 := exp(-2.6 * dt)
				_vx[i] *= d2
				_vy[i] *= d2
				_px[i] += _vx[i] * dt
				_py[i] += _vy[i] * dt
	for i in NUM_CAP:
		if _n_life[i] > 0.0:
			_n_age[i] += dt
			if _n_age[i] >= _n_life[i]:
				_n_life[i] = 0.0
				continue
			any = true
			var fast := 90.0 if _n_kind[i] == 1 else 60.0
			_n_pos[i] += Vector2(_n_vx[i], -fast * exp(-2.2 * _n_age[i])) * dt * 2.2
	if any or _was_active:
		queue_redraw()
	_was_active = any


var _was_active := false


# --- drawing -----------------------------------------------------------------

func _draw() -> void:
	if _life.is_empty():
		return
	for i in CAP:
		if _life[i] <= 0.0 or _delay[i] > 0.0:
			continue
		var t := _age[i] / _life[i]
		var pos := Vector2(_px[i], _py[i])
		match _kind[i]:
			Kind.CHIP:
				var a := 1.0 - smoothstep(0.7, 1.0, t)
				_draw_sprite(_chip, pos, _rot[i], 0.9 * _size[i], Color(1, 1, 1, a), Color("#e3c08a"), 9.0)
			Kind.LEAF:
				var a2 := smoothstep(0.0, 0.08, t) * (1.0 - smoothstep(0.65, 1.0, t))
				# Leaf flutter: x scale oscillates like a tumbling sheet.
				draw_set_transform(pos, _rot[i], Vector2(0.45 + 0.55 * absf(cos(_ph[i] * 1.3)), 1.0))
				var ls := _size[i] * 0.85
				if _leaf != null:
					var lw := float(_leaf.get_width()) * ls
					var lh := float(_leaf.get_height()) * ls
					draw_texture_rect(_leaf, Rect2(-lw * 0.5, -lh * 0.5, lw, lh), false, Color(1, 1, 1, a2))
				else:
					draw_circle(Vector2.ZERO, 6.0 * ls, Color(0.5, 0.75, 0.3, a2))
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			Kind.DUST:
				var e := _out_cubic(t)
				var a3 := 0.34 * (1.0 - t) * smoothstep(0.0, 0.12, t + 0.1)
				var s := _size[i] * (0.55 + 1.1 * e)
				draw_texture_rect(_soft, Rect2(pos.x - s, pos.y - s * 0.8, s * 2.0, s * 1.6), false, Color(0.86, 0.78, 0.62, a3))
			Kind.LOG:
				var a4 := 1.0 - smoothstep(0.75, 1.0, t)
				_draw_sprite(_logt, pos, _rot[i], _size[i], Color(1, 1, 1, a4), Color("#8a5a32"), 16.0)
	for i in NUM_CAP:
		if _n_life[i] <= 0.0:
			continue
		var t2 := _n_age[i] / _n_life[i]
		var kind: int = _n_kind[i]
		var pop_t := clampf(_n_age[i] / (0.22 if kind == 1 else 0.14), 0.0, 1.0)
		var sc := lerpf(1.9 if kind == 1 else 1.45, 1.0, _out_back(pop_t))
		if kind == 1:
			sc *= 1.0 + 0.06 * sin(_n_age[i] * 30.0) * (1.0 - t2)
		var a5 := 1.0 - smoothstep(0.6, 1.0, t2)
		var size := _num_font_size(kind)
		var col := Color(1, 1, 1, a5)
		var outline := Color(0.12, 0.06, 0.03, a5)
		if kind == 1:
			col = Color(1.0, 0.72, 0.16, a5).lerp(Color(1.0, 0.95, 0.6, a5), 0.5 - 0.5 * cos(_n_age[i] * 26.0)) if t2 < 0.5 else Color(1.0, 0.72, 0.16, a5)
		elif kind == 2:
			col = Color(0.97, 0.95, 0.9, a5 * 0.95)
		draw_set_transform(_n_pos[i], _n_rot[i] * pop_t, Vector2(sc, sc))
		var base := Vector2(-_n_half[i], size * 0.34)
		draw_string_outline(_font, base, _n_text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, size, 10 if kind == 1 else 8, outline)
		draw_string(_font, base + Vector2(0.9, 0.0), _n_text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)   # faux bold
		draw_string(_font, base, _n_text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_sprite(tex: Texture2D, pos: Vector2, rot: float, sc: float, mod: Color, fallback: Color, fb_size: float) -> void:
	draw_set_transform(pos, rot, Vector2.ONE)
	if tex != null:
		var w := float(tex.get_width()) * sc
		var h := float(tex.get_height()) * sc
		draw_texture_rect(tex, Rect2(-w * 0.5, -h * 0.5, w, h), false, mod)
	else:
		draw_rect(Rect2(-fb_size * 0.5 * sc, -fb_size * 0.3 * sc, fb_size * sc, fb_size * 0.6 * sc), Color(fallback, mod.a))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _out_cubic(t: float) -> float:
	var u := 1.0 - t
	return 1.0 - u * u * u


static func _out_back(t: float) -> float:
	var u := t - 1.0
	return 1.0 + 2.70158 * u * u * u + 1.70158 * u * u
