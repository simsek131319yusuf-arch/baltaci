extends SceneTree
## Story system tests (no UI: Story.ui_enabled = false, beats finish instantly when played).
## Expected outcomes are hand-written from data/story.json:
##   intro            camp_enter, no conditions
##   first_shift      camp_enter, runs >= 1
##   chain5           chain n >= 5
##   depth30          depth col >= 30
##   ladin            tree_first_seen tree == ladin
##   kemal_challenge  camp_enter, runs >= 5, flag_not kemal_challenge; reward flag kemal_challenge
##   kemal_defeat     chain n >= 15 AND flag kemal_challenge; reward 400 gold + flag map_piece
##   depth100         depth col >= 100 AND flag map_piece
## GameState.save_path points at user://test_story_save.json; the real save is never touched.

const SAVE_PATH := "user://test_story_save.json"
const REAL_SAVE := "user://save.json"

var _fails := 0
var _checks := 0
var _real_before := PackedByteArray()
var _real_existed := false
var _gs: Node
var _st: Node
var _started: Array = []
var _finished: Array = []


func _initialize() -> void:
	await process_frame
	_gs = root.get_node("GameState")
	_st = root.get_node("Story")
	_real_existed = FileAccess.file_exists(REAL_SAVE)
	if _real_existed:
		_real_before = FileAccess.get_file_as_bytes(REAL_SAVE)
	_gs.save_path = SAVE_PATH
	_st.ui_enabled = false
	_st.beat_started.connect(func(id): _started.append(id))
	_st.beat_finished.connect(func(id): _finished.append(id))

	_test_data()
	_test_intro_once()
	_test_first_shift()
	_test_midrun_queue()
	_test_kemal_chain()
	_test_depth100()
	_test_skip_marks_seen()
	_test_run_end_ctx()
	_test_reset()
	_test_malformed()
	_test_real_save()

	for p in [SAVE_PATH, SAVE_PATH + ".tmp", SAVE_PATH + ".bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	print("TEST_STORY ", "OK (%d checks)" % _checks if _fails == 0 else "FAIL %d of %d checks" % [_fails, _checks])
	quit(1 if _fails > 0 else 0)


func _fresh() -> void:
	_gs.from_dict({})
	_gs.last_run = {}
	_st.queue.clear()
	_st.current = {}
	_st._toasted.clear()
	_started.clear()
	_finished.clear()


func _test_data() -> void:
	_fresh()
	var ids: Array = []
	for b in _st.beats:
		ids.append(b.id)
	_eq("beat ids in file order", ids, ["intro", "first_shift", "chain5", "depth30", "ladin", "kemal_challenge", "kemal_defeat", "depth100"])
	for who in ["pipsy", "hoca", "kemal", "bodo"]:
		_ok("character " + who, _st.characters.has(who))
	for b in _st.beats:
		var n: int = b.lines.size()
		_ok("%s has 2-6 lines" % b.id, n >= 2 and n <= 6)
		for l in b.lines:
			_ok("%s line length <= 115: %s" % [b.id, str(l.text).substr(0, 20)], str(l.text).length() <= 115)
			_ok("%s speaker known" % b.id, _st.characters.has(str(l.who)))
			if l.has("emote"):
				_ok("%s emote valid" % b.id, ["happy", "cry", "wow"].has(str(l.emote)))
	_ok("intro has a letter", typeof(_st.get_beat("intro").get("letter")) == TYPE_DICTIONARY)
	_eq("kemal_defeat reward gold", _st.get_beat("kemal_defeat").reward.gold, 400)


func _test_intro_once() -> void:
	_fresh()
	_st.notify("camp_enter", {"runs": 0})
	_eq("fresh camp_enter plays exactly intro", _started, ["intro"])
	_eq("intro finished", _finished, ["intro"])
	_ok("intro flag set", _gs.get_flag("story_intro"))
	_ok("not playing afterwards", not _st.is_playing())
	_st.notify("camp_enter", {"runs": 0})
	_eq("intro not repeated", _started, ["intro"])


func _test_first_shift() -> void:
	_fresh()
	_gs.set_flag("story_intro", true)
	_st.notify("camp_enter", {})
	_eq("runs=0: nothing", _started, [])
	_gs.runs = 1
	_st.notify("camp_enter", {})
	_eq("runs=1: first_shift", _started, ["first_shift"])
	_st.notify("camp_enter", {})
	_eq("first_shift once", _started, ["first_shift"])


func _test_midrun_queue() -> void:
	_fresh()
	_st.notify("chain", {"n": 4})
	_eq("chain 4: no beat", _st.queue, [])
	_st.notify("chain", {"n": 5})
	_eq("chain 5: queued, not played", _st.queue, ["chain5"])
	_eq("chain 5: no dialog started", _started, [])
	_st.notify("chain", {"n": 6})
	_eq("chain 6: no duplicate in queue", _st.queue, ["chain5"])
	_st.notify("depth", {"col": 29})
	_eq("depth 29: nothing new", _st.queue, ["chain5"])
	_st.notify("depth", {"col": 30})
	_eq("depth 30 queued", _st.queue, ["chain5", "depth30"])
	_st.notify("tree_first_seen", {"tree": "kavak"})
	_eq("kavak: nothing", _st.queue, ["chain5", "depth30"])
	_st.notify("tree_first_seen", {"tree": "ladin"})
	_eq("ladin queued", _st.queue, ["chain5", "depth30", "ladin"])
	_st.notify("camp_enter", {})
	_eq("camp_enter drains queue in order (intro first: unseen in this state)", _started, ["chain5", "depth30", "ladin", "intro"])
	_eq("queue empty after", _st.queue, [])
	# a chain event for an already-seen beat never requeues
	_st.notify("chain", {"n": 9})
	_eq("seen chain5 not requeued", _st.queue, [])


func _test_kemal_chain() -> void:
	_fresh()
	_gs.set_flag("story_chain5", true)
	_gs.gold = 100.0
	_st.notify("chain", {"n": 15})
	_eq("chain 15 without kemal flag: no beat 7", _st.queue, [])
	_gs.runs = 4
	_st.notify("camp_enter", {})
	_ok("runs=4: kemal_challenge not started", not _started.has("kemal_challenge"))
	_gs.runs = 5
	_st.notify("camp_enter", {})
	_ok("runs=5: kemal_challenge started", _started.has("kemal_challenge"))
	_ok("challenge flag set by reward", _gs.get_flag("kemal_challenge"))
	_eq("no gold from challenge", _gs.gold, 100.0)
	_started.clear()
	_st.notify("chain", {"n": 14})
	_eq("chain 14 with flag: no beat", _st.queue, [])
	_st.notify("chain", {"n": 15})
	_eq("chain 15 with flag: beat 7 queued", _st.queue, ["kemal_defeat"])
	_eq("gold unchanged until beat finishes", _gs.gold, 100.0)
	_st.notify("camp_enter", {})
	_ok("kemal_defeat played", _started.has("kemal_defeat"))
	_eq("gold = 100 + 400 exactly", _gs.gold, 500.0)
	_ok("map_piece flag", _gs.get_flag("map_piece"))
	_ok("kemal_defeat seen", _gs.get_flag("story_kemal_defeat"))
	_st.notify("camp_enter", {})
	_st.notify("chain", {"n": 30})
	_eq("no second payout", _gs.gold, 500.0)


func _test_depth100() -> void:
	_fresh()
	_st.notify("depth", {"col": 100})
	_ok("depth100 needs map_piece", not _st.queue.has("depth100"))
	_gs.set_flag("map_piece", true)
	_st.notify("depth", {"col": 99})
	_ok("col 99 no", not _st.queue.has("depth100"))
	_st.notify("depth", {"col": 100})
	_ok("col 100 with map_piece queued", _st.queue.has("depth100"))


func _test_skip_marks_seen() -> void:
	_fresh()
	_gs.set_flag("kemal_challenge", true)
	_gs.gold = 0.0
	_st.notify("chain", {"n": 15})
	_ok("queued", _st.queue.has("kemal_defeat"))
	_st.queue.erase("chain5")
	_st.current = _st.get_beat("kemal_defeat")
	_st.queue.erase("kemal_defeat")
	_ok("is_playing while current set", _st.is_playing())
	_st.finish_current(true)   # what the Geç button does
	_ok("skipped beat seen", _gs.get_flag("story_kemal_defeat"))
	_eq("skipped beat still pays reward", _gs.gold, 400.0)
	_ok("skip emitted finished", _finished.has("kemal_defeat"))
	_ok("not playing after skip", not _st.is_playing())
	_st.finish_current(true)
	_eq("finish_current when idle is a no-op", _gs.gold, 400.0)


func _test_run_end_ctx() -> void:
	_fresh()
	_gs.set_flag("story_intro", true)
	_gs.set_flag("story_first_shift", true)
	_gs.set_flag("kemal_challenge", true)
	# run_end carries last_run; "chain" falls back to its longest_chain
	_st.load_data({"characters": {"hoca": {"name": "Hoca"}}, "beats": [
		{"id": "re", "trigger": {"event": "run_end", "conditions": [{"chain_gte": 7}, {"gold_gte": 50}]}, "lines": [{"who": "hoca", "text": "x"}]},
	]})
	_gs.gold = 10.0
	_st.notify("run_end", {"last_run": {"longest_chain": 7}})
	_eq("gold 10 < 50: no", _started, [])
	_gs.gold = 60.0
	_st.notify("run_end", {"last_run": {"longest_chain": 6}})
	_eq("chain 6 < 7: no", _started, [])
	_st.notify("run_end", {"last_run": {"longest_chain": 7}})
	_eq("run_end with last_run chain 7 and gold 60: plays", _started, ["re"])
	_st.load_story(_st.STORY_PATH)


func _test_reset() -> void:
	_fresh()
	_gs.set_flag("story_intro", true)
	_gs.set_flag("kemal_challenge", true)
	_gs.set_flag("map_piece", true)
	_st.queue.append("chain5")
	_st.reset_story()
	_ok("reset clears intro flag", not _gs.get_flag("story_intro"))
	_ok("reset clears reward flags", not _gs.get_flag("kemal_challenge") and not _gs.get_flag("map_piece"))
	_eq("reset clears queue", _st.queue, [])
	_st.notify("camp_enter", {})
	_eq("intro plays again after reset", _started, ["intro"])


func _test_malformed() -> void:
	_fresh()
	var good := {"id": "ok", "trigger": {"event": "camp_enter", "conditions": []}, "lines": [{"who": "hoca", "text": "Merhaba"}]}
	_st.load_data({"characters": {"hoca": {"name": "Hoca"}, "bad": 5}, "beats": [
		5,
		"text",
		{},
		{"id": "no_trigger", "lines": [{"who": "hoca", "text": "x"}]},
		{"id": "bad_event", "trigger": {"event": 7}, "lines": [{"who": "hoca", "text": "x"}]},
		{"id": "no_lines", "trigger": {"event": "camp_enter"}},
		{"id": "empty_lines", "trigger": {"event": "camp_enter"}, "lines": []},
		{"id": "junk_lines", "trigger": {"event": "camp_enter"}, "lines": [1, null, {"who": "hoca"}, {"text": ""}]},
		{"id": "bad_conds", "trigger": {"event": "camp_enter", "conditions": "x"}, "lines": [{"who": "hoca", "text": "x"}]},
		{"id": "unknown_cond", "trigger": {"event": "camp_enter", "conditions": [{"banana_gte": 1}, 5, {"runs_gte": "many"}]}, "lines": [{"who": "hoca", "text": "x"}]},
		{"id": "", "trigger": {"event": "camp_enter"}, "lines": [{"who": "hoca", "text": "x"}]},
		{"id": "bad_reward", "trigger": {"event": "chain", "conditions": []}, "reward": 12, "letter": "nope", "lines": [{"who": "ghost", "text": "kimse yok"}]},
		good,
		good.duplicate(true),
	]})
	var ids: Array = []
	for b in _st.beats:
		ids.append(b.id)
	_eq("only well-formed beats survive (unknown_cond is valid but never matches)", ids, ["unknown_cond", "bad_reward", "ok"])
	_eq("non-dict character dropped", _st.characters.keys(), ["hoca"])
	_st.notify("camp_enter", {"runs": 3})
	_eq("only the valid matching beat plays; junk conditions never match", _started, ["ok"])
	_st.notify("chain", {"n": 1})
	_eq("bad_reward beat plays without crash, bad reward/letter dropped", _st.queue, ["bad_reward"])
	_st.notify("camp_enter", {})
	_ok("bad_reward finished", _finished.has("bad_reward"))
	# top-level garbage
	_st.load_data({"beats": "nope", "characters": []})
	_eq("garbage top-level: no beats", _st.beats.size(), 0)
	_st.notify("camp_enter", {})
	_st.load_story("res://data/does_not_exist.json")
	_eq("missing file: no beats, no crash", _st.beats.size(), 0)
	_st.load_story(_st.STORY_PATH)
	_eq("real story reloaded", _st.beats.size(), 8)


func _test_real_save() -> void:
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


func _ok(label: String, cond: bool) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		print("  FAIL ", label)
