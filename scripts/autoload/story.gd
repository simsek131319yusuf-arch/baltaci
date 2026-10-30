extends Node
## Light story system. Beats live in data/story.json; seen-state lives in GameState.flags
## ("story_<id>"). Gameplay code only calls Story.notify(event, ctx).
##
## Blocking dialogs open only on BLOCKING_EVENTS (camp_enter, run_end). Mid-run events
## (chain / depth / tree_first_seen) show a small auto-dismissing toast and queue the full
## beat for the next blocking event.

signal beat_started(id: String)
signal beat_finished(id: String)

const STORY_PATH := "res://data/story.json"
const BLOCKING_EVENTS: Array[String] = ["camp_enter", "run_end"]
const BOX_SCENE := "res://scenes/story/dialogue_box.tscn"
const TOAST_SCENE := "res://scenes/story/toast.tscn"
const GAP_BETWEEN_BEATS := 0.3

var characters: Dictionary = {}     # id -> {name, portrait, color, ...}
var beats: Array = []               # validated beat dictionaries, file order
var queue: Array = []               # beat ids waiting to play
## false = no UI at all (tests, headless): beats finish instantly when played.
var ui_enabled: bool = true
var current: Dictionary = {}        # beat being played ({} = idle)

var _box: Node = null
var _toast: Node = null
var _toasted: Dictionary = {}       # beat id -> true (one toast per beat per session)


func _ready() -> void:
	load_story(STORY_PATH)


func is_playing() -> bool:
	return not current.is_empty()


func has_seen(id: String) -> bool:
	return bool(GameState.get_flag("story_" + id, false))


func get_beat(id: String) -> Dictionary:
	for b in beats:
		if b.id == id:
			return b
	return {}


## Wipes all story progress (seen flags, reward flags, queue). Paid gold is not refunded.
func reset_story() -> void:
	queue.clear()
	_toasted.clear()
	for b in beats:
		GameState.flags.erase("story_" + b.id)
		var r = b.get("reward", {})
		if typeof(r) == TYPE_DICTIONARY and r.has("flag"):
			GameState.flags.erase(str(r.flag))
	GameState.save_game()
	GameState.changed.emit()


# ------------------------------------------------------------------ loading

func load_story(path: String) -> void:
	characters = {}
	beats = []
	var text := FileAccess.get_file_as_string(path)
	var parser := JSON.new()
	if text.is_empty() or parser.parse(text) != OK or typeof(parser.data) != TYPE_DICTIONARY:
		push_warning("story: cannot read %s" % path)
		return
	load_data(parser.data)


## Validates a parsed story dictionary; malformed characters/beats are skipped with a warning.
func load_data(d: Dictionary) -> void:
	characters = {}
	beats = []
	var chars = d.get("characters", {})
	if typeof(chars) == TYPE_DICTIONARY:
		for k in chars:
			if typeof(chars[k]) == TYPE_DICTIONARY:
				characters[str(k)] = chars[k]
	var raw = d.get("beats", [])
	if typeof(raw) != TYPE_ARRAY:
		return
	var seen_ids := {}
	for entry in raw:
		var b := _validate_beat(entry)
		if b.is_empty():
			push_warning("story: malformed beat ignored")
			continue
		if seen_ids.has(b.id):
			push_warning("story: duplicate beat id '%s' ignored" % b.id)
			continue
		seen_ids[b.id] = true
		beats.append(b)


func _validate_beat(entry) -> Dictionary:
	if typeof(entry) != TYPE_DICTIONARY:
		return {}
	var id = entry.get("id")
	if typeof(id) != TYPE_STRING or id.is_empty():
		return {}
	var trig = entry.get("trigger")
	if typeof(trig) != TYPE_DICTIONARY or typeof(trig.get("event")) != TYPE_STRING:
		return {}
	var conds = trig.get("conditions", [])
	if typeof(conds) != TYPE_ARRAY:
		return {}
	var lines_in = entry.get("lines")
	if typeof(lines_in) != TYPE_ARRAY:
		return {}
	var lines: Array = []
	for l in lines_in:
		if typeof(l) == TYPE_DICTIONARY and typeof(l.get("text")) == TYPE_STRING and not str(l.text).is_empty():
			lines.append(l)
	if lines.is_empty():
		return {}
	var out: Dictionary = entry.duplicate(true)
	out["lines"] = lines
	out["trigger"] = {"event": trig.event, "conditions": conds}
	var rw = entry.get("reward")
	if rw != null and typeof(rw) != TYPE_DICTIONARY:
		out.erase("reward")
	var lt = entry.get("letter")
	if lt != null and (typeof(lt) != TYPE_DICTIONARY or typeof(lt.get("text")) != TYPE_STRING):
		out.erase("letter")
	return out


# ------------------------------------------------------------------ triggers

## Gameplay entry point. Evaluates unseen beats for `event`; matches are queued. Blocking
## events start playback right away, mid-run events only toast.
func notify(event: String, ctx: Dictionary = {}) -> void:
	var blocking := BLOCKING_EVENTS.has(event)
	for b in beats:
		if has_seen(b.id) or queue.has(b.id) or current.get("id", "") == b.id:
			continue
		if b.trigger.event != event:
			continue
		if not _conditions_met(b.trigger.conditions, ctx):
			continue
		queue.append(b.id)
		if not blocking:
			_show_toast(b)
	if blocking:
		play_next()


func _conditions_met(conds: Array, ctx: Dictionary) -> bool:
	for c in conds:
		if typeof(c) != TYPE_DICTIONARY:
			return false
		for key in c:
			if not _check(str(key), c[key], ctx):
				return false
	return true


func _check(key: String, want, ctx: Dictionary) -> bool:
	match key:
		"flag":
			return bool(GameState.get_flag(str(want), false))
		"flag_not":
			return not bool(GameState.get_flag(str(want), false))
		"tree":
			return str(ctx.get("tree", "")) == str(want)
	if typeof(want) != TYPE_INT and typeof(want) != TYPE_FLOAT:
		return false
	var w := float(want)
	if key.ends_with("_gte"):
		return _value(key.trim_suffix("_gte"), ctx) >= w
	if key.ends_with("_lte"):
		return _value(key.trim_suffix("_lte"), ctx) <= w
	if key.ends_with("_eq"):
		return _value(key.trim_suffix("_eq"), ctx) == w
	return false   # unknown condition never matches


## Numeric lookup: event context first, then GameState. Missing -> -INF so *_gte fails.
func _value(name: String, ctx: Dictionary) -> float:
	var aliases := {"chain": ["n", "chain", "longest_chain"], "col": ["col", "depth"], "depth": ["depth", "col"]}
	var keys: Array = aliases.get(name, [name])
	for k in keys:
		var v = ctx.get(k)
		if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
			return float(v)
	var lr = ctx.get("last_run")
	if name == "chain" and typeof(lr) == TYPE_DICTIONARY and lr.has("longest_chain"):
		return float(lr.longest_chain)
	match name:
		"runs": return float(GameState.runs)
		"gold": return float(GameState.gold)
		"best_chain": return float(GameState.best_chain)
		"max_depth": return float(GameState.max_depth)
	return -INF


# ------------------------------------------------------------------ playback

func play_next() -> void:
	if is_playing():
		return
	while not queue.is_empty():
		var id: String = queue.pop_front()
		var b := get_beat(id)
		if b.is_empty() or has_seen(id):
			continue
		current = b
		beat_started.emit(id)
		if not ui_enabled:
			finish_current(false)
			return
		_ensure_box()
		_box.play(b, characters)
		return


## Ends the current beat: pays the reward, marks it seen, then continues with the queue.
## Called by the dialogue box (skipped = true for "Geç"), or directly in UI-less mode.
func finish_current(_skipped: bool = false) -> void:
	if current.is_empty():
		return
	var b := current
	current = {}
	var r = b.get("reward", {})
	if typeof(r) == TYPE_DICTIONARY:
		var g = r.get("gold")
		if typeof(g) == TYPE_INT or typeof(g) == TYPE_FLOAT:
			GameState.gold += maxf(0.0, float(g))
		var f = r.get("flag")
		if typeof(f) == TYPE_STRING and not f.is_empty():
			GameState.flags[f] = true
	GameState.set_flag("story_" + b.id, true)   # saves + emits changed
	beat_finished.emit(b.id)
	if not queue.is_empty():
		if ui_enabled and is_inside_tree():
			get_tree().create_timer(GAP_BETWEEN_BEATS).timeout.connect(play_next)
		else:
			play_next()


func _ensure_box() -> void:
	if is_instance_valid(_box):
		return
	_box = load(BOX_SCENE).instantiate()
	add_child(_box)
	_box.finished.connect(func(skipped: bool): finish_current(skipped))


func _show_toast(b: Dictionary) -> void:
	if not ui_enabled or _toasted.has(b.id) or not is_inside_tree():
		return
	_toasted[b.id] = true
	var t = b.get("toast")
	if typeof(t) != TYPE_DICTIONARY:
		t = b.lines[0]
	if not is_instance_valid(_toast):
		_toast = load(TOAST_SCENE).instantiate()
		add_child(_toast)
	var who := str(t.get("who", ""))
	_toast.show_line(characters.get(who, {}), who, str(t.get("text", "")), str(t.get("emote", "")))
