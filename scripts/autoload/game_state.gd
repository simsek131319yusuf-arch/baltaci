extends Node
## Persistent player state + save/load. Single source of truth for gold and upgrade levels.

signal changed

const DEFAULT_SAVE_PATH := "user://save.json"   # fixed ASCII lowercase key; never derived via to_lower()
const MAX_COUNT := 2000000000

## Where the save lives. Tests and previews override it so they never touch the real save.
var save_path: String = DEFAULT_SAVE_PATH
## When false, save_game() does nothing (autoplay / screenshot runs).
var persist: bool = true

var gold: float = 0.0
var levels: Dictionary = {}       # upgrade_id -> int
var best_chain: int = 0
var runs: int = 0
var last_run: Dictionary = {}     # see CONTRACT.md "Run result"
var flags: Dictionary = {}        # story/progress flags: ASCII key -> bool/int/float/String
var max_depth: int = 0            # deepest forest column reached in any run


## Persisted flag helpers (story beats, one-time hints). Values must be JSON-safe primitives.
func get_flag(key: String, default = false):
	return flags.get(key, default)


func set_flag(key: String, value = true) -> void:
	if flags.get(key) == value:
		return
	flags[key] = value
	save_game()
	changed.emit()


func note_depth(col: int) -> void:
	if col > max_depth:
		max_depth = col


func _ready() -> void:
	load_game()


func stat(name: String) -> float:
	return Balance.compute_stat(name, levels)


func level_of(id: String) -> int:
	return int(levels.get(id, 0))


func next_cost(id: String) -> float:
	return Balance.upgrade_cost(id, level_of(id))


func can_buy(id: String) -> bool:
	return not Balance.is_maxed(id, level_of(id)) and gold >= next_cost(id)


func buy(id: String) -> bool:
	if not can_buy(id):
		return false
	gold -= next_cost(id)
	levels[id] = level_of(id) + 1
	save_game()
	changed.emit()
	return true


## Called by the forest scene when a run ends. Computes payout from the same data the
## results screen shows, so displayed and credited gold can never diverge.
func apply_run_result(logs: Dictionary, longest_chain: int, trees_felled: int, duration: float) -> Dictionary:
	var payout := Balance.run_payout(logs, longest_chain)
	gold += payout.total
	best_chain = max(best_chain, longest_chain)
	runs += 1
	last_run = {
		"logs": logs.duplicate(),
		"longest_chain": longest_chain,
		"trees_felled": trees_felled,
		"duration": duration,
		"sales": payout.sales,
		"chain_bonus": payout.chain_bonus,
		"total": payout.total,
		"gold_after": gold,
	}
	save_game()
	changed.emit()
	return last_run


func to_dict() -> Dictionary:
	return {"save_version": Balance.save_version, "gold": gold, "levels": levels,
		"best_chain": best_chain, "runs": runs, "flags": flags, "max_depth": max_depth}


## Loads a state dict defensively: wrong types or out-of-range numbers fall back to safe values.
func from_dict(d: Dictionary) -> void:
	d = _migrate(d)
	gold = 0.0
	var g = d.get("gold", 0.0)
	if _is_number(g) and is_finite(float(g)):
		gold = maxf(0.0, float(g))
	levels = {}
	var lv = d.get("levels", {})
	if typeof(lv) == TYPE_DICTIONARY:
		for k in lv:
			var u := Balance.get_upgrade(str(k))
			if u.is_empty() or not _is_number(lv[k]) or not is_finite(float(lv[k])):
				continue
			levels[str(k)] = int(clampf(float(lv[k]), 0.0, float(u.max_level)))
	best_chain = _count(d.get("best_chain", 0))
	runs = _count(d.get("runs", 0))
	max_depth = _count(d.get("max_depth", 0))
	flags = {}
	var fl = d.get("flags", {})
	if typeof(fl) == TYPE_DICTIONARY:
		for k in fl:
			var t := typeof(fl[k])
			if t == TYPE_BOOL or t == TYPE_STRING or (_is_number(fl[k]) and is_finite(float(fl[k]))):
				flags[str(k)] = fl[k]


static func _is_number(v) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT


static func _count(v) -> int:
	if not _is_number(v) or not is_finite(float(v)):
		return 0
	return int(clampf(float(v), 0.0, float(MAX_COUNT)))


## Atomic-ish save: write + verify a temp file, keep the previous save as .bak, then replace.
func save_game() -> void:
	if not persist:
		return
	var tmp := save_path + ".tmp"
	var bak := save_path + ".bak"
	var text := JSON.stringify(to_dict(), "\t")
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("save failed: %s" % FileAccess.get_open_error())
		return
	f.store_string(text)
	f.close()
	if FileAccess.get_file_as_string(tmp) != text:
		push_error("save failed: temp file verification mismatch")
		return
	if FileAccess.file_exists(save_path):
		DirAccess.copy_absolute(_abs(save_path), _abs(bak))
	var err := DirAccess.rename_absolute(_abs(tmp), _abs(save_path))
	if err != OK:
		# Rename over an existing file can fail (locked / platform quirk): copy, then verify.
		err = DirAccess.copy_absolute(_abs(tmp), _abs(save_path))
		if err != OK or FileAccess.get_file_as_string(save_path) != text:
			push_error("save failed: could not replace %s (err %d)" % [save_path, err])
			return
		DirAccess.remove_absolute(_abs(tmp))


## Loads save_path; a corrupt file is moved to *.corrupt.json and the newest valid of
## .tmp / .bak is used instead.
func load_game() -> void:
	var data = _read_dict(save_path)
	if data == null and FileAccess.file_exists(save_path):
		var corrupt := save_path.get_basename() + ".corrupt." + save_path.get_extension()
		DirAccess.remove_absolute(_abs(corrupt))
		var err := DirAccess.rename_absolute(_abs(save_path), _abs(corrupt))
		push_warning("save file unreadable, moved to %s (err %d)" % [corrupt, err])
	if data == null:
		data = _read_dict(save_path + ".tmp")
	if data == null:
		data = _read_dict(save_path + ".bak")
	if data != null:
		from_dict(data)
	changed.emit()


## Parsed JSON dict from `path`, or null when missing / not a JSON object.
func _read_dict(path: String):
	if not FileAccess.file_exists(path):
		return null
	var parser := JSON.new()   # unlike JSON.parse_string, a parse error is not logged as an engine error
	if parser.parse(FileAccess.get_file_as_string(path)) != OK:
		return null
	return parser.data if typeof(parser.data) == TYPE_DICTIONARY else null


func _abs(p: String) -> String:
	return ProjectSettings.globalize_path(p)


func reset() -> void:
	from_dict({})
	save_game()
	changed.emit()


## Upgrade old save dicts step by step. Add a branch per version bump.
func _migrate(d: Dictionary) -> Dictionary:
	var v := int(d.get("save_version", 1))
	# if v < 2: ... ; v = 2
	d["save_version"] = v
	return d
