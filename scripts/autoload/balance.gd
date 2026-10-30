extends Node
## Read-only game data loaded from res://data/*.json.
## Pure helpers here take levels as arguments so they can be unit tested without GameState.

var trees: Dictionary = {}        # id -> tree def
var tree_order: Array = []
var spawn_rules: Array = []
var forest: Dictionary = {}
var base_stats: Dictionary = {}
var upgrades: Array = []          # list of upgrade defs
var save_version: int = 1
var chain_bonus_max: float = 1.0   # total chain bonus cap, as a fraction of sales


func _ready() -> void:
	reload()


func reload() -> void:
	var t := _load_json("res://data/trees.json")
	trees = t.get("trees", {})
	tree_order = t.get("order", [])
	spawn_rules = t.get("spawn", [])
	var b := _load_json("res://data/balance.json")
	forest = b.get("forest", {})
	base_stats = b.get("base_stats", {})
	save_version = int(b.get("save_version", 1))
	chain_bonus_max = float(b.get("chain_bonus_max", 1.0))
	upgrades = _load_json("res://data/upgrades.json").get("upgrades", [])


func get_upgrade(id: String) -> Dictionary:
	for u in upgrades:
		if u.id == id:
			return u
	return {}


## Cost of buying the next level when the upgrade is currently at `level`.
func upgrade_cost(id: String, level: int) -> float:
	var u := get_upgrade(id)
	if u.is_empty():
		return INF
	return round(float(u.base_cost) * pow(float(u.growth), level))


func is_maxed(id: String, level: int) -> bool:
	var u := get_upgrade(id)
	return u.is_empty() or level >= int(u.max_level)


## Final stat value for the given upgrade levels {upgrade_id: level}.
func compute_stat(stat: String, levels: Dictionary) -> float:
	var v := float(base_stats.get(stat, 0.0))
	for u in upgrades:
		if u.stat == stat and u.op == "add":
			var lv := int(clampf(float(levels.get(u.id, 0)), 0.0, float(u.max_level)))
			v += float(lv) * float(u.value)
	match stat:
		"swing_interval":
			v = max(v, float(base_stats.get("swing_interval_min", 0.1)))
		"crit_chance":
			v = clamp(v, 0.0, 1.0)
	return v


## Weighted tree pick for a forest column. Weights are piecewise-linear over column index.
func pick_tree(col: int, rng: RandomNumberGenerator) -> String:
	var total := 0.0
	var options: Array = []
	for r in spawn_rules:
		if col < int(r.from_col):
			continue
		var w := _weight_at(r.weights, col)
		if w > 0.0:
			options.append([r.tree, w])
			total += w
	if options.is_empty():
		return tree_order[0]
	var roll := rng.randf() * total
	for o in options:
		roll -= o[1]
		if roll <= 0.0:
			return o[0]
	return options[-1][0]


func _weight_at(points: Array, col: int) -> float:
	if points.is_empty():
		return 0.0
	if col <= points[0][0]:
		return float(points[0][1])
	for i in range(1, points.size()):
		if col <= points[i][0]:
			var a: Array = points[i - 1]
			var b: Array = points[i]
			var t := float(col - a[0]) / float(b[0] - a[0])
			return lerp(float(a[1]), float(b[1]), t)
	return float(points[-1][1])


## Run payout. `logs` = {tree_id: count}. Returns {sales, chain_bonus, total}.
func run_payout(logs: Dictionary, longest_chain: int) -> Dictionary:
	var sales := 0.0
	for id in logs:
		sales += float(logs[id]) * float(trees.get(id, {}).get("log_value", 0))
	var links: int = max(0, longest_chain - 1)
	var rate: float = minf(float(links) * float(base_stats.get("chain_bonus_per_link", 0.0)), chain_bonus_max)
	var bonus := sales * rate
	return {"sales": sales, "chain_bonus": round(bonus), "total": sales + round(bonus)}


func _load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Balance: cannot open %s" % path)
		return {}
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		push_error("Balance: bad json %s" % path)
		return {}
	return data
