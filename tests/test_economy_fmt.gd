extends SceneTree
## Number formatting helper: locale independent, expected strings written in advance.

func _initialize() -> void:
	var Fmt = load("res://scenes/ui/fmt.gd")
	var cases := [
		[Fmt.num(0), "0"], [Fmt.num(7), "7"], [Fmt.num(999), "999"],
		[Fmt.num(1000), "1K"], [Fmt.num(1234), "1.2K"], [Fmt.num(999999), "1M"],
		[Fmt.num(3.4e6), "3.4M"], [Fmt.num(2.5e9), "2.5B"], [Fmt.num(1.0e12), "1T"],
		[Fmt.num(12.4), "12"], [Fmt.num(-1500), "-1.5K"],
		[Fmt.dec(0.7), "0.7"], [Fmt.dec(20.0), "20"], [Fmt.percent(0.04), "%4"], [Fmt.percent(0.062), "%6.2"],
		[Fmt.seconds(0.66), "0.66 sn"],
	]
	var fails := 0
	for c in cases:
		if c[0] != c[1]:
			fails += 1
			print("  FAIL got=", c[0], " want=", c[1])
	print("TEST_ECONOMY_FMT ", "OK (%d checks)" % cases.size() if fails == 0 else "FAIL %d" % fails)
	quit(1 if fails > 0 else 0)
