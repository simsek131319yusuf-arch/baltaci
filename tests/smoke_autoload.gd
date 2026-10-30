extends SceneTree
## Orchestrator smoke test for autoload contract. Expected values are written in advance.

func _initialize() -> void:
	await process_frame
	var B = root.get_node("Balance")
	var fails := 0
	fails += _eq("tree_order", B.tree_order, ["kavak", "cam", "ladin"])
	fails += _eq("axe_damage lv2", B.compute_stat("axe_damage", {"axe_damage": 2}), 11.0)
	fails += _eq("cost axe lv3", B.upgrade_cost("axe_damage", 3), 25.0)   # 10*1.36^3=25.16
	fails += _eq("swing at max level", B.compute_stat("swing_interval", {"swing_interval": 99}), 0.22)   # clamped to lv12
	var p = B.run_payout({"kavak": 10, "cam": 2}, 3)                     # sales 20+18=38, bonus 38*2*0.05=3.8->4
	fails += _eq("payout", [p.sales, p.chain_bonus, p.total], [38.0, 4.0, 42.0])
	var cap = B.run_payout({"kavak": 10}, 500)                           # +100% cap: 20 -> 40
	fails += _eq("payout cap", [cap.sales, cap.chain_bonus, cap.total], [20.0, 20.0, 40.0])
	print("SMOKE ", "OK" if fails == 0 else "FAIL %d" % fails)
	quit(fails)


func _eq(label: String, got, want) -> int:
	if str(got) == str(want):
		return 0
	print("  FAIL ", label, " got=", got, " want=", want)
	return 1
