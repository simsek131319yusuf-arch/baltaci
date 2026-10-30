extends SceneTree
## Headless tests for the animation/juice layer: curves are continuous and frame-rate independent,
## springs settle, pools are bounded, hit-stop/shake are wired. Expected values are written in advance.
## Run: ~/bin/godot --headless --path . -s tests/test_juice.gd
## GameState.save_path is redirected, so the real save is never written.

const SAVE_PATH := "user://test_juice_save.json"
const REAL_SAVE := "user://save.json"
const FOREST_PATH := "res://scenes/forest/forest.tscn"
const CAMP_PATH := "res://scenes/camp/camp.tscn"

var _fails := 0
var _real_before: PackedByteArray = PackedByteArray()
var _real_existed := false
var _old_path := ""


func _initialize() -> void:
	await process_frame
	var G := root.get_node("GameState")
	var Juice: GDScript = load("res://scenes/ui/juice.gd")
	_redirect_save(G)
	G.from_dict({"levels": {"fall_power": 15}})

	# (1) damp() is frame-rate independent: 1 s of approach at 60 Hz == at 240 Hz.
	var a := 0.0
	for i in 60:
		a = Juice.damp(a, 1.0, 5.0, 1.0 / 60.0)
	var b := 0.0
	for i in 240:
		b = Juice.damp(b, 1.0, 5.0, 1.0 / 240.0)
	_ok("damp: 60 Hz vs 240 Hz agree (%.5f vs %.5f)" % [a, b], absf(a - b) < 1e-4)
	_near("damp: 1 - e^-5", a, 1.0 - exp(-5.0), 1e-4)
	_near("out_back ends at 1", Juice.out_back(1.0), 1.0, 1e-6)
	_ok("out_back overshoots", Juice.out_back(0.7) > 1.0)

	# (2) axe swing: wind-up above the wind-up angle (ease-out back), accelerating strike,
	# exactly one impact at rotation 0, no angular snap between frames, same timing at any frame rate.
	var f := _new_forest()
	var axe: Node2D = f._axe
	var impacts := [0]
	var impact_rot := [99.0]
	axe.impact.connect(func() -> void:
		impacts[0] += 1
		impact_rot[0] = axe._body.rotation)
	var timing := {}
	for dt in [1.0 / 30.0, 1.0 / 60.0, 1.0 / 240.0]:
		axe.stop()
		impacts[0] = 0
		axe.swing(0.55)
		var t := 0.0
		var prev: float = axe._body.rotation
		var max_step := 0.0
		var peak := 0.0
		var t_impact := -1.0
		while t < 0.7:
			axe.tick(dt)
			t += dt
			var r: float = axe._body.rotation
			max_step = maxf(max_step, absf(r - prev) / dt * (1.0 / 60.0))   # normalised to a 60 Hz frame
			prev = r
			peak = maxf(peak, r)
			if t_impact < 0.0 and impacts[0] == 1:
				t_impact = t
		timing[dt] = t_impact
		_eq("axe impacts once @%.0f Hz" % (1.0 / dt), impacts[0], 1)
		_ok("axe wind-up overshoots the wind-up angle (peak %.3f > 0.95)" % peak, peak > 0.95)
		_ok("axe no snapping: max %.3f rad per 60 Hz frame < 0.32" % max_step, max_step < 0.32)
		_near("axe impact pose is rotation 0", impact_rot[0], 0.0, 0.01)
		_ok("axe returns to rest pose (%.2f)" % axe._body.rotation, absf(axe._body.rotation - axe.REST_ROT) < 0.1)
	# 0.55 s * (0.28 + 0.2) = 0.264 s to contact.
	for dt in timing:
		_near("axe contact time @%.0f Hz" % (1.0 / dt), timing[dt], 0.264, 0.06)
	_free(f)

	# (3) cursor smoothing: exponential, never overshoots, converges.
	f = _new_forest()
	axe = f._axe
	axe.position = Vector2(100, 100)
	axe.target = Vector2(900, 100)
	var last_x: float = axe.position.x
	var mono := true
	for i in 120:
		axe.tick(1.0 / 60.0)
		if axe.position.x < last_x - 1e-3 or axe.position.x > 900.0 + 1e-3:
			mono = false
		last_x = axe.position.x
	_ok("cursor follow monotonic, no overshoot", mono)
	_ok("cursor follow converges in 2 s (%.1f)" % axe.position.x, absf(axe.position.x - 900.0) < 1.0)
	_free(f)

	# (4) tree: wobble = damped spring (oscillates 2+ times, settles, bounded); fall = crack, then
	# accelerating fall that lands once, bounces and settles; rotation never jumps.
	f = _new_forest()
	var tr: Node2D = f.add_tree("kavak", 1000.0)
	tr.last_hit_side = -1
	tr.shake(0.03)
	var crossings := 0
	var prev_sign := 0
	var max_ang := 0.0
	var t2 := 0.0
	while t2 < 2.0:
		tr.tick(1.0 / 60.0)
		t2 += 1.0 / 60.0
		var ang: float = tr._body.rotation
		max_ang = maxf(max_ang, absf(ang))
		var sg := 1 if ang > 0.0005 else (-1 if ang < -0.0005 else 0)
		if sg != 0 and prev_sign != 0 and sg != prev_sign:
			crossings += 1
		if sg != 0:
			prev_sign = sg
	_ok("wobble oscillates 2+ times (zero crossings: %d)" % crossings, crossings >= 2)
	_ok("wobble amplitude is small (%.3f rad)" % max_ang, max_ang > 0.02 and max_ang < 0.1)
	_ok("wobble settles", tr.is_settled() and tr._body.rotation == 0.0 and tr._body.scale == Vector2.ONE)

	tr = f.add_tree("kavak", 2000.0)
	tr.start_fall(1, 1)
	var landed_at := -1.0
	var t3 := 0.0
	var prev_rot: float = tr._body.rotation
	var worst := 0.0
	var mono_fall := true
	var min_after := 99.0
	var land_count := 0
	while t3 < 2.0:
		var landed: bool = tr.tick(1.0 / 60.0)
		t3 += 1.0 / 60.0
		var r2: float = tr._body.rotation
		worst = maxf(worst, absf(r2 - prev_rot))
		if tr.fall_t > tr.CRACK_TIME + 0.05 and tr.state == tr.State.FALLING and r2 < prev_rot - 1e-6:
			mono_fall = false
		if tr.state == tr.State.FELLED:
			min_after = minf(min_after, r2)
		prev_rot = r2
		if landed:
			land_count += 1
			landed_at = t3
	_eq("lands exactly once", land_count, 1)
	_near("landing time = crack + fall", landed_at, tr.CRACK_TIME + tr.FALL_TIME, 0.03)
	_ok("fall angle increases smoothly after the crack", mono_fall)
	_ok("no angular snap (worst %.3f rad per frame)" % worst, worst < 0.16)
	_ok("bounces off the ground (min %.3f < pi/2)" % min_after, min_after < PI * 0.5 - 0.03)
	_ok("fully faded and gone by 2 s", tr.state == tr.State.GONE)
	_free(f)

	# (5) FX pools stay bounded and drain.
	f = _new_forest()
	var fx: Node2D = f._fx
	for i in 200:
		fx.chips(Vector2(500, 600), 1, 8)
	_ok("pool is capped (%d <= %d)" % [fx.active_count(), fx.CAP], fx.active_count() <= fx.CAP)
	fx.leaves(Vector2(500, 300), 20.0, 10)
	fx.dust_line(Vector2(500, 760), 1, 300.0, 10)
	fx.log_pop(Vector2(600, 740), 1)
	fx.number(Vector2(500, 500), "12", 1)
	for i in 240:
		fx.tick(1.0 / 60.0)
	_eq("all particles expire within 4 s", fx.active_count(), 0)
	_free(f)

	# (6) hit-stop + trauma wiring: a hit freezes for hitstop_ms (kill: hitstop_kill_ms), landing adds trauma,
	# the shake offset is zero without trauma and bounded with it.
	f = _new_forest()
	var t6: Node2D = f.add_tree("kavak", 1000.0)
	f.add_tree("kavak", 1080.0)
	f.strike_at(Vector2(995.0, 700.0))      # 5 dmg on a 20 hp tree: a plain hit
	_near("normal hit-stop", f._hitstop_t, f.hitstop_ms * 0.001, 1e-6)
	f._hitstop_t = 0.0
	t6.hp = 1.0
	f.strike_at(Vector2(995.0, 700.0))
	_near("kill hit-stop", f._hitstop_t, f.hitstop_kill_ms * 0.001, 1e-6)
	var peak_trauma := 0.0
	var peak_off := 0.0
	for i in 300:
		f.advance(1.0 / 60.0)
		peak_trauma = maxf(peak_trauma, f._trauma)
		peak_off = maxf(peak_off, f._shake_off.length())
	_ok("landing adds trauma (%.2f)" % peak_trauma, peak_trauma >= f.trauma_land - 0.001)
	_ok("shake offset bounded (%.1f px)" % peak_off, peak_off < 30.0)
	_eq("trauma fully decays", f._trauma, 0.0)
	_eq("shake offset back to zero", f._shake_off, Vector2.ZERO)
	_eq("woken trees are released from the active list", f._active.size(), 0)
	_free(f)

	# (7) camp: fall_power is shown as real damage on the reference tree (kavak, 260 px), not a percent.
	G.from_dict({})
	var camp: Control = (load(CAMP_PATH) as PackedScene).instantiate()
	root.add_child(camp)
	await process_frame
	_eq("fall damage base 0.05 -> 13", camp._fmt_stat("fall_power", 0.05), "13")
	_eq("fall damage level 1 0.062 -> 16", camp._fmt_stat("fall_power", 0.062), "16")
	_ok("fall card names the reference tree", camp._cards["fall_power"].stat.text.contains("(Kavak)"))
	root.remove_child(camp)
	camp.free()

	_restore_save(G)
	print("TEST_JUICE ", "OK" if _fails == 0 else "FAIL %d" % _fails)
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


func _eq(label: String, got, want) -> void:
	if str(got) == str(want):
		print("PASS ", label)
	else:
		print("FAIL ", label, " got=", got, " want=", want)
		_fails += 1


func _ok(label: String, cond: bool) -> void:
	_eq(label, cond, true)


func _near(label: String, got: float, want: float, tol: float) -> void:
	if absf(got - want) <= tol:
		print("PASS ", label)
	else:
		print("FAIL ", label, " got=", got, " want=", want, " tol=", tol)
		_fails += 1


func _redirect_save(G) -> void:
	_real_existed = FileAccess.file_exists(REAL_SAVE)
	if _real_existed:
		_real_before = FileAccess.get_file_as_bytes(REAL_SAVE)
	_old_path = G.save_path
	G.save_path = SAVE_PATH
	G.persist = false
	_wipe()


func _wipe() -> void:
	for suffix in ["", ".tmp", ".bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH + suffix))


func _restore_save(G) -> void:
	_wipe()
	G.save_path = _old_path
	G.persist = true
	var now_exists := FileAccess.file_exists(REAL_SAVE)
	_ok("real save existence unchanged", now_exists == _real_existed)
	if now_exists and _real_existed:
		_ok("real save bytes unchanged", FileAccess.get_file_as_bytes(REAL_SAVE) == _real_before)
