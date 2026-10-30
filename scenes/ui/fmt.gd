extends RefCounted
## Locale-independent number formatting helpers (no thousands separators from the OS locale).

const SUFFIXES := ["", "K", "M", "B", "T"]


## 0 -> "0", 999 -> "999", 1234 -> "1.2K", 3.4e6 -> "3.4M".
static func num(value: float) -> String:
	var v := absf(value)
	var sign_str := "-" if value < 0.0 and round(v) > 0.0 else ""
	if v < 999.5:
		return sign_str + str(int(round(v)))
	var idx := 0
	while v >= 999.95 and idx < SUFFIXES.size() - 1:
		v /= 1000.0
		idx += 1
	return sign_str + _trim("%.1f" % v) + SUFFIXES[idx]


## Decimal with at most `digits` places and no trailing zeros ("0.5", "11").
static func dec(value: float, digits: int = 2) -> String:
	return _trim(("%." + str(digits) + "f") % value)


## 0.04 -> "%4", 0.125 -> "%12.5".
static func percent(fraction: float) -> String:
	return "%" + dec(fraction * 100.0, 1)


static func seconds(value: float) -> String:
	return dec(value, 2) + " sn"


static func _trim(s: String) -> String:
	if s.contains("."):
		s = s.rstrip("0").rstrip(".")
	return s
