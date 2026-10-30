extends Node2D
## Pipsy, the lumberjack puppy mascot (bottom-left). Uses Art "cat/idle" / "cat/swing" when present.
## Node origin = ground point under Pipsy. Everything is eased: breathing + bob while idle,
## a cross-faded swing pose with a squash spring, cheer hops and emote bubbles.

const Juice := preload("res://scenes/ui/juice.gd")

const SWING_SHOW := 0.24
const HOP_TIME := 0.46

var _swing_t: float = 0.0
var _time: float = 0.0
var _swing_w: float = 0.0        # 0 = idle pose, 1 = swing pose (smoothed, cross-fades)
var _sq: float = 0.0             # squash spring (negative = squashed)
var _sq_v: float = 0.0
var _hop_t: float = -1.0
var _hops_left: int = 0
var _em_tex: Texture2D
var _em_t: float = -1.0
var _em_dur: float = 0.0


func swing() -> void:
	_swing_t = SWING_SHOW
	_sq_v = -2.4     # quick anticipation squash, the spring rebounds into a stretch


## Two happy hops.
func cheer() -> void:
	_hops_left = 2
	_hop_t = 0.0


## Emote bubble above Pipsy: kind is "happy", "wow" or "cry". duration < 0 keeps it up.
func emote(kind: String, duration: float = 1.8) -> void:
	var tex := Art.tex("ui/pipsy_" + kind)
	if tex == null:
		return
	_em_tex = tex
	_em_t = 0.0
	_em_dur = duration


func clear_emote() -> void:
	_em_t = -1.0


func _process(delta: float) -> void:
	_time += delta
	_swing_t = maxf(0.0, _swing_t - delta)
	# Pose weight eases in fast and back out slower: no hard sprite swap.
	_swing_w = Juice.damp(_swing_w, 1.0 if _swing_t > 0.0 else 0.0, 34.0 if _swing_t > 0.0 else 11.0, delta)
	# Squash spring.
	var n := maxi(1, int(ceil(delta / 0.008)))
	var h := minf(delta, 0.1) / float(n)
	for i in n:
		_sq_v += (-26.0 * 26.0 * _sq - 2.0 * 0.3 * 26.0 * _sq_v) * h
		_sq += _sq_v * h
	if _hop_t >= 0.0:
		_hop_t += delta
		if _hop_t >= HOP_TIME:
			_hop_t -= HOP_TIME
			_hops_left -= 1
			_sq_v = -2.6     # land squash
			if _hops_left <= 0:
				_hop_t = -1.0
	if _em_t >= 0.0:
		_em_t += delta
		if _em_dur >= 0.0 and _em_t > _em_dur:
			_em_t = -1.0
	queue_redraw()


func _draw() -> void:
	var swinging := _swing_t > 0.0
	var tex_idle := Art.tex("cat/idle")
	var tex_swing := Art.tex("cat/swing")
	if tex_swing == null:
		tex_swing = tex_idle
	if tex_idle:
		var sc := 190.0 / float(tex_idle.get_height())
		var sz := tex_idle.get_size() * sc
		# Breathing (scale.y sine) + gentle bob; squash spring and hop on top, all from the feet.
		var breathe := sin(_time * 2.4)
		var sy := 1.0 + 0.016 * breathe + _sq
		var sx := 1.0 - 0.007 * breathe - _sq * 0.55
		var hop_y := 0.0
		if _hop_t >= 0.0:
			var u := _hop_t / HOP_TIME
			hop_y = -64.0 * 4.0 * u * (1.0 - u)
		var bob_y := sin(_time * 1.3) * 1.6
		draw_set_transform(Vector2(0, bob_y + hop_y), 0.0, Vector2(sx, sy))
		var r := Rect2(-sz.x * 0.5, -sz.y, sz.x, sz.y)
		draw_texture_rect(tex_idle, r, false)
		if _swing_w > 0.01:
			draw_texture_rect(tex_swing, r, false, Color(1, 1, 1, _swing_w))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		_draw_emote(Vector2(54, -sz.y - 8.0 + bob_y + hop_y * 0.6))
		return
	var fur := Color("#e39a45")
	var fur_dark := Color("#b8702a")
	var cream := Color("#f6e2bf")
	var breathe := sin(_time * 2.4) * 2.0
	# Shadow
	draw_set_transform(Vector2(0, 2), 0.0, Vector2(1.0, 0.22))
	draw_circle(Vector2.ZERO, 70.0, Color(0, 0, 0, 0.25))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Tail
	var tail := PackedVector2Array()
	for i in 14:
		var k := float(i) / 13.0
		tail.append(Vector2(-42 - 38 * k, -34 - 52 * sin(k * 2.4) + sin(_time * 2.0 + k * 3.0) * 4.0 * k))
	draw_polyline(tail, fur_dark, 14.0)
	draw_polyline(tail, fur, 10.0)
	# Body (sitting) + belly
	draw_set_transform(Vector2(0, -42 + breathe * 0.5), 0.0, Vector2(1.0, 1.12))
	draw_circle(Vector2.ZERO, 46.0, fur)
	draw_circle(Vector2(6, 10), 30.0, cream)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Feet
	draw_circle(Vector2(-18, -6), 13.0, fur_dark)
	draw_circle(Vector2(22, -6), 13.0, fur_dark)
	# Head
	var hc := Vector2(6, -104 + breathe)
	draw_colored_polygon(PackedVector2Array([hc + Vector2(-34, -16), hc + Vector2(-28, -52), hc + Vector2(-8, -30)]), fur_dark)
	draw_colored_polygon(PackedVector2Array([hc + Vector2(34, -16), hc + Vector2(28, -52), hc + Vector2(8, -30)]), fur_dark)
	draw_circle(hc, 38.0, fur)
	draw_set_transform(hc + Vector2(0, 14), 0.0, Vector2(1.0, 0.7))
	draw_circle(Vector2.ZERO, 22.0, cream)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var blink := fmod(_time, 3.6) > 3.45
	for sx in [-1, 1]:
		var ep := hc + Vector2(sx * 15.0, -4.0)
		if blink or swinging:
			draw_line(ep + Vector2(-6, 0), ep + Vector2(6, 0), Color("#2a1a10"), 3.0)
		else:
			draw_circle(ep, 6.0, Color("#2a1a10"))
			draw_circle(ep + Vector2(-2, -2), 2.0, Color.WHITE)
	draw_colored_polygon(PackedVector2Array([hc + Vector2(-5, 8), hc + Vector2(5, 8), hc + Vector2(0, 14)]), Color("#d1626c"))
	for sx in [-1, 1]:
		draw_line(hc + Vector2(sx * 12, 12), hc + Vector2(sx * 38, 8), Color(1, 1, 1, 0.8), 1.5)
		draw_line(hc + Vector2(sx * 12, 15), hc + Vector2(sx * 38, 18), Color(1, 1, 1, 0.8), 1.5)
	# Red woodsman cap
	var cap := Color("#b8342c")
	draw_colored_polygon(PackedVector2Array([hc + Vector2(-36, -22), hc + Vector2(-24, -52), hc + Vector2(20, -56), hc + Vector2(38, -22)]), cap)
	draw_rect(Rect2(hc + Vector2(-38, -26), Vector2(76, 9)), cap.darkened(0.25))
	draw_circle(hc + Vector2(0, -60), 7.0, Color("#f0e6d2"))
	# Arm + little axe
	var shoulder := Vector2(30, -66 + breathe * 0.5)
	var hand := shoulder + (Vector2(26, -44) if not swinging else Vector2(40, 8))
	draw_line(shoulder, hand, fur_dark, 16.0)
	draw_line(shoulder, hand, fur, 11.0)
	var haft_end := hand + (Vector2(18, -64) if not swinging else Vector2(70, 22))
	draw_line(hand, haft_end, Color("#7a4d2a"), 6.0)
	var dir := (haft_end - hand).normalized()
	var nrm := Vector2(-dir.y, dir.x)
	draw_colored_polygon(PackedVector2Array([haft_end - dir * 4 + nrm * 4, haft_end + dir * 12 + nrm * 16,
		haft_end + dir * 12 - nrm * 14, haft_end - dir * 4 - nrm * 4]), Color("#c9d3dc"))
	draw_circle(hand, 8.0, fur)


func _draw_emote(anchor: Vector2) -> void:
	if _em_t < 0.0 or _em_tex == null:
		return
	var pop := Juice.out_back(clampf(_em_t / 0.28, 0.0, 1.0), 2.4)
	var fade := 1.0
	if _em_dur >= 0.0:
		fade = 1.0 - smoothstep(_em_dur - 0.3, _em_dur, _em_t)
	var sc := pop * 0.78
	var wob := sin(_em_t * 6.0) * 0.06
	var bob := sin(_em_t * 4.0) * 3.0 - 10.0 * Juice.out_cubic(clampf(_em_t / 0.4, 0.0, 1.0))
	var sz := _em_tex.get_size()
	draw_set_transform(anchor + Vector2(0, bob), wob, Vector2(sc, sc))
	draw_texture_rect(_em_tex, Rect2(-sz.x * 0.5, -sz.y, sz.x, sz.y), false, Color(1, 1, 1, fade))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
