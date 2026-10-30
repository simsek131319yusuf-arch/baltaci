extends SceneTree
## Economy tests. Expected numbers are hand-computed from data/upgrades.json + balance.json:
##   cost(level) = round(base_cost * growth^level); stat = base + level * value.
## buy() saves, so GameState.save_path points at user://test_save.json for the whole test;
## the real user://save.json is never opened for writing (checked again at the end).

const SAVE_PATH := "user://test_save.json"
const REAL_SAVE := "user://save.json"

var _fails := 0
var _checks := 0
var _real_before: PackedByteArray = PackedByteArray()
var _real_existed := false
var _gs: Node
var _bal: Node


func _initialize() -> void:
	await process_frame
	_gs = root.get_node("GameState")
	_bal = root.get_node("Balance")
	_real_existed = FileAccess.file_exists(REAL_SAVE)
	if _real_existed:
		_real_before = FileAccess.get_file_as_bytes(REAL_SAVE)
	var saved_state: Dictionary = _gs.to_dict()
	var old_path: String = _gs.save_path
	_gs.save_path = SAVE_PATH
	_wipe_test_files()

	_test_costs()
	_test_stats()
	_test_buy()
	_test_buy_limits()
	_test_roundtrip()
	_test_missing_keys()
	_test_migration()
	_test_reset()
	_test_validation()
	_test_payout_cap()
	_test_save_files()

	_wipe_test_files()
	_gs.save_path = old_path
	_gs.from_dict(saved_state)
	_check_real_save_untouched()
	print("TEST_ECONOMY ", "OK (%d checks)" % _checks if _fails == 0 else "FAIL %d of %d checks" % [_fails, _checks])
	quit(1 if _fails > 0 else 0)


# ---------------------------------------------------------------- tests

func _test_costs() -> void:
	# id: [level0, level1, level5]
	var want := {
		"axe_damage": [10, 14, 47],         # 10, 13.6->14, 10*1.36^5=46.53
		"swing_interval": [15, 23, 114],    # 15, 22.5->23, 15*1.5^5=113.9
		"run_time": [40, 60, 304],          # 40, 60, 40*1.5^5=303.75
		"fall_power": [140, 224, 1468],     # 140, 224, 140*1.6^5=1468.0
		"crit_chance": [220, 352, 2307],    # 220, 352, 220*1.6^5=2306.9
	}
	for id in want:
		var lv := [0, 1, 5]
		for i in 3:
			_eq("cost %s lv%d" % [id, lv[i]], _bal.upgrade_cost(id, lv[i]), float(want[id][i]))
	_eq("cost axe lv2", _bal.upgrade_cost("axe_damage", 2), 18.0)   # 18.496
	_eq("cost unknown", _bal.upgrade_cost("nope", 0), INF)


func _test_stats() -> void:
	_near("axe lv0", _bal.compute_stat("axe_damage", {}), 5.0)
	_near("axe lv1", _bal.compute_stat("axe_damage", {"axe_damage": 1}), 8.0)
	_near("axe lv5", _bal.compute_stat("axe_damage", {"axe_damage": 5}), 20.0)
	_near("axe lv25", _bal.compute_stat("axe_damage", {"axe_damage": 25}), 80.0)
	_near("swing lv0", _bal.compute_stat("swing_interval", {}), 0.7)
	_near("swing lv5", _bal.compute_stat("swing_interval", {"swing_interval": 5}), 0.5)
	_near("swing lv12", _bal.compute_stat("swing_interval", {"swing_interval": 12}), 0.22)
	_near("swing level past max is clamped to max_level", _bal.compute_stat("swing_interval", {"swing_interval": 99}), 0.22)
	_ok("swing never below the floor", _bal.compute_stat("swing_interval", {"swing_interval": 99}) >= 0.18)
	_near("axe past max clamps to lv25", _bal.compute_stat("axe_damage", {"axe_damage": 99}), 80.0)
	_near("negative level clamps to 0", _bal.compute_stat("axe_damage", {"axe_damage": -4}), 5.0)
	_near("run_time lv5", _bal.compute_stat("run_time", {"run_time": 5}), 35.0)
	_near("run_time lv15", _bal.compute_stat("run_time", {"run_time": 15}), 65.0)
	_near("fall lv5", _bal.compute_stat("fall_power", {"fall_power": 5}), 0.11)
	_near("fall lv15", _bal.compute_stat("fall_power", {"fall_power": 15}), 0.23)
	_near("crit lv0", _bal.compute_stat("crit_chance", {}), 0.0)
	_near("crit lv1", _bal.compute_stat("crit_chance", {"crit_chance": 1}), 0.04)
	_near("crit lv10", _bal.compute_stat("crit_chance", {"crit_chance": 10}), 0.4)
	_near("crit past max = lv10", _bal.compute_stat("crit_chance", {"crit_chance": 100}), 0.4)
	_near("crit mult untouched", _bal.compute_stat("crit_multiplier", {"axe_damage": 3}), 2.0)
	_near("mixed axe", _bal.compute_stat("axe_damage", {"axe_damage": 2, "run_time": 1}), 11.0)
	_near("mixed run", _bal.compute_stat("run_time", {"axe_damage": 2, "run_time": 1}), 23.0)


func _test_buy() -> void:
	_gs.from_dict({"gold": 300.0})
	var changed_count := [0]
	var cb := func() -> void: changed_count[0] += 1
	_gs.changed.connect(cb)
	_ok("buy axe #1", _gs.buy("axe_damage"))
	_near("gold after axe #1", _gs.gold, 290.0)
	_eq("axe level 1", _gs.level_of("axe_damage"), 1)
	_ok("buy axe #2", _gs.buy("axe_damage"))
	_near("gold after axe #2", _gs.gold, 276.0)    # 290 - 14
	_eq("axe level 2", _gs.level_of("axe_damage"), 2)
	_near("axe stat after 2 buys", _gs.stat("axe_damage"), 11.0)
	_ok("buy crit", _gs.buy("crit_chance"))
	_near("gold after crit", _gs.gold, 56.0)       # 276 - 220
	_ok("cannot buy fall_power (140 > 56)", not _gs.buy("fall_power"))
	_near("gold unchanged on failure", _gs.gold, 56.0)
	_eq("fall_power level unchanged", _gs.level_of("fall_power"), 0)
	_eq("changed fired once per successful buy", changed_count[0], 3)
	_gs.changed.disconnect(cb)
	_ok("unknown upgrade not buyable", not _gs.buy("nope"))


func _test_buy_limits() -> void:
	_gs.from_dict({"gold": 1.0e12, "levels": {"axe_damage": 25}})
	_ok("maxed axe reports maxed", _bal.is_maxed("axe_damage", 25))
	_ok("cannot buy past max", not _gs.buy("axe_damage"))
	_eq("level stays 25", _gs.level_of("axe_damage"), 25)
	_near("gold untouched at max", _gs.gold, 1.0e12)
	_gs.from_dict({"gold": 1.0e12, "levels": {"run_time": 14}})
	_ok("buy last run_time level", _gs.buy("run_time"))
	_eq("run_time level 15", _gs.level_of("run_time"), 15)
	_ok("run_time now maxed", not _gs.buy("run_time"))
	_ok("not maxed at 14", not _bal.is_maxed("run_time", 14))


func _test_roundtrip() -> void:
	_gs.from_dict({"gold": 1234.5, "levels": {"axe_damage": 3, "crit_chance": 2}, "best_chain": 7, "runs": 4})
	var d: Dictionary = _gs.to_dict()
	var via_json = JSON.parse_string(JSON.stringify(d))   # what a real save file goes through
	_gs.from_dict({})
	_near("wiped gold", _gs.gold, 0.0)
	_gs.from_dict(via_json)
	_near("gold roundtrip", _gs.gold, 1234.5)
	_eq("axe roundtrip", _gs.level_of("axe_damage"), 3)
	_eq("crit roundtrip", _gs.level_of("crit_chance"), 2)
	_eq("best_chain roundtrip", _gs.best_chain, 7)
	_eq("runs roundtrip", _gs.runs, 4)
	_eq("level type is int", typeof(_gs.levels["axe_damage"]), TYPE_INT)


func _test_missing_keys() -> void:
	_gs.from_dict({"gold": 50.0})
	_near("partial gold", _gs.gold, 50.0)
	_eq("partial levels empty", _gs.levels.size(), 0)
	_eq("partial best_chain", _gs.best_chain, 0)
	_eq("partial runs", _gs.runs, 0)
	_gs.from_dict({})
	_near("empty gold", _gs.gold, 0.0)
	_eq("empty level_of", _gs.level_of("axe_damage"), 0)


func _test_migration() -> void:
	_eq("balance save_version", _bal.save_version, 1)
	_eq("to_dict save_version", _gs.to_dict()["save_version"], 1)
	_eq("migrate keeps v1", _gs._migrate({"save_version": 1})["save_version"], 1)
	_eq("migrate defaults missing version", _gs._migrate({})["save_version"], 1)
	_eq("migrate keeps gold", _gs._migrate({"gold": 9.0})["gold"], 9.0)


func _test_reset() -> void:
	_gs.from_dict({"gold": 500.0, "levels": {"axe_damage": 4}, "best_chain": 3, "runs": 2})
	_gs.reset()
	_near("reset gold", _gs.gold, 0.0)
	_eq("reset levels", _gs.levels.size(), 0)
	_eq("reset best_chain", _gs.best_chain, 0)
	_eq("reset runs", _gs.runs, 0)


# ---------------------------------------------------------------- new coverage

func _test_validation() -> void:
	_gs.from_dict({"gold": "abc", "levels": [1, 2], "runs": "x", "best_chain": null})
	_near("string gold -> 0", _gs.gold, 0.0)
	_eq("array levels -> empty", _gs.levels.size(), 0)
	_eq("string runs -> 0", _gs.runs, 0)
	_eq("null best_chain -> 0", _gs.best_chain, 0)
	_gs.from_dict({"gold": -50.0})
	_near("negative gold -> 0", _gs.gold, 0.0)
	_gs.from_dict({"gold": INF})
	_near("inf gold -> 0", _gs.gold, 0.0)
	_gs.from_dict({"gold": NAN})
	_near("nan gold -> 0", _gs.gold, 0.0)
	_gs.from_dict({"levels": {"axe_damage": 100, "run_time": -3, "swing_interval": "7", "bogus": 4, "crit_chance": 3.9}})
	_eq("level clamped to max", _gs.level_of("axe_damage"), 25)
	_eq("negative level -> 0", _gs.level_of("run_time"), 0)
	_eq("string level dropped", _gs.level_of("swing_interval"), 0)
	_ok("unknown upgrade dropped", not _gs.levels.has("bogus"))
	_eq("float level truncated", _gs.level_of("crit_chance"), 3)
	_gs.from_dict({"runs": -4, "best_chain": 1.0e30})
	_eq("negative runs -> 0", _gs.runs, 0)
	_eq("huge best_chain clamped", _gs.best_chain, 2000000000)
	_gs.from_dict({"levels": {"axe_damage": 1000000000}})
	_near("absurd level cannot inflate stat", _gs.stat("axe_damage"), 80.0)


func _test_payout_cap() -> void:
	# 10 kavak = 20 sales. chain 5 -> 4 links * 0.05 = +20% = 4. chain 100 -> capped at +100% = 20.
	var p4: Dictionary = _bal.run_payout({"kavak": 10}, 5)
	_eq("chain 5 payout", [p4.sales, p4.chain_bonus, p4.total], [20.0, 4.0, 24.0])
	var p100: Dictionary = _bal.run_payout({"kavak": 10}, 100)
	_eq("chain 100 capped at +100%", [p100.sales, p100.chain_bonus, p100.total], [20.0, 20.0, 40.0])
	var p21: Dictionary = _bal.run_payout({"kavak": 10}, 21)   # 20 links * .05 = exactly 1.0
	_eq("chain 21 exactly at cap", p21.chain_bonus, 20.0)
	var p22: Dictionary = _bal.run_payout({"kavak": 10}, 22)
	_eq("chain 22 still capped", p22.chain_bonus, 20.0)
	_eq("no chain, no bonus", _bal.run_payout({"kavak": 10}, 1).chain_bonus, 0.0)


func _test_save_files() -> void:
	_wipe_test_files()
	_gs.from_dict({"gold": 5.0, "levels": {"axe_damage": 2}})
	_gs.save_game()
	_ok("save file written", FileAccess.file_exists(SAVE_PATH))
	_ok("no tmp left", not FileAccess.file_exists(SAVE_PATH + ".tmp"))
	_ok("first save has no .bak yet", not FileAccess.file_exists(SAVE_PATH + ".bak"))
	_gs.from_dict({"gold": 9.0, "levels": {"axe_damage": 3}})
	_gs.save_game()
	_ok(".bak created by second save", FileAccess.file_exists(SAVE_PATH + ".bak"))
	var bak = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH + ".bak"))
	_near(".bak holds the previous save", float(bak["gold"]), 5.0)
	# Corrupt main file -> moved aside, .bak (gold 5) restored.
	_write(SAVE_PATH, '{"gold": 12')
	_gs.from_dict({"gold": 77.0})
	_gs.load_game()
	_ok("corrupt file moved to .corrupt.json", FileAccess.file_exists("user://test_save.corrupt.json"))
	_ok("corrupt original gone", not FileAccess.file_exists(SAVE_PATH))
	_near("fell back to .bak", _gs.gold, 5.0)
	# Missing main, valid tmp (crash between write and rename) -> tmp wins over .bak.
	_wipe_test_files()
	_write(SAVE_PATH + ".tmp", '{"gold": 999.0}')
	_write(SAVE_PATH + ".bak", '{"gold": 1.0}')
	_gs.from_dict({})
	_gs.load_game()
	_near("tmp recovered when main is missing", _gs.gold, 999.0)
	# Main is a JSON array -> moved aside as corrupt.
	_wipe_test_files()
	_write(SAVE_PATH, "[1,2]")
	_gs.load_game()
	_ok("non-object save moved aside", FileAccess.file_exists("user://test_save.corrupt.json"))
	# persist=false never writes.
	_wipe_test_files()
	_gs.persist = false
	_gs.from_dict({"gold": 4.0})
	_gs.save_game()
	_gs.persist = true
	_ok("persist=false writes nothing", not FileAccess.file_exists(SAVE_PATH))


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _wipe_test_files() -> void:
	for suffix in ["", ".tmp", ".bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH + suffix))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_save.corrupt.json"))


func _check_real_save_untouched() -> void:
	var now_exists := FileAccess.file_exists(REAL_SAVE)
	_ok("real save existence unchanged", now_exists == _real_existed)
	if now_exists and _real_existed:
		_ok("real save bytes unchanged", FileAccess.get_file_as_bytes(REAL_SAVE) == _real_before)


# ---------------------------------------------------------------- asserts

func _eq(label: String, got, want) -> void:
	_checks += 1
	if typeof(got) == typeof(want) and got == want:
		return
	if (typeof(got) == TYPE_FLOAT or typeof(got) == TYPE_INT) and (typeof(want) == TYPE_FLOAT or typeof(want) == TYPE_INT) and float(got) == float(want):
		return
	_fails += 1
	print("  FAIL ", label, " got=", got, " want=", want)


func _near(label: String, got: float, want: float) -> void:
	_checks += 1
	if absf(got - want) <= 1e-6:
		return
	_fails += 1
	print("  FAIL ", label, " got=", got, " want=", want)


func _ok(label: String, cond: bool) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		print("  FAIL ", label)
