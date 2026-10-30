extends SceneTree
## Perfect-aim bot balance simulator (headless). Never touches the real save.
## Run: ~/bin/godot --headless --path . -s tools/sim_balance.gd [-- table|progress|all]
## Bot: every swing hits the leftmost standing tree from its left side, so trees fall forward
## and chain. `skip` = swings the player loses repositioning after each felled tree.

var G
var B


func _initialize() -> void:
	await process_frame
	G = root.get_node("GameState")
	B = root.get_node("Balance")
	G.save_path = "user://sim_save.json"
	G.persist = false
	var mode := "all"
	for a in OS.get_cmdline_user_args():
		mode = a
	if mode == "table" or mode == "all":
		_table()
	if mode == "progress" or mode == "all":
		_progress()
	quit(0)


func _levels(frac: float) -> Dictionary:
	var lv := {}
	for u in B.upgrades:
		lv[u.id] = int(round(float(u.max_level) * frac))
	return lv


func _table() -> void:
	var cfgs := [
		["base", {}],
		["all lv5", _all(5)],
		["all lv10", _all(10)],
		["all max", _levels(1.0)],
	]
	print("%-9s %-5s %9s %9s %9s %7s %7s %7s" % ["config", "skip", "mean_gold", "median", "max", "felled", "chain", "secs"])
	for c in cfgs:
		for skip in [0, 1]:
			var golds := []
			var fel := 0.0
			var ch := 0.0
			var secs := 0.0
			var n := 60
			for seed in n:
				var r := run_once(c[1], seed + 1, skip)
				golds.append(r.total)
				fel += r.felled
				ch += r.chain
				secs += r.secs
			var sum := 0.0
			for g in golds:
				sum += g
			golds.sort()
			print("%-9s %-5d %9.0f %9.0f %9.0f %7.1f %7.1f %7.1f" % [c[0], skip, sum / n, golds[n / 2], golds[n - 1], fel / n, ch / n, secs / n])


func _all(lv: int) -> Dictionary:
	var out := {}
	for u in B.upgrades:
		out[u.id] = mini(lv, int(u.max_level))
	return out


## One simulated run; returns {total, felled, chain, secs}.
func run_once(levels: Dictionary, seed: int, skip_after_kill: int) -> Dictionary:
	G.from_dict({"levels": levels})
	var f: Node2D = (load("res://scenes/forest/forest.tscn") as PackedScene).instantiate()
	f.manual_mode = true
	f.swing_enabled = false
	f.layout_seed = seed
	root.add_child(f)
	f.time_left = G.stat("run_time")
	var dt := 1.0 / 60.0
	var t := 0.0
	var next_hit := 0.534
	var skip := 0
	var iv: float = G.stat("swing_interval")
	while f.phase != f.Phase.DONE and t < 300.0:
		if f.phase == f.Phase.RUNNING and t >= next_hit:
			next_hit += iv
			if skip > 0:
				skip -= 1
			else:
				var tgt = null
				for tr in f.trees:
					if tr.is_standing():
						tgt = tr
						break
				if tgt == null or tgt.position.x > f._next_x - 1500.0:
					f.ensure_forest((tgt.position.x if tgt else f._next_x) + 2500.0)
					if tgt == null:
						for tr in f.trees:
							if tr.is_standing():
								tgt = tr
								break
				var before: int = f.standing_count()
				f.strike_at(Vector2(tgt.position.x - 5.0 - f.cam_x, 700.0))
				if f.standing_count() < before:
					skip = skip_after_kill
		f.advance(dt)
		t += dt
	var r2 := {"total": float(G.last_run.get("total", 0.0)), "felled": f.trees_felled, "chain": f.longest_chain, "secs": t}
	# GameState.apply_run_result adds to gold/runs in memory only (persist=false).
	root.remove_child(f)
	f.free()
	return r2


## Greedy buyer: after each run buy the cheapest affordable upgrade until nothing is affordable.
func _progress() -> void:
	for skip in [0, 1]:
		G.from_dict({})
		var runs := 0
		var maxed_at := -1
		var first_buy := -1
		var log_lines: Array = []
		while runs < 200:
			runs += 1
			var bank_before: float = G.gold
			var lv_save: Dictionary = G.levels.duplicate()
			var r := run_once(lv_save, 1000 + runs, skip)
			var gold_save: float = bank_before + r.total
			G.from_dict({"levels": lv_save, "gold": gold_save})
			var bought := 0
			while true:
				var best := ""
				var best_cost := INF
				for u in B.upgrades:
					if not B.is_maxed(u.id, G.level_of(u.id)) and G.next_cost(u.id) < best_cost and G.can_buy(u.id):
						best = u.id
						best_cost = G.next_cost(u.id)
				if best == "":
					break
				G.buy(best)
				bought += 1
			if bought > 0 and first_buy < 0:
				first_buy = runs
			if runs <= 3 or runs % 5 == 0:
				log_lines.append("  run %3d gold_run %7.0f bank %9.0f levels %s" % [runs, r.total, G.gold, str(G.levels)])
			var done := true
			for u in B.upgrades:
				if not B.is_maxed(u.id, G.level_of(u.id)):
					done = false
			if done:
				maxed_at = runs
				break
		print("PROGRESS skip=%d first_upgrade_after_run=%d everything_maxed_at_run=%d" % [skip, first_buy, maxed_at])
		for l in log_lines:
			print(l)
