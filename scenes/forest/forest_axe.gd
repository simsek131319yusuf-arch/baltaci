extends Node2D
## Axe cursor. The node origin is the hotspot (blade). The body swings around the handle end.
## Rest pose is "raised"; the impact pose is rotation 0 (blade exactly on the hotspot).
##
## The swing is a small tick-driven state machine (no tweens) so the forest can freeze it for
## hit-stop: anticipation wind-up (ease-out back) -> accelerating strike (ease-in quad) ->
## impact -> recoil (overshooting ease-out back) with a fading motion trail.

signal impact

const Juice := preload("res://scenes/ui/juice.gd")

const HANDLE := Vector2(-30, -104)   # pivot -> blade, placeholder pose at impact
const REST_ROT := 0.6
const WINDUP_ROT := 0.95
const TRAIL_LEN := 14
const TRAIL_LIFE := 0.16

enum Phase { REST, WINDUP, STRIKE, RECOIL }

@export var follow_rate: float = 24.0          # exponential cursor smoothing (1/s)
@export var follow_rate_strike: float = 70.0   # near-snap while striking, so blade and hit agree
@export var windup_share: float = 0.28
@export var strike_share: float = 0.2

## Where the axe wants to be (viewport px); the node eases towards it.
var target: Vector2 = Vector2(800, 450)

var _body: Node2D
var _trail: Node2D
var _tex: Texture2D
var _sprite_scale: float = 1.0
var _impact_pending := false   # swing started, contact not delivered yet
var _phase: Phase = Phase.REST
var _pt := 0.0                 # time inside the phase
var _dur_windup := 0.1
var _dur_strike := 0.06
var _dur_recoil := 0.2
var _rot_from := REST_ROT
var _time := 0.0
var _kick := Vector2.ZERO      # recoil push of the body (decays)
var _punch := 0.0              # squash on impact (decays)
var _prev_pos := Vector2.ZERO
var _tilt := 0.0
var _blade_local := Vector2.ZERO
var _tr_pos := PackedVector2Array()
var _tr_age := PackedFloat32Array()
var _tr_head := 0
var _tr_count := 0


func _ready() -> void:
	_tex = Art.tex("axe")
	_body = Node2D.new()
	add_child(_body)
	if _tex:
		_sprite_scale = 150.0 / float(_tex.get_height())
		_body.position = Vector2(0, float(_tex.get_height()) * _sprite_scale * 0.88)
		_blade_local = Vector2(0, -float(_tex.get_height()) * _sprite_scale * 0.88)
	else:
		_body.position = -HANDLE
		_blade_local = HANDLE
	_body.rotation = REST_ROT
	_body.draw.connect(_draw_axe)
	_body.queue_redraw()
	_tr_pos.resize(TRAIL_LEN)
	_tr_age.resize(TRAIL_LEN)
	_trail = Node2D.new()
	_trail.top_level = true      # draws in canvas coordinates, unaffected by the axe moving
	_trail.draw.connect(_draw_trail)
	add_child(_trail)
	move_child(_trail, 0)
	_prev_pos = position


## One chop: wind up, strike (emits `impact` on contact), recover.
## A swing still waiting for its contact delivers it before the new one starts.
func swing(duration: float) -> void:
	flush_impact()
	var d := maxf(duration, 0.08)
	_impact_pending = true
	_dur_windup = d * windup_share
	_dur_strike = d * strike_share
	_dur_recoil = d * (1.0 - windup_share - strike_share)
	_rot_from = _body.rotation if _body else REST_ROT
	_phase = Phase.WINDUP
	_pt = 0.0


func has_pending_impact() -> bool:
	return _impact_pending


## Delivers the contact of a swing that is still in progress (no-op otherwise).
func flush_impact() -> void:
	if _impact_pending:
		_deliver_impact()


func _deliver_impact() -> void:
	if not _impact_pending:
		return
	_impact_pending = false
	_kick = Vector2(7.0, -10.0)
	_punch = 1.0
	if _phase == Phase.STRIKE or _phase == Phase.WINDUP:
		_phase = Phase.RECOIL
		_pt = 0.0
		if _body:
			_body.rotation = 0.0
	impact.emit()


func stop() -> void:
	_impact_pending = false
	_phase = Phase.REST
	_pt = 0.0
	if _body:
		_body.rotation = REST_ROT
		_body.scale = Vector2.ONE
		_body.position = _rest_body_pos()
	_tr_count = 0


func _rest_body_pos() -> Vector2:
	if _tex:
		return Vector2(0, float(_tex.get_height()) * _sprite_scale * 0.88)
	return -HANDLE


## Advances the swing and the smoothed cursor following. `dt` may be hit-stop scaled.
func tick(dt: float) -> void:
	if _body == null or dt <= 0.0:
		return
	_time += dt
	var rate := follow_rate_strike if _phase == Phase.STRIKE else follow_rate
	position = Juice.damp_v(position, target, rate, dt)
	var vel_x := (position.x - _prev_pos.x) / dt
	_prev_pos = position
	_tilt = Juice.damp(_tilt, clampf(vel_x * 0.00022, -0.14, 0.14), 10.0, dt)

	var rest := REST_ROT + sin(_time * 2.2) * 0.02 + _tilt
	var rot := rest
	match _phase:
		Phase.REST:
			_body.rotation = rest
		Phase.WINDUP:
			_pt += dt
			var k := clampf(_pt / _dur_windup, 0.0, 1.0)
			# Ease-out back: pulls past the wind-up angle a touch, then settles.
			rot = lerpf(_rot_from, WINDUP_ROT, Juice.out_back(k, 2.0))
			_body.rotation = rot
			if k >= 1.0:
				_phase = Phase.STRIKE
				_pt = 0.0
		Phase.STRIKE:
			_pt += dt
			var k2 := clampf(_pt / _dur_strike, 0.0, 1.0)
			rot = lerpf(WINDUP_ROT, 0.0, k2 * k2)   # ease-in quad: accelerates into the hit
			_body.rotation = rot
			_record_trail()
			if k2 >= 1.0:
				_body.rotation = 0.0
				_deliver_impact()
		Phase.RECOIL:
			_pt += dt
			var k3 := clampf(_pt / _dur_recoil, 0.0, 1.0)
			rot = lerpf(0.0, rest, Juice.out_back(k3, 2.4))
			_body.rotation = rot
			if _pt < TRAIL_LIFE:
				_record_trail()
			if k3 >= 1.0:
				_phase = Phase.REST
	_kick = Juice.damp_v(_kick, Vector2.ZERO, 16.0, dt)
	_punch = Juice.damp(_punch, 0.0, 14.0, dt)
	_body.position = _rest_body_pos() + _kick
	_body.scale = Vector2(1.0 + 0.09 * _punch, 1.0 - 0.07 * _punch)
	_age_trail(dt)


func _record_trail() -> void:
	_tr_pos[_tr_head] = _body.to_global(_blade_local)
	_tr_age[_tr_head] = 0.0
	_tr_head = (_tr_head + 1) % TRAIL_LEN
	_tr_count = mini(_tr_count + 1, TRAIL_LEN)


func _age_trail(dt: float) -> void:
	if _tr_count == 0:
		return
	for i in _tr_count:
		var idx := (_tr_head - 1 - i + TRAIL_LEN * 2) % TRAIL_LEN
		_tr_age[idx] += dt
	var newest := (_tr_head - 1 + TRAIL_LEN) % TRAIL_LEN
	if _tr_age[(_tr_head - _tr_count + TRAIL_LEN) % TRAIL_LEN] > TRAIL_LIFE and _tr_age[newest] > TRAIL_LIFE:
		_tr_count = 0
	_trail.queue_redraw()


func _draw_trail() -> void:
	if _tr_count < 2:
		return
	for i in range(_tr_count - 1):
		var a_idx := (_tr_head - 1 - i + TRAIL_LEN * 2) % TRAIL_LEN
		var b_idx := (_tr_head - 2 - i + TRAIL_LEN * 2) % TRAIL_LEN
		var life := 1.0 - clampf(_tr_age[a_idx] / TRAIL_LIFE, 0.0, 1.0)
		if life <= 0.0:
			continue
		var fall := 1.0 - float(i) / float(_tr_count)
		var w := 3.0 + 13.0 * life * fall
		_trail.draw_line(_tr_pos[a_idx], _tr_pos[b_idx], Color(0.92, 0.96, 1.0, 0.5 * life * fall), w)


func _draw_axe() -> void:
	if _tex:
		var sz := _tex.get_size() * _sprite_scale
		_body.draw_texture_rect(_tex, Rect2(-sz.x * 0.5, -sz.y, sz.x, sz.y), false)
		return
	var b := _body
	var wood := Color("#8a5a32")
	var steel := Color("#c9d3dc")
	var tip := HANDLE
	# Handle (soft shadow + wood + highlight).
	b.draw_line(Vector2(3, 3), tip + Vector2(3, 3), Color(0, 0, 0, 0.25), 9.0)
	b.draw_line(Vector2.ZERO, tip, wood.darkened(0.25), 9.0)
	b.draw_line(Vector2(-1, 0), tip + Vector2(-1, 0), wood, 6.0)
	b.draw_line(Vector2(-2, -2), tip + Vector2(-2, 6), wood.lightened(0.25), 1.5)
	# Head: wedge with the cutting edge on the left (toward the tree).
	var c := tip
	var head := PackedVector2Array([c + Vector2(6, -18), c + Vector2(-8, -20), c + Vector2(-34, -30),
		c + Vector2(-38, 8), c + Vector2(-8, 18), c + Vector2(6, 16)])
	b.draw_colored_polygon(head, steel.darkened(0.2))
	b.draw_colored_polygon(PackedVector2Array([c + Vector2(-8, -20), c + Vector2(-34, -30),
		c + Vector2(-38, 8), c + Vector2(-8, 18)]), steel)
	b.draw_polyline(PackedVector2Array([c + Vector2(-34, -28), c + Vector2(-37, 6)]), Color.WHITE, 2.0)
