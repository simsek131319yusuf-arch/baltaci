extends RefCounted
## Shared animation helpers: tuning values (data/balance.json "juice"), easing curves,
## frame-rate independent smoothing and a hover/press feedback wrapper for buttons.

static var _cfg: Dictionary = {}
static var _loaded := false


static func cfg(key: String, fallback: float) -> float:
	if not _loaded:
		_loaded = true
		var f := FileAccess.open("res://data/balance.json", FileAccess.READ)
		if f != null:
			var d = JSON.parse_string(f.get_as_text())
			if typeof(d) == TYPE_DICTIONARY and typeof(d.get("juice")) == TYPE_DICTIONARY:
				_cfg = d["juice"]
	return float(_cfg.get(key, fallback))


## Exponential approach: frame-rate independent replacement for lerp(a, b, k).
static func damp(current: float, target: float, rate: float, dt: float) -> float:
	return lerpf(current, target, 1.0 - exp(-rate * dt))


static func damp_v(current: Vector2, target: Vector2, rate: float, dt: float) -> Vector2:
	return current.lerp(target, 1.0 - exp(-rate * dt))


static func out_back(t: float, s: float = 1.70158) -> float:
	var u := t - 1.0
	return 1.0 + (s + 1.0) * u * u * u + s * u * u


static func in_cubic(t: float) -> float:
	return t * t * t


static func out_cubic(t: float) -> float:
	var u := 1.0 - t
	return 1.0 - u * u * u


static func in_out_sine(t: float) -> float:
	return 0.5 - 0.5 * cos(PI * t)


## Hover grows, press squashes, release springs back. Safe to call once per button.
static func button(btn: Control, hover_scale: float = 1.05, press_scale: float = 0.94) -> void:
	var fix_pivot := func() -> void: btn.pivot_offset = btn.size * 0.5
	btn.resized.connect(fix_pivot)
	fix_pivot.call()
	var state := {"tw": null, "hover": false}
	var go := func(sc: Vector2, dur: float, back: bool) -> void:
		if state.tw != null and (state.tw as Tween).is_valid():
			(state.tw as Tween).kill()
		var tw := btn.create_tween()
		state.tw = tw
		tw.tween_property(btn, "scale", sc, dur).set_trans(Tween.TRANS_BACK if back else Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	btn.mouse_entered.connect(func() -> void:
		state.hover = true
		if not (btn is BaseButton and (btn as BaseButton).disabled):
			go.call(Vector2.ONE * hover_scale, 0.14, true))
	btn.mouse_exited.connect(func() -> void:
		state.hover = false
		go.call(Vector2.ONE, 0.16, false))
	if btn is BaseButton:
		var bb := btn as BaseButton
		bb.button_down.connect(func() -> void: go.call(Vector2(press_scale * 1.03, press_scale * 0.94), 0.06, false))
		bb.button_up.connect(func() -> void: go.call(Vector2.ONE * (hover_scale if state.hover else 1.0), 0.22, true))


## Scale-pop for labels/cards. Pivot is centred.
static func pop(ctrl: Control, from_scale: float = 1.3, dur: float = 0.28) -> void:
	ctrl.pivot_offset = ctrl.size * 0.5
	ctrl.scale = Vector2.ONE * from_scale
	ctrl.create_tween().tween_property(ctrl, "scale", Vector2.ONE, dur).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## 9-slice wooden panel from art ("ui/panel"); null when the art is missing.
static func panel_box(tint: Color = Color(0.55, 0.42, 0.36), margin: int = 22, content: int = 14) -> StyleBox:
	var tex := Art.tex("ui/panel")
	if tex == null:
		return null
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.texture_margin_left = margin
	sb.texture_margin_right = margin
	sb.texture_margin_top = margin
	sb.texture_margin_bottom = margin
	sb.content_margin_left = content + 8
	sb.content_margin_right = content + 8
	sb.content_margin_top = content + 4
	sb.content_margin_bottom = content + 4
	sb.modulate_color = tint
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	return sb
