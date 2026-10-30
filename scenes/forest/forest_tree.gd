extends Node2D
## One tree of the forest. Root = node origin (bottom-centre of the trunk).
## Standing -> falling (rotates around the root) -> felled (fades) -> gone (stump remains).

enum State { STANDING, FALLING, FELLED, GONE }

const CRACK_TIME := 0.14      # creak + tiny pause before the trunk gives way
const FALL_TIME := 0.52       # gravity-like fall after the crack (landing at CRACK_TIME + FALL_TIME)
const FADE_TIME := 1.15       # felled: bounce, hold, then fade; GONE after this
const HOLD_TIME := 0.4
const NOTCH_COLOR := Color("#ecd5a4")
const Juice := preload("res://scenes/ui/juice.gd")
# Damped springs for the hit wobble (root pivot): lean angle and squash/stretch.
const ANG_OMEGA := 21.0
const ANG_ZETA := 0.2
const ANG_GAIN := 38.0        # lean velocity impulse per unit "strength"
const SQ_OMEGA := 30.0
const SQ_ZETA := 0.22
const SQ_GAIN := 40.0
const BOUNCE_AMP := 0.2

var tree_id: String = ""
var def: Dictionary = {}
var max_hp: float = 1.0
var hp: float = 1.0
var tree_height: float = 260.0
var tree_width: float = 34.0
var state: State = State.STANDING
var fall_dir: int = 0
var chain_id: int = -1
var fall_t: float = 0.0
var fade_t: float = 0.0
var last_hit_side: int = 1

var in_active: bool = false     # registered in the forest's active list (wobbling / falling / fading)
var leaf_cd: float = 0.0        # forest-driven leaf emission timer while falling

var _body: Node2D
var _variation: float = 0.0
var _crown_scale: float = 1.0
var _ang := 0.0
var _ang_v := 0.0
var _sq := 0.0
var _sq_v := 0.0
var _creak_seed := 0.0


## Configure from trees.json data. `rng` only drives cosmetic variation.
func setup(id: String, x: float, ground_y: float, rng: RandomNumberGenerator) -> void:
	tree_id = id
	def = Balance.trees.get(id, {})
	max_hp = float(def.get("hp", 10))
	hp = max_hp
	tree_height = float(def.get("height", 260))
	tree_width = float(def.get("width", 34))
	position = Vector2(x, ground_y)
	_variation = rng.randf_range(-0.07, 0.07)
	_crown_scale = rng.randf_range(0.92, 1.1)


func _ready() -> void:
	_body = Node2D.new()
	add_child(_body)
	_body.draw.connect(_draw_body)


func is_standing() -> bool:
	return state == State.STANDING


## Returns true when this hit kills the tree.
func take_damage(amount: float, hit_side: int) -> bool:
	hp -= amount
	last_hit_side = hit_side
	if _body:
		_body.queue_redraw()
	return hp <= 0.0


## Kicks the wobble springs (lean away from the hit + squash/stretch). Tick-driven, so it
## freezes with hit-stop and never depends on tween timing.
func shake(strength: float) -> void:
	if state != State.STANDING or _body == null:
		return
	_ang_v += strength * float(-last_hit_side) * ANG_GAIN
	_sq_v += strength * SQ_GAIN


func is_settled() -> bool:
	return absf(_ang) < 0.0006 and absf(_ang_v) < 0.01 and absf(_sq) < 0.0006 and absf(_sq_v) < 0.01


func start_fall(dir: int, cid: int) -> void:
	state = State.FALLING
	fall_dir = dir
	chain_id = cid
	fall_t = 0.0
	leaf_cd = 0.0
	_creak_seed = float(cid) * 1.7 + position.x * 0.013
	if _body:
		# Hand the wobble over to the creak so the trunk never snaps back to upright.
		_body.rotation = _ang
		_body.scale = Vector2(1.0 + _sq * 0.5, 1.0 - _sq)
	queue_redraw()


## World-space centre of the crown right now (for leaves shed while falling).
func crown_world() -> Vector2:
	var r := _body.rotation if _body else 0.0
	return position + Vector2(sin(r), -cos(r)) * tree_height * 0.78


## Advances wobble / falling / fading. Returns true on the frame the trunk hits the ground.
func tick(dt: float) -> bool:
	match state:
		State.STANDING:
			_step_springs(dt)
		State.FALLING:
			fall_t += dt
			if fall_t < CRACK_TIME:
				# Creak: lean back a hair against the fall, with a quick tremble that ramps up.
				var k := fall_t / CRACK_TIME
				var tremble := sin(fall_t * 95.0 + _creak_seed) * 0.014 * sin(PI * k)
				_body.rotation = -float(fall_dir) * 0.05 * Juice.out_cubic(minf(k * 1.6, 1.0)) * (1.0 - k * 0.25) + tremble + _ang * (1.0 - k)
				_body.scale = Vector2(1.0 + _sq * 0.5, 1.0 - _sq).lerp(Vector2.ONE, k)
			else:
				var k2 := clampf((fall_t - CRACK_TIME) / FALL_TIME, 0.0, 1.0)
				# Gravity: angular acceleration grows as the trunk tips over (ease-in ~k^2.4).
				var lean0 := -float(fall_dir) * 0.05 * 0.75
				_body.rotation = lerpf(lean0, float(fall_dir) * (PI * 0.5), pow(k2, 2.4))
				if k2 >= 1.0:
					_body.rotation = float(fall_dir) * (PI * 0.5)
					state = State.FELLED
					fade_t = 0.0
					return true
		State.FELLED:
			fade_t += dt
			# Two damped bounces: |sin| lifts the tip, decay settles it.
			var bt := fade_t
			var lift := BOUNCE_AMP * exp(-8.0 * bt) * absf(sin(bt * 20.0))
			_body.rotation = float(fall_dir) * (PI * 0.5 - lift)
			var fade_k := clampf((fade_t - HOLD_TIME) / (FADE_TIME - HOLD_TIME), 0.0, 1.0)
			_body.modulate.a = 1.0 - fade_k * fade_k
			if fade_t >= FADE_TIME:
				state = State.GONE
				_body.visible = false
	return false


func _step_springs(dt: float) -> void:
	if _body == null or is_settled():
		return
	var n := maxi(1, int(ceil(dt / 0.008)))
	var h := minf(dt, 0.1) / float(n)
	for i in n:
		_ang_v += (-ANG_OMEGA * ANG_OMEGA * _ang - 2.0 * ANG_ZETA * ANG_OMEGA * _ang_v) * h
		_ang += _ang_v * h
		_sq_v += (-SQ_OMEGA * SQ_OMEGA * _sq - 2.0 * SQ_ZETA * SQ_OMEGA * _sq_v) * h
		_sq += _sq_v * h
	if is_settled():
		_ang = 0.0
		_ang_v = 0.0
		_sq = 0.0
		_sq_v = 0.0
	_body.rotation = _ang
	# Squash from the root: compress in y, bulge in x (and the reverse on the rebound).
	_body.scale = Vector2(1.0 + _sq * 0.5, 1.0 - _sq)


func _stage() -> int:
	return clampi(int(floor((1.0 - clampf(hp / max_hp, 0.0, 1.0)) * 4.0)), 0, 3)


# --- drawing -----------------------------------------------------------------

func _draw() -> void:
	# Ground shadow while the tree stands; the stump once it is cut.
	if state == State.STANDING:
		# Contact shadow: tight dark core + wider soft skirt, so the trunk sits on the grass.
		draw_set_transform(Vector2(0, 4), 0.0, Vector2(1.0, 0.24))
		draw_circle(Vector2.ZERO, tree_width * 2.0, Color(0.05, 0.1, 0.02, 0.1))
		draw_circle(Vector2.ZERO, tree_width * 1.35, Color(0.04, 0.07, 0.02, 0.2))
		draw_circle(Vector2.ZERO, tree_width * 0.8, Color(0.03, 0.04, 0.01, 0.32))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	var stump_tex := Art.tex("trees/%s_stump" % tree_id)
	if stump_tex:
		var tex0 := Art.tex("trees/%s_0" % tree_id)
		var sc := tree_height / float(tex0.get_height()) if tex0 else 1.0
		var sz := stump_tex.get_size() * sc
		draw_texture_rect(stump_tex, Rect2(-sz.x * 0.5, -sz.y, sz.x, sz.y), false)
		return
	var trunk := Color.html(str(def.get("color_trunk", "#8a6a4a")))
	var hw := tree_width * 0.5
	var h := 17.0
	draw_set_transform(Vector2(0, 3), 0.0, Vector2(1.0, 0.2))
	draw_circle(Vector2.ZERO, tree_width * 1.1, Color(0, 0, 0, 0.18))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_colored_polygon(PackedVector2Array([Vector2(-hw * 1.05, 0), Vector2(hw * 1.05, 0),
		Vector2(hw * 0.85, -h), Vector2(-hw * 0.85, -h)]), trunk.darkened(0.08))
	draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(hw * 1.05, 0),
		Vector2(hw * 0.85, -h), Vector2(0, -h)]), trunk.darkened(0.25))
	draw_set_transform(Vector2(0, -h), 0.0, Vector2(1.0, 0.38))
	draw_circle(Vector2.ZERO, hw * 0.85, NOTCH_COLOR.darkened(0.12))
	draw_circle(Vector2.ZERO, hw * 0.6, NOTCH_COLOR)
	draw_circle(Vector2.ZERO, hw * 0.32, NOTCH_COLOR.darkened(0.1))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_body() -> void:
	var tex := Art.tex("trees/%s_%d" % [tree_id, _stage()])
	if tex:
		var sc := tree_height / float(tex.get_height())
		var sz := tex.get_size() * sc
		_body.draw_texture_rect(tex, Rect2(-sz.x * 0.5, -sz.y, sz.x, sz.y), false)
		return
	_draw_placeholder()


func _draw_placeholder() -> void:
	var b := _body
	var trunk := Color.html(str(def.get("color_trunk", "#8a6a4a")))
	var crown := Color.html(str(def.get("color_crown", "#3f7a4a")))
	trunk = trunk.lightened(_variation)
	crown = crown.lightened(_variation * 1.5)
	var w := tree_width
	var h := tree_height
	var trunk_h := h * (0.34 if tree_id == "kavak" else 0.3)
	var hw := w * 0.5
	# Trunk with a darker shaded half.
	var top_hw := hw * 0.66
	b.draw_colored_polygon(PackedVector2Array([Vector2(-hw * 1.12, 0), Vector2(hw * 1.12, 0),
		Vector2(top_hw, -trunk_h * 1.1), Vector2(-top_hw, -trunk_h * 1.1)]), trunk)
	b.draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(hw * 1.12, 0),
		Vector2(top_hw, -trunk_h * 1.1), Vector2(0, -trunk_h * 1.1)]), trunk.darkened(0.22))
	for i in 3:
		var yy := -trunk_h * (0.2 + 0.28 * i)
		b.draw_line(Vector2(-hw * 0.3, yy), Vector2(-hw * 0.3, yy - 9), trunk.darkened(0.3), 2.0)
	# Cut notch grows with damage.
	var frac := 1.0 - clampf(hp / max_hp, 0.0, 1.0)
	if frac > 0.0:
		var s := float(last_hit_side)
		var depth := hw * (0.35 + 1.2 * frac)
		var ny := -trunk_h * 0.38
		var nh := 5.0 + 12.0 * frac
		b.draw_colored_polygon(PackedVector2Array([Vector2(s * hw, ny - nh),
			Vector2(s * (hw - depth), ny), Vector2(s * hw, ny + nh * 0.6)]), NOTCH_COLOR)
	if tree_id == "kavak":
		_draw_poplar_crown(crown, trunk_h)
	else:
		_draw_conifer_crown(crown, trunk_h, 4 if tree_id == "cam" else 6)


func _draw_poplar_crown(crown: Color, trunk_h: float) -> void:
	var b := _body
	var span := tree_height - trunk_h * 0.75
	var w := tree_width
	var n := 6
	for pass_i in 3:
		for i in n:
			var k := float(i) / float(n - 1)
			var cy := -trunk_h * 0.8 - span * (0.12 + 0.76 * k)
			var rx := w * (1.15 - 0.45 * absf(k - 0.35)) * _crown_scale
			var ry := span * 0.17
			var sway := sin(float(i) * 1.7 + _variation * 40.0) * w * 0.12
			match pass_i:
				0:
					b.draw_set_transform(Vector2(sway + 4, cy + 4), 0.0, Vector2(1.0, ry / rx))
					b.draw_circle(Vector2.ZERO, rx, crown.darkened(0.38))
				1:
					b.draw_set_transform(Vector2(sway, cy), 0.0, Vector2(1.0, ry / rx))
					b.draw_circle(Vector2.ZERO, rx, crown)
				2:
					b.draw_set_transform(Vector2(sway - rx * 0.22, cy - ry * 0.28), 0.0, Vector2(1.0, ry / rx))
					b.draw_circle(Vector2.ZERO, rx * 0.55, crown.lightened(0.22))
	b.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_conifer_crown(crown: Color, trunk_h: float, layers: int) -> void:
	var b := _body
	var crown_h := tree_height - trunk_h * 0.8
	var lh := crown_h / (1.0 + float(layers - 1) * 0.42)
	var step := lh * 0.42
	var hw := tree_width * (1.65 if layers <= 4 else 1.45) * _crown_scale
	for i in layers:
		var k := float(i) / float(layers - 1)
		var base_y := -trunk_h * 0.8 - step * float(i)
		var half := hw * (1.0 - 0.62 * k)
		var apex := Vector2(0, base_y - lh)
		var col := crown.lightened(0.12 * k).darkened(0.1 * (1.0 - k))
		b.draw_colored_polygon(PackedVector2Array([Vector2(-half, base_y),
			Vector2(-half * 0.45, base_y - lh * 0.07), Vector2(half * 0.45, base_y - lh * 0.07),
			Vector2(half, base_y), apex]), col)
		# Shaded right side + light left edge for volume.
		b.draw_colored_polygon(PackedVector2Array([apex, Vector2(half, base_y),
			Vector2(half * 0.45, base_y - lh * 0.07), Vector2(0, base_y - lh * 0.05)]), col.darkened(0.2))
		b.draw_colored_polygon(PackedVector2Array([apex, Vector2(-half * 0.55, base_y - lh * 0.03),
			Vector2(-half, base_y)]), col.lightened(0.1))
