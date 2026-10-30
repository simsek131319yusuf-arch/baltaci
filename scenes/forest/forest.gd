extends Node2D
## Core run scene ("vardiya"): side-view forest, auto-swinging axe, felling + chain reactions,
## HUD and results. Simulation is driven by advance(dt) so tests can step it deterministically.

signal run_finished(result: Dictionary)
signal chain_grew(count: int)

const ForestTree := preload("res://scenes/forest/forest_tree.gd")
const ForestBackdrop := preload("res://scenes/forest/forest_backdrop.gd")
const ForestAxe := preload("res://scenes/forest/forest_axe.gd")
const ForestCat := preload("res://scenes/forest/forest_cat.gd")
const ForestHud := preload("res://scenes/forest/forest_hud.gd")
const ForestFx := preload("res://scenes/forest/forest_fx.gd")
const Fmt := preload("res://scenes/ui/fmt.gd")
const Juice := preload("res://scenes/ui/juice.gd")
const SceneTransition := preload("res://scenes/ui/scene_transition.gd")

const VIEW_SIZE := Vector2(1600, 900)
const CAMP_SCENE := "res://scenes/camp/camp.tscn"

enum Phase { RUNNING, ENDING, DONE }

@export_group("Camera")
@export var edge_zone: float = 150.0
@export var scroll_speed: float = 1100.0
@export var first_tree_x: float = 480.0
@export var follow_speed: float = 520.0     # auto-follow nudge (px/s) when the tree line drifts right
@export var cull_margin: float = 900.0      # trees this far behind the camera are freed
@export_group("Hits")
@export var hit_tolerance: float = 14.0
@export var tree_shake_rad: float = 0.03
@export var chips_per_hit: int = 7
@export_group("Juice")   # defaults; data/balance.json "juice" overrides them in _ready()
@export var hitstop_ms: float = 45.0         # hit-stop on a normal hit
@export var hitstop_crit_ms: float = 65.0
@export var hitstop_kill_ms: float = 60.0
@export var hitstop_scale: float = 0.04      # simulation speed while frozen (local time scale)
@export var shake_max_px: float = 16.0
@export var trauma_decay: float = 1.5        # per second
@export var trauma_crit: float = 0.14
@export var trauma_crack: float = 0.05
@export var trauma_land: float = 0.2
@export var trauma_per_link: float = 0.09
@export var chain_happy: int = 3
@export var chain_wow: int = 8
@export_group("Run")
@export var max_end_wait: float = 6.0   # hard cap while waiting for in-flight falls
@export var layout_seed: int = 0   # 0 = random layout each run

# State exposed for tests / HUD.
var phase: Phase = Phase.RUNNING
var trees: Array = []                 # all ForestTree nodes, left to right
var logs: Dictionary = {}             # tree_id -> count (counted when the trunk hits the ground)
var trees_felled: int = 0
var longest_chain: int = 0
var current_chain: int = 0
var chain_sizes: Dictionary = {}      # chain_id -> trees that started falling in it (HUD / popup)
var chain_landed: Dictionary = {}     # chain_id -> trees of that chain whose trunk hit the ground (paid)
var time_left: float = 0.0
var elapsed: float = 0.0
var cam_x: float = 0.0
var swing_enabled: bool = true
var manual_mode: bool = false         # tests: no input, no mouse capture, no autoplay
var power_mult: float = 1.0           # autoplay boost for axe damage
var fall_mult: float = 1.0            # autoplay boost for fall damage
var virtual_cursor_active: bool = false
var virtual_cursor: Vector2 = Vector2(800, 600)
## Story hooks (Story.notify + GameState.note_depth). Off in tests (manual_mode) and in autoplay /
## autoshot runs so previews never open blocking dialogs; `--story` forces them on for previews.
var story_enabled: bool = true

var _ground_y: float = 760.0
var _standing: int = 0
var _next_col: int = 0
var _next_x: float = 0.0
var _gen_rng := RandomNumberGenerator.new()
var _cull_cd: float = 0.0
var _active: Array = []               # trees currently falling / fading
var _next_chain_id: int = 0
var _swing_cd: float = 0.3
var _end_timer: float = 0.0
var _trauma: float = 0.0
var _shake_t: float = 0.0
var _shake_off: Vector2 = Vector2.ZERO
var _noise := FastNoiseLite.new()
var _hitstop_t: float = 0.0
var _rng := RandomNumberGenerator.new()
var _world: Node2D
var _fx: Node2D   # ForestFx
var _backdrop: Node2D
var _axe: Node2D
var _cat: Node2D
var _hud: CanvasLayer
var _autoshot_path: String = ""
var _story_col: int = 0
var _story_trees: Dictionary = {}
var _run_end_sent: bool = false
var _last_result: Dictionary = {}
var _autoshot_at: float = 6.0
var _auto_time: float = -1.0
var _autoend_at: float = -1.0
var _autoplay: bool = false
var _auto_target: Node2D
var _real_time: float = 0.0
var _shot_taken: bool = false
var _autoend_given: bool = false
# --autoshot-seq: a short frame sequence (for judging smoothness), see _seq_run().
var _shot_wait: float = 2.4          # results screenshot waits for the reveal animation (--autoshot-wait=)
var _seq_dir: String = ""
var _seq_frames: int = 12
var _seq_interval: float = 0.06
var _seq_slow: float = 0.15
var _seq_trigger: String = "chain"
var _seq_chain: int = 2
var _seq_started: bool = false
var _seq_acc: float = 0.0


func _ready() -> void:
	_parse_args()
	story_enabled = (not _autoplay and not manual_mode) or OS.get_cmdline_user_args().has("--story")
	_load_juice()
	_noise.seed = 1337
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 1.0
	_ground_y = float(Balance.forest.get("ground_y", 760))
	time_left = _auto_time if _auto_time > 0.0 else GameState.stat("run_time")
	_next_x = first_tree_x
	_build_layers()
	if not manual_mode:
		ensure_forest(first_tree_x + VIEW_SIZE.x)
		_hud.show_banner("Başla!")
		if not _autoplay:
			Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	set_process(not manual_mode)


func _exit_tree() -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_HIDDEN:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _load_juice() -> void:
	hitstop_ms = Juice.cfg("hitstop_ms", hitstop_ms)
	hitstop_crit_ms = Juice.cfg("hitstop_crit_ms", hitstop_crit_ms)
	hitstop_kill_ms = Juice.cfg("hitstop_kill_ms", hitstop_kill_ms)
	hitstop_scale = Juice.cfg("hitstop_scale", hitstop_scale)
	shake_max_px = Juice.cfg("shake_max_px", shake_max_px)
	trauma_decay = Juice.cfg("trauma_decay", trauma_decay)
	trauma_crit = Juice.cfg("trauma_crit", trauma_crit)
	trauma_land = Juice.cfg("trauma_land", trauma_land)
	trauma_per_link = Juice.cfg("trauma_per_link", trauma_per_link)
	chain_happy = int(Juice.cfg("chain_happy", chain_happy))
	chain_wow = int(Juice.cfg("chain_wow", chain_wow))


func _parse_args() -> void:
	var seed_val := layout_seed
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--autoshot="):
			_autoshot_path = a.substr("--autoshot=".length())
			_autoplay = true
		elif a.begins_with("--autoshot-seq="):
			_seq_dir = a.substr("--autoshot-seq=".length())
			_autoplay = true
		elif a.begins_with("--seq-frames="):
			_seq_frames = int(a.substr("--seq-frames=".length()))
		elif a.begins_with("--seq-interval="):
			_seq_interval = float(a.substr("--seq-interval=".length()))
		elif a.begins_with("--seq-slow="):
			_seq_slow = float(a.substr("--seq-slow=".length()))
		elif a.begins_with("--seq-trigger="):
			_seq_trigger = a.substr("--seq-trigger=".length())
		elif a.begins_with("--seq-chain="):
			_seq_chain = int(a.substr("--seq-chain=".length()))
		elif a.begins_with("--autoplay-seed="):
			seed_val = int(a.substr("--autoplay-seed=".length()))
			_autoplay = true
		elif a.begins_with("--autoshot-wait="):
			_shot_wait = float(a.substr("--autoshot-wait=".length()))
		elif a.begins_with("--autoshot-at="):
			_autoshot_at = float(a.substr("--autoshot-at=".length()))
		elif a.begins_with("--autotime="):
			_auto_time = float(a.substr("--autotime=".length()))
		elif a.begins_with("--autoend="):
			_autoend_at = float(a.substr("--autoend=".length()))
			_autoend_given = true
	if _autoplay and not manual_mode:
		GameState.persist = false   # autoplay never writes the real save
		virtual_cursor_active = true
		power_mult = 4.0
		fall_mult = 2.0
		if seed_val == 0:
			seed_val = 7
	layout_seed = seed_val
	_rng.seed = seed_val if seed_val != 0 else int(Time.get_ticks_usec())
	_gen_rng.seed = seed_val if seed_val != 0 else int(Time.get_ticks_usec()) + 1


func _build_layers() -> void:
	var bg_layer := CanvasLayer.new()
	bg_layer.layer = -10
	add_child(bg_layer)
	_backdrop = ForestBackdrop.new()
	_backdrop.ground_y = _ground_y
	bg_layer.add_child(_backdrop)

	_world = Node2D.new()
	add_child(_world)
	_fx = ForestFx.new()
	_fx.z_index = 20
	_fx.ground_y = _ground_y
	_world.add_child(_fx)

	var cat_layer := CanvasLayer.new()
	cat_layer.layer = 5
	add_child(cat_layer)
	_cat = ForestCat.new()
	_cat.position = Vector2(170, _ground_y + 62)
	cat_layer.add_child(_cat)

	_hud = ForestHud.new()
	add_child(_hud)
	_hud.paydos_pressed.connect(end_run)
	_hud.camp_pressed.connect(_go_camp)
	_hud.results_revealed.connect(_on_results_revealed)

	var axe_layer := CanvasLayer.new()
	axe_layer.layer = 20
	add_child(axe_layer)
	_axe = ForestAxe.new()
	_axe.position = VIEW_SIZE * 0.5
	_axe.target = _axe.position
	_axe.follow_rate = Juice.cfg("cursor_follow", _axe.follow_rate)
	_axe.follow_rate_strike = Juice.cfg("cursor_follow_strike", _axe.follow_rate_strike)
	axe_layer.add_child(_axe)
	_axe.impact.connect(_on_axe_impact)
	_axe.visible = not manual_mode


# --- forest construction ---------------------------------------------------------

## Endless forest: generates columns left to right until world x `to_x` is covered.
## Column index (depth) drives the tree mix through Balance.pick_tree.
func ensure_forest(to_x: float) -> void:
	var s_min := float(Balance.forest.get("spacing_min", 70))
	var s_max := float(Balance.forest.get("spacing_max", 115))
	while _next_x <= to_x:
		add_tree(Balance.pick_tree(_next_col, _gen_rng), _next_x, _gen_rng)
		_next_col += 1
		_next_x += _gen_rng.randf_range(s_min, s_max)
	if story_enabled:
		var col := _next_col - int(Balance.forest.get("buffer_columns", 14))
		if col > _story_col:
			_story_col = col
			GameState.note_depth(col)
			Story.notify("depth", {"col": col})


## World x up to which the forest must exist when something is happening at `wx`.
func forest_ahead_of(wx: float) -> float:
	return wx + float(Balance.forest.get("buffer_columns", 14)) * float(Balance.forest.get("spacing_max", 115))


func generated_columns() -> int:
	return _next_col


## Adds one standing tree at world x (also used by tests to build exact layouts).
func add_tree(id: String, x: float, rng: RandomNumberGenerator = null) -> Node2D:
	if rng == null:
		rng = _rng
	var t: Node2D = ForestTree.new()
	t.setup(id, x, _ground_y, rng)
	_world.add_child(t)
	trees.append(t)
	_standing += 1
	if story_enabled and not _story_trees.has(id):
		_story_trees[id] = true
		Story.notify("tree_first_seen", {"tree": id})
	return t


func standing_count() -> int:
	return _standing


# --- frame loop ------------------------------------------------------------------

func _process(delta: float) -> void:
	_real_time += delta
	_seq_acc += delta
	# Local time scale: hit-stop slows the simulation (axe, trees, particles) but never the
	# camera, HUD or input; Engine.time_scale stays untouched.
	var sdt := delta
	if _hitstop_t > 0.0:
		_hitstop_t -= delta
		sdt = delta * hitstop_scale
	if _autoplay:
		_update_autoplay(delta)
	_update_camera(delta)
	ensure_forest(forest_ahead_of(cam_x + VIEW_SIZE.x))
	_cull_cd -= delta
	if _cull_cd <= 0.0:
		_cull_cd = 0.5
		_cull_behind()
	_axe.target = cursor_screen()
	_axe.tick(sdt)
	advance(sdt)
	_fx.tick(sdt)
	_backdrop.set_cam(cam_x, _shake_off)
	var gold: float = Balance.run_payout(logs, longest_chain).total
	if phase != Phase.DONE:
		_hud.set_values(time_left, gold, current_chain)
	_check_autoshot()
	if _seq_dir != "" and not _seq_started and _seq_trigger == "time" and _real_time >= _autoshot_at:
		_seq_start()


## Advances the whole simulation by dt seconds (timers, swings, falls, shake).
func advance(dt: float) -> void:
	if phase == Phase.RUNNING:
		elapsed += dt
		time_left = maxf(0.0, time_left - dt)
		if swing_enabled:
			_swing_cd -= dt
			if _swing_cd <= 0.0:
				_swing_cd += GameState.stat("swing_interval")
				_axe.swing(minf(GameState.stat("swing_interval") * 0.9, 0.55))
				_cat.swing()
				if _seq_dir != "" and _seq_trigger == "swing" and _real_time >= _autoshot_at:
					_seq_start()
		if time_left <= 0.0:
			end_run()
	# Forward pass over the trees that were active when the frame began (trees woken during the
	# pass are first ticked next frame); removal keeps the order, no per-frame array copy.
	var ai := 0
	var left := _active.size()
	while left > 0:
		left -= 1
		var t: Node2D = _active[ai]
		if not is_instance_valid(t):   # freed by the cull while still wobbling
			_active.remove_at(ai)
			continue
		if t.tick(dt):
			_on_landed(t)
		elif t.state == ForestTree.State.FALLING and t.fall_t > ForestTree.CRACK_TIME:
			t.leaf_cd -= dt
			if t.leaf_cd <= 0.0:
				t.leaf_cd = 0.09
				_fx.leaves(t.crown_world(), t.tree_width * 0.5, 1)
		if t.state == ForestTree.State.GONE or (t.state == ForestTree.State.STANDING and t.is_settled()):
			t.in_active = false
			_active.remove_at(ai)
		else:
			ai += 1
	if phase == Phase.ENDING:
		_end_timer += dt
		var falling := false
		for t in _active:
			if t.state == ForestTree.State.FALLING:
				falling = true
		if not falling or _end_timer >= max_end_wait:
			_complete()
	# Trauma shake: offset = trauma^2 * smooth noise, trauma decays linearly. No random jitter.
	_trauma = maxf(0.0, _trauma - trauma_decay * dt)
	_shake_t += dt
	if _trauma > 0.0:
		var amt := _trauma * _trauma * shake_max_px * 1.7
		_shake_off = Vector2(_noise.get_noise_2d(_shake_t * 26.0, 0.0), _noise.get_noise_2d(_shake_t * 26.0, 57.0)) * amt
	else:
		_shake_off = Vector2.ZERO
	_world.position = Vector2(-cam_x, 0.0) + _shake_off


func cursor_screen() -> Vector2:
	if virtual_cursor_active:
		return virtual_cursor
	return get_viewport().get_mouse_position()


func _update_camera(delta: float) -> void:
	if manual_mode:
		return
	var dir := 0.0
	var m := cursor_screen()
	if not _autoplay and phase == Phase.RUNNING:
		# Edge scrolling needs the pointer inside the window; the keyboard always works.
		if Rect2(Vector2.ZERO, VIEW_SIZE).has_point(m):
			if m.x > VIEW_SIZE.x - edge_zone:
				dir = (m.x - (VIEW_SIZE.x - edge_zone)) / edge_zone
			elif m.x < edge_zone:
				dir = -(edge_zone - m.x) / edge_zone
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			dir = 1.0
		elif Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			dir = -1.0
	cam_x = maxf(0.0, cam_x + dir * scroll_speed * delta)
	if dir == 0.0 and not _autoplay and phase == Phase.RUNNING:
		# Auto-follow: when the leftmost standing tree in reach sits right of the left third,
		# the tree line has moved on without the camera -> nudge right (never left).
		var lead := INF
		for t in trees:
			if t.is_standing() and t.position.x >= cam_x:
				lead = t.position.x
				break
		var excess := lead - cam_x - VIEW_SIZE.x / 3.0
		if excess > 0.0 and lead < INF:
			cam_x += minf(excess, follow_speed * delta)


## Frees trees (standing or stump) far behind the camera so the endless forest stays cheap.
func _cull_behind() -> void:
	var limit := cam_x - cull_margin
	var keep: Array = []
	for t in trees:
		var done: bool = t.state == ForestTree.State.GONE or t.state == ForestTree.State.STANDING
		if done and t.position.x < limit:
			if t.state == ForestTree.State.STANDING:
				_standing -= 1
			if t == _auto_target:
				_auto_target = null
			t.queue_free()
		else:
			keep.append(t)
	trees = keep


# --- hitting ---------------------------------------------------------------------

func _on_axe_impact() -> void:
	if phase != Phase.RUNNING:
		return
	strike_at(cursor_screen())


## Chops whatever standing tree lies under `screen` (viewport coordinates). Returns it or null.
func strike_at(screen: Vector2) -> Node2D:
	var wx := screen.x + cam_x
	var target := find_tree_at(wx, screen.y)
	if target == null:
		return null
	var crit := _rng.randf() < GameState.stat("crit_chance")
	var dmg := GameState.stat("axe_damage") * power_mult
	if crit:
		dmg *= GameState.stat("crit_multiplier")
	hit_tree(target, wx, screen.y, dmg, crit)
	return target


func find_tree_at(wx: float, y: float) -> Node2D:
	var best: Node2D = null
	var best_d := INF
	for t in trees:
		if not t.is_standing():
			continue
		var d: float = absf(wx - t.position.x)
		if d > t.tree_width * 0.5 + hit_tolerance:
			continue
		if y > t.position.y + 12.0 or y < t.position.y - t.tree_height:
			continue
		if d < best_d:
			best_d = d
			best = t
	return best


func hit_tree(t: Node2D, hit_wx: float, hit_y: float, dmg: float, crit: bool) -> void:
	var dir := fall_dir_for(hit_wx, t.position.x)
	var dead: bool = t.take_damage(dmg, -dir)
	_fx.number(Vector2(hit_wx, hit_y - 30.0), ("%d!" % int(round(dmg))) if crit else str(int(round(dmg))), 1 if crit else 0)
	_fx.chips(Vector2(hit_wx, hit_y), -dir, chips_per_hit + (4 if crit else 0))
	_fx.leaves(t.position + Vector2(0.0, -t.tree_height * 0.78), t.tree_width * 0.6, 3 if crit else 2)
	t.shake(tree_shake_rad * (1.7 if crit else 1.0))
	_wake(t)
	if crit:
		_add_trauma(trauma_crit)
	_hitstop_t = maxf(_hitstop_t, (hitstop_kill_ms if dead else (hitstop_crit_ms if crit else hitstop_ms)) * 0.001)
	if dead:
		_next_chain_id += 1
		_begin_fall(t, dir, _next_chain_id)


## Registers a tree for per-frame ticking (wobble springs, falling, fading).
func _wake(t: Node2D) -> void:
	if not t.in_active:
		t.in_active = true
		_active.append(t)


func _add_trauma(v: float) -> void:
	_trauma = minf(1.0, _trauma + v)


## A tree falls AWAY from the side it was hit from: hit left of the trunk -> falls right (+1).
static func fall_dir_for(hit_x: float, tree_x: float) -> int:
	return 1 if hit_x < tree_x else -1


## Standing trees whose root x lies in (x, x + dir*height] (open at the falling tree itself).
static func trees_in_fall_range(candidates: Array, x: float, dir: int, height: float) -> Array:
	var out: Array = []
	for t in candidates:
		if not t.is_standing():
			continue
		var d: float = (t.position.x - x) * float(dir)
		if d > 0.0 and d <= height:
			out.append(t)
	return out


func _begin_fall(t: Node2D, dir: int, chain_id: int) -> void:
	t.start_fall(dir, chain_id)
	t.z_index = 1
	_standing -= 1
	_wake(t)
	_add_trauma(trauma_crack)
	_fx.leaves(t.position + Vector2(0.0, -t.tree_height * 0.8), t.tree_width * 0.8, 4)
	var n: int = int(chain_sizes.get(chain_id, 0)) + 1
	chain_sizes[chain_id] = n
	current_chain = n
	if _seq_dir != "" and _seq_trigger == "chain" and n >= _seq_chain:
		_seq_start()
	if n >= 2:
		_hud.show_chain_popup(n)
		chain_grew.emit(n)
		if story_enabled and n >= 5:
			Story.notify("chain", {"n": n})
		if n == chain_happy or n == chain_wow or (n > chain_wow and n % 4 == 0):
			_cat.emote("wow" if n >= chain_wow else "happy", 1.6)



func _on_landed(t: Node2D) -> void:
	if phase == Phase.DONE:
		return   # run already paid out; late landings are visual only
	# Logs and chain length are counted from the same event (the trunk hitting the ground),
	# so a tree still in the air at payout time is in neither.
	logs[t.tree_id] = int(logs.get(t.tree_id, 0)) + int(t.def.get("logs", 1))
	trees_felled += 1
	var landed: int = int(chain_landed.get(t.chain_id, 0)) + 1
	chain_landed[t.chain_id] = landed
	longest_chain = maxi(longest_chain, landed)
	var dmg: float = t.tree_height * GameState.stat("fall_power") * fall_mult
	for victim in trees_in_fall_range(trees, t.position.x, t.fall_dir, t.tree_height):
		victim.take_damage(dmg, -t.fall_dir)
		_fx.number(victim.position + Vector2(0, -victim.tree_height * 0.45), str(int(round(dmg))), 2)
		victim.shake(tree_shake_rad * 1.4)
		_wake(victim)
		if victim.hp <= 0.0:
			_begin_fall(victim, t.fall_dir, t.chain_id)
	var links: int = int(chain_sizes.get(t.chain_id, 1))
	_add_trauma(trauma_land + trauma_per_link * float(links - 1))
	_fx.dust_line(t.position, t.fall_dir, t.tree_height, 6 + int(t.tree_height / 55.0))
	_fx.chips(t.position + Vector2(float(t.fall_dir) * t.tree_height * 0.55, -6.0), -t.fall_dir, 4)
	_fx.log_pop(t.position + Vector2(float(t.fall_dir) * t.tree_height * 0.45, -14.0), t.fall_dir)


# --- run end ---------------------------------------------------------------------

func end_run() -> void:
	if phase != Phase.RUNNING:
		return
	# A swing already under way delivers its contact before the run is closed.
	_axe.flush_impact()
	phase = Phase.ENDING
	_end_timer = 0.0
	_axe.stop()
	_axe.visible = false
	_hud.set_paydos_enabled(false)
	if not manual_mode:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _complete() -> void:
	if phase == Phase.DONE:
		return
	phase = Phase.DONE
	var result: Dictionary
	if _autoplay:
		# Autoplay/screenshot runs never touch GameState or the save: preview only.
		result = _preview_result()
	else:
		result = GameState.apply_run_result(logs, longest_chain, trees_felled, elapsed)
	var total: float = float(result.get("total", 0.0))
	var kind: String = ForestHud.reaction_for_total(total)   # judged against earlier runs, before this one is recorded
	if not _autoplay:
		ForestHud.record_total(total)
	_hud.show_results(result, kind)
	if kind == "happy":
		_cat.cheer()
	_last_result = result
	run_finished.emit(result)


## The results panel finished revealing: only now may a story beat open over it.
func _on_results_revealed() -> void:
	if not story_enabled or _run_end_sent:
		return
	_run_end_sent = true
	Story.notify("run_end", {"last_run": _last_result, "depth": GameState.max_depth})


func _story_busy() -> bool:
	return story_enabled and _run_end_sent and (Story.is_playing() or not Story.queue.is_empty())


func _preview_result() -> Dictionary:
	var payout := Balance.run_payout(logs, longest_chain)
	return {"logs": logs.duplicate(), "longest_chain": longest_chain, "trees_felled": trees_felled,
		"duration": elapsed, "sales": payout.sales, "chain_bonus": payout.chain_bonus,
		"total": payout.total, "gold_after": GameState.gold + payout.total}


func _go_camp() -> void:
	if _story_busy():
		return   # a dialog is open (or about to reopen between beats): the button must not fire
	if ResourceLoader.exists(CAMP_SCENE):
		SceneTransition.go(get_tree(), CAMP_SCENE)
	else:
		push_warning("camp scene not found: %s" % CAMP_SCENE)


# --- autoplay / autoshot -----------------------------------------------------------

func _update_autoplay(delta: float) -> void:
	if phase != Phase.RUNNING:
		return
	if _auto_target != null and (not is_instance_valid(_auto_target) or not _auto_target.is_standing()):
		_auto_target = null
	if _auto_target == null:
		for t in trees:
			if t.is_standing() and t.position.x > cam_x + 420.0:
				_auto_target = t
				break
		if _auto_target == null:
			for t in trees:
				if t.is_standing():
					_auto_target = t
					break
	if _auto_target == null:
		return
	var want_cam := maxf(0.0, _auto_target.position.x - 760.0)
	cam_x = move_toward(cam_x, want_cam, 1400.0 * delta)
	var goal := Vector2(_auto_target.position.x - cam_x - 12.0, _ground_y - _auto_target.tree_height * 0.22)
	virtual_cursor = virtual_cursor.lerp(goal, clampf(delta * 9.0, 0.0, 1.0))


func _check_autoshot() -> void:
	if _autoend_at > 0.0 and _real_time >= _autoend_at:
		_autoend_at = -1.0
		_autoend_given = true
		end_run()
	if _autoshot_path == "" or _shot_taken:
		return
	var ready_to_shoot := (phase == Phase.DONE) if _autoend_given else (_real_time >= _autoshot_at)
	if ready_to_shoot:
		_shot_taken = true
		_save_shot()


func _save_shot() -> void:
	await get_tree().create_timer(_shot_wait if phase == Phase.DONE else 0.0).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(_autoshot_path)
	print("autoshot: ", _autoshot_path, " err=", err)
	get_tree().quit()


# --- smoothness frame sequence ---------------------------------------------------------

## Starts saving `_seq_frames` frames every `_seq_interval` seconds of GAME time. Engine.time_scale is
## lowered so a PNG write does not distort the spacing; it is restored before quitting.
func _seq_start() -> void:
	if _seq_started:
		return
	_seq_started = true
	_seq_run()


func _seq_run() -> void:
	DirAccess.make_dir_recursive_absolute(_seq_dir)
	Engine.time_scale = _seq_slow
	for i in _seq_frames:
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var path := _seq_dir.path_join("seq_%02d.png" % i)
		var err := img.save_png(path)
		print("seq: ", path, " t=", snappedf(float(i) * _seq_interval, 0.001), " err=", err)
		_seq_acc = 0.0
		while _seq_acc < _seq_interval:
			await get_tree().process_frame
	Engine.time_scale = 1.0
	get_tree().quit()
