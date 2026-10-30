extends SceneTree
## Headless tests for the forest run logic. Expected values are written in advance.
## Run: ~/bin/godot --headless --path . -s tests/test_forest.gd
## GameState.save_path is redirected to user://test_forest_save.json, so the real save is never written.

const SAVE_PATH := "user://test_forest_save.json"
const REAL_SAVE := "user://save.json"
const FOREST_PATH := "res://scenes/forest/forest.tscn"

var _fails := 0
var _real_before: PackedByteArray = PackedByteArray()
var _real_existed := false
var _old_path := ""


func _initialize() -> void:
	await process_frame
	var B := root.get_node("Balance")
	var G := root.get_node("GameState")
	_redirect_save(G)

	# Fixed stats so expectations are independent of any save: kavak 260 px * 0.23 = 59.8 fall damage.
	G.from_dict({"levels": {"fall_power": 15}})

	# (1) fall range: x = 1000, height 260, dir +1 -> roots in (1000, 1260].
	var f := _new_forest()
	var xs := [900.0, 1000.0, 1001.0, 1100.0, 1260.0, 1261.0, 1500.0]
	var ts: Array = []
	for x in xs:
		ts.append(f.add_tree("kavak", x))
	var picked_r: Array = f.trees_in_fall_range(f.trees, 1000.0, 1, 260.0)
	_eq("range +1 picks (1000,1260]", _xs(picked_r), [1001.0, 1100.0, 1260.0])
	var picked_l: Array = f.trees_in_fall_range(f.trees, 1000.0, -1, 260.0)
	_eq("range -1 picks [740,1000)", _xs(picked_l), [900.0])
	ts[2].state = ts[2].State.FALLING   # non-standing trees are skipped
	_eq("range skips fallen", _xs(f.trees_in_fall_range(f.trees, 1000.0, 1, 260.0)), [1100.0, 1260.0])
	_free(f)

	# (2) chain of 3 kavak, 80 px apart, enough fall damage -> longest_chain == 3.
	f = _new_forest()
	var a: Node2D = f.add_tree("kavak", 1000.0)
	var b: Node2D = f.add_tree("kavak", 1080.0)
	var c: Node2D = f.add_tree("kavak", 1160.0)
	a.hp = 1.0
	f.strike_at(Vector2(1000.0 - 5.0 - f.cam_x, 700.0))   # hit from the left -> falls right
	_step(f, 3.0)
	_eq("chain longest", f.longest_chain, 3)
	_eq("chain felled", f.trees_felled, 3)
	_eq("chain logs", f.logs, {"kavak": 3})
	_eq("chain same direction", [a.fall_dir, b.fall_dir, c.fall_dir], [1, 1, 1])
	_free(f)

	# (2b) damage too low -> no chain.
	G.from_dict({})
	f = _new_forest()
	a = f.add_tree("kavak", 1000.0)
	b = f.add_tree("kavak", 1080.0)
	a.hp = 1.0
	f.strike_at(Vector2(995.0, 700.0))
	_step(f, 3.0)
	_eq("one landing (13) does not kill a 20 hp neighbour", [f.longest_chain, f.trees_felled], [1, 1])
	_eq("neighbour keeps 7 hp", b.hp, 7.0)
	_free(f)

	# (3) direction is opposite to the hit side.
	f = _new_forest()
	_eq("hit from left falls right", f.fall_dir_for(950.0, 1000.0), 1)
	_eq("hit from right falls left", f.fall_dir_for(1050.0, 1000.0), -1)
	var l: Node2D = f.add_tree("kavak", 1000.0)
	var r: Node2D = f.add_tree("kavak", 2000.0)
	l.hp = 1.0
	r.hp = 1.0
	f.strike_at(Vector2(992.0, 700.0))
	f.strike_at(Vector2(2008.0, 700.0))
	_eq("strike dirs via scene", [l.fall_dir, r.fall_dir], [1, -1])
	# Cursor outside the trunk (beyond width/2 + tolerance) or above the crown misses.
	var m: Node2D = f.add_tree("kavak", 3000.0)
	_eq("miss beside trunk", f.strike_at(Vector2(3000.0 + 17.0 + 14.0 + 1.0, 700.0)), null)
	_eq("miss above crown", f.strike_at(Vector2(3000.0, 760.0 - 261.0)), null)
	_eq("hit within tolerance", f.strike_at(Vector2(3000.0 + 17.0 + 13.0, 700.0)), m)
	_free(f)

	# (4) ending a run credits exactly run_payout(...).total.
	G.from_dict({})
	_eq("gold reset", G.gold, 0.0)
	f = _new_forest()
	var k1: Node2D = f.add_tree("kavak", 1000.0)
	f.add_tree("kavak", 1080.0)
	var cam: Node2D = f.add_tree("cam", 2000.0)
	k1.hp = 1.0
	cam.hp = 1.0
	f.strike_at(Vector2(995.0, 700.0))
	f.strike_at(Vector2(1995.0, 700.0))
	_step(f, 3.0)
	var expect_logs := {"kavak": 1, "cam": 1}
	_eq("logs before end", f.logs, expect_logs)
	var want: Dictionary = B.run_payout(expect_logs, 1)   # (2 + 9) * 1, no chain bonus
	_eq("payout expected", want.total, 11.0)
	f.end_run()
	_step(f, 0.5)
	_eq("phase done", f.phase, f.Phase.DONE)
	_eq("gold == payout.total", G.gold, want.total)
	_eq("last_run total", G.last_run.get("total"), want.total)
	_eq("last_run gold_after", G.last_run.get("gold_after"), want.total)
	_free(f)

	# (4b) chain bonus: 3-chain of kavak -> sales 6, bonus round(6*2*0.05)=1 -> 7.
	G.from_dict({"levels": {"fall_power": 15}})
	f = _new_forest()
	a = f.add_tree("kavak", 1000.0)
	f.add_tree("kavak", 1080.0)
	f.add_tree("kavak", 1160.0)
	a.hp = 1.0
	f.strike_at(Vector2(995.0, 700.0))
	_step(f, 3.0)
	f.end_run()
	_step(f, 0.5)
	_eq("chain payout credited", G.gold, 7.0)
	_free(f)

	# (5) in-flight falls are waited for (<= 2 s) before paying out.
	G.from_dict({})
	f = _new_forest()
	a = f.add_tree("kavak", 1000.0)
	a.hp = 1.0
	f.strike_at(Vector2(995.0, 700.0))
	f.end_run()
	_step(f, 0.3)
	_eq("not paid while tree still falling", f.phase, f.Phase.ENDING)
	_step(f, 0.5)
	_eq("paid after landing", [f.phase, f.logs], [f.Phase.DONE, {"kavak": 1}])
	_free(f)

	# (6) REGRESSION: logs and chain agree when the run ends right after the first strike.
	# 12 kavak 80 px apart, fall_power lv15 (59.8 dmg) -> one chain of 12.
	G.from_dict({"levels": {"fall_power": 15}})
	f = _new_forest()
	for i in 12:
		f.add_tree("kavak", 1000.0 + 80.0 * i)
	f.trees[0].hp = 1.0
	f.strike_at(Vector2(995.0, 700.0))
	f.end_run()
	_step(f, 10.0)
	var fell := 0
	for t in f.trees:
		if t.state != t.State.STANDING:
			fell += 1
	var log_sum := 0
	for k in f.logs:
		log_sum += int(f.logs[k])
	_eq("ending waits for the whole cascade: phase", f.phase, f.Phase.DONE)
	_eq("logs == longest_chain == trees that fell", [log_sum, f.longest_chain, fell], [12, 12, 12])
	_eq("12-chain payout = 24 + round(24*11*0.05)=13", G.last_run.get("total"), 37.0)
	_free(f)

	# (6b) hard cap cuts the wait, but chain and logs still come from the same landings.
	G.from_dict({"levels": {"fall_power": 15}})
	f = _new_forest()
	f.max_end_wait = 0.9
	for i in 12:
		f.add_tree("kavak", 1000.0 + 80.0 * i)
	f.trees[0].hp = 1.0
	f.strike_at(Vector2(995.0, 700.0))
	f.end_run()
	_step(f, 3.0)
	log_sum = 0
	for k in f.logs:
		log_sum += int(f.logs[k])
	_eq("capped wait still finishes", f.phase, f.Phase.DONE)
	_ok("cap really cut the cascade", log_sum < 12)
	_eq("capped: logs == longest_chain (same landings)", [log_sum, f.longest_chain], [log_sum, log_sum])
	_free(f)

	# (7) axe: a swing in progress delivers its impact at run end / before the next swing.
	G.from_dict({})
	f = _new_forest()
	var hits := [0]
	f._axe.impact.connect(func() -> void: hits[0] += 1)
	f._axe.swing(0.4)
	f._axe.swing(0.4)
	_eq("new swing first delivers the pending impact", hits[0], 1)
	f._axe.stop()
	_eq("stop() drops an undelivered swing", f._axe.has_pending_impact(), false)
	var tgt: Node2D = f.add_tree("kavak", 1000.0)
	tgt.hp = 1.0
	f.virtual_cursor_active = true
	f.virtual_cursor = Vector2(995.0, 700.0)
	f._axe.swing(0.4)
	f.end_run()
	_eq("end_run completes the swing impact", tgt.state, tgt.State.FALLING)
	_step(f, 2.0)
	_eq("that last hit is paid", f.logs, {"kavak": 1})
	_free(f)

	# (8) endless forest: generated on demand, depth drives the mix.
	f = _new_forest()
	f.layout_seed = 5
	f._gen_rng.seed = 5
	f.ensure_forest(30000.0)
	_ok("far more than the old 60 columns exist", f.generated_columns() > 250)
	var sorted_ok := true
	for i in range(1, f.trees.size()):
		if f.trees[i].position.x <= f.trees[i - 1].position.x:
			sorted_ok = false
	_ok("trees are ordered left to right", sorted_ok)
	var early := 0
	for i in 6:
		if f.trees[i].tree_id == "kavak":
			early += 1
	_eq("first six columns are all kavak", early, 6)
	var deep_ladin := 0
	var deep_n := 0
	for i in range(100, f.trees.size()):
		deep_n += 1
		if f.trees[i].tree_id == "ladin":
			deep_ladin += 1
	_ok("ladin dominates beyond column 100 (%d/%d)" % [deep_ladin, deep_n], float(deep_ladin) / float(deep_n) > 0.55)
	var n_before: int = f.trees.size()
	f.ensure_forest(30000.0)
	_eq("ensure_forest is idempotent", f.trees.size(), n_before)
	_free(f)

	# (8b) trees far behind the camera are freed.
	f = _new_forest()
	for i in 20:
		f.add_tree("kavak", 500.0 + 100.0 * i)
	f.trees[3].hp = 1.0
	f.strike_at(Vector2(795.0, 700.0))   # x=800 is tree 3
	_step(f, 3.0)
	f.cam_x = 2000.0 + 900.0   # everything left of x=2000 is behind the cull margin
	f._cull_behind()
	var left_of_2000 := 0
	for t in f.trees:
		if t.position.x < 2000.0:
			left_of_2000 += 1
	_eq("culled trees are gone from the list", left_of_2000, 0)
	_eq("standing count follows the cull", f.standing_count(), f.trees.size())
	_free(f)

	# (9) camera: auto-follow nudges right only; keyboard scroll works with the pointer outside.
	f = _new_forest()
	f.manual_mode = false
	f.virtual_cursor_active = true
	f.virtual_cursor = Vector2(800.0, 450.0)
	f.add_tree("kavak", 1600.0)
	f._update_camera(0.1)
	_near_eq("auto-follow: lead tree far right -> nudge 52 px", f.cam_x, 52.0)
	f.cam_x = 1500.0
	f._update_camera(0.1)
	_near_eq("auto-follow: lead tree in the left third -> stay", f.cam_x, 1500.0)
	f.cam_x = 3000.0
	f._update_camera(0.1)
	_near_eq("auto-follow never scrolls left", f.cam_x, 3000.0)
	f.cam_x = 0.0
	f.virtual_cursor = Vector2(-500.0, -500.0)   # pointer outside the window
	var key := InputEventKey.new()
	key.keycode = KEY_D
	key.physical_keycode = KEY_D
	key.pressed = true
	Input.parse_input_event(key)
	Input.flush_buffered_events()
	f._update_camera(0.1)
	var key_up: InputEventKey = key.duplicate()
	key_up.pressed = false
	Input.parse_input_event(key_up)
	Input.flush_buffered_events()
	_near_eq("keyboard D scrolls with pointer outside (1100 px/s * 0.1)", f.cam_x, 110.0)
	f.manual_mode = true
	_free(f)

	# (10) autoplay previews the result but never touches GameState or the save file.
	G.from_dict({})
	_wipe()
	f = _new_forest()
	f._autoplay = true
	a = f.add_tree("kavak", 1000.0)
	a.hp = 1.0
	f.strike_at(Vector2(995.0, 700.0))
	f.end_run()
	_step(f, 3.0)
	_eq("autoplay finished", f.phase, f.Phase.DONE)
	_eq("autoplay credited nothing", [G.gold, G.runs], [0.0, 0])
	_ok("autoplay wrote no save", not FileAccess.file_exists(SAVE_PATH))
	_free(f)

	_restore_save(G)
	print("TEST_FOREST ", "OK" if _fails == 0 else "FAIL %d" % _fails)
	quit(_fails)


func _new_forest() -> Node2D:
	var f: Node2D = (load(FOREST_PATH) as PackedScene).instantiate()
	f.manual_mode = true
	f.swing_enabled = false
	root.add_child(f)
	return f


func _free(f: Node2D) -> void:
	root.remove_child(f)
	f.free()


## Steps the simulation in 1/30 s ticks.
func _step(f: Node2D, seconds: float) -> void:
	var n := int(ceil(seconds * 30.0))
	for i in n:
		f.advance(1.0 / 30.0)


func _xs(list: Array) -> Array:
	var out: Array = []
	for t in list:
		out.append(t.position.x)
	out.sort()
	return out


func _eq(label: String, got, want) -> void:
	if str(got) == str(want):
		print("PASS ", label)
	else:
		print("FAIL ", label, " got=", got, " want=", want)
		_fails += 1


func _redirect_save(G) -> void:
	_real_existed = FileAccess.file_exists(REAL_SAVE)
	if _real_existed:
		_real_before = FileAccess.get_file_as_bytes(REAL_SAVE)
	_old_path = G.save_path
	G.save_path = SAVE_PATH
	_wipe()


func _wipe() -> void:
	for suffix in ["", ".tmp", ".bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH + suffix))


func _restore_save(G) -> void:
	_wipe()
	G.save_path = _old_path
	var now_exists := FileAccess.file_exists(REAL_SAVE)
	_ok("real save existence unchanged", now_exists == _real_existed)
	if now_exists and _real_existed:
		_ok("real save bytes unchanged", FileAccess.get_file_as_bytes(REAL_SAVE) == _real_before)


func _ok(label: String, cond: bool) -> void:
	_eq(label, cond, true)


func _near_eq(label: String, got: float, want: float) -> void:
	_eq(label, absf(got - want) < 0.01, true)
	if absf(got - want) >= 0.01:
		print("   got=", got, " want=", want)
