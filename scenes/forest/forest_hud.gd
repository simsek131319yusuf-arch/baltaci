extends CanvasLayer
## Run HUD (time, gold, chain, Paydos) and the results panel. All built in code.
## Gold counts up with an exponential approach and punches on gain; the timer pulses each
## second of the last five; the chain counter and "Zincir xN!" popup pop with scale + tilt.

signal paydos_pressed
signal camp_pressed
signal results_revealed   # the results panel finished its count-up (story beats may open now)

## Pipsy's result reaction is relative to the player's own history (GameState flags, JSON-safe floats).
const FLAG_AVG := "avg_total"      # exponential moving average of run totals
const FLAG_BEST := "best_total"


## "happy" / "cry" / "" for a run total judged against earlier runs. No history = first run = "happy".
## good: total >= 1.15 x average OR >= 0.8 x best;  poor: total < 0.6 x average.
static func reaction_kind(total: float, avg: float, best: float, has_history: bool) -> String:
	if not has_history:
		return "happy"
	if total >= avg * Juice.cfg("good_vs_avg", 1.15) or total >= best * Juice.cfg("good_vs_best", 0.8):
		return "happy"
	if total < avg * Juice.cfg("poor_vs_avg", 0.6):
		return "cry"
	return ""


static func reaction_for_total(total: float) -> String:
	var has := GameState.flags.has(FLAG_AVG)
	return reaction_kind(total, float(GameState.get_flag(FLAG_AVG, 0.0)), float(GameState.get_flag(FLAG_BEST, 0.0)), has)


## Folds a finished run into the history flags (saved with the game).
static func record_total(total: float) -> void:
	var has := GameState.flags.has(FLAG_AVG)
	var avg := float(GameState.get_flag(FLAG_AVG, 0.0))
	var best := float(GameState.get_flag(FLAG_BEST, 0.0))
	GameState.set_flag(FLAG_AVG, total if not has else avg + Juice.cfg("avg_alpha", 0.35) * (total - avg))
	GameState.set_flag(FLAG_BEST, maxf(best, total))

const Fmt := preload("res://scenes/ui/fmt.gd")
const Juice := preload("res://scenes/ui/juice.gd")

const INK := Color("#2b1a0e")
const WOOD := Color("#a8693a")
const WOOD_DARK := Color("#6e4223")
const CREAM := Color("#f8ecd2")
const GOLD := Color("#ffd35a")
const DANGER := Color("#ff4a3a")
const PANEL_TINT := Color(0.5, 0.37, 0.31)

@export var gold_count_rate: float = 9.0   # exponential approach speed (1/s)

var _time_label: Label
var _gold_label: Label
var _chain_label: Label
var _paydos: Button
var _popup: Label
var _banner: Label
var _popup_tw: Tween
var _results_root: Control
var _last_sec: int = -1
var _gold_target: float = 0.0
var _gold_shown: float = 0.0
var _gold_text_val: int = -1
var _gold_punch: float = 0.0
var _time_punch: float = 0.0
var _chain_value: int = 0
var _chain_punch: float = 0.0
var _gold_primed := false


func _ready() -> void:
	layer = 10
	gold_count_rate = Juice.cfg("gold_count_rate", gold_count_rate)
	_build()


func _process(delta: float) -> void:
	# Gold: exponential approach (frame-rate independent); snaps the last unit so it ends exact.
	if not is_equal_approx(_gold_shown, _gold_target):
		_gold_shown = Juice.damp(_gold_shown, _gold_target, gold_count_rate, delta)
		if absf(_gold_shown - _gold_target) < 0.5:
			_gold_shown = _gold_target
	var shown := int(round(_gold_shown))
	if shown != _gold_text_val:
		_gold_text_val = shown
		_gold_label.text = Fmt.num(float(shown))
		_gold_label.pivot_offset = Vector2(0.0, _gold_label.size.y * 0.5)
	_gold_punch = Juice.damp(_gold_punch, 0.0, 9.0, delta)
	var gs := 1.0 + 0.28 * _gold_punch
	_gold_label.scale = Vector2(gs, gs)
	_time_punch = Juice.damp(_time_punch, 0.0, 8.0, delta)
	var ts := 1.0 + 0.38 * _time_punch
	_time_label.scale = Vector2(ts, ts)
	_chain_punch = Juice.damp(_chain_punch, 0.0, 9.0, delta)
	var cs := 1.0 + 0.3 * _chain_punch
	_chain_label.scale = Vector2(cs, cs)


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Time (top centre)
	var time_panel := _pill(root, Control.PRESET_CENTER_TOP, Vector2(-100, 10), Vector2(200, 104))
	var tbox := HBoxContainer.new()
	tbox.alignment = BoxContainer.ALIGNMENT_CENTER
	tbox.add_theme_constant_override("separation", 8)
	time_panel.add_child(tbox)
	var clock := Art.tex("ui/clock")
	if clock:
		tbox.add_child(_icon(clock, 44))
	_time_label = _label("0", 68, CREAM)
	tbox.add_child(_time_label)
	_time_label.resized.connect(func() -> void: _time_label.pivot_offset = _time_label.size * 0.5)

	# Gold + chain (top left)
	var left := VBoxContainer.new()
	left.position = Vector2(14, 10)
	left.add_theme_constant_override("separation", 0)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(left)
	var gold_panel := _pill(left, -1, Vector2.ZERO, Vector2(260, 78))
	var gbox := HBoxContainer.new()
	gbox.add_theme_constant_override("separation", 10)
	gold_panel.add_child(gbox)
	var coin := Art.tex("ui/coin")
	if coin:
		gbox.add_child(_icon(coin, 38))
	else:
		gbox.add_child(_coin_dot())
	_gold_label = _label("0", 36, GOLD)
	gbox.add_child(_gold_label)
	var chain_panel := _pill(left, -1, Vector2.ZERO, Vector2(260, 64))
	var cbox := HBoxContainer.new()
	cbox.add_theme_constant_override("separation", 8)
	chain_panel.add_child(cbox)
	var chain_ic := Art.tex("ui/chain")
	if chain_ic:
		cbox.add_child(_icon(chain_ic, 28))
	_chain_label = _label("Zincir: 0", 25, CREAM)
	cbox.add_child(_chain_label)
	_chain_label.resized.connect(func() -> void: _chain_label.pivot_offset = _chain_label.size * 0.5)

	# Paydos button (top right)
	_paydos = Button.new()
	_paydos.text = "Paydos"
	_paydos.focus_mode = Control.FOCUS_NONE
	_paydos.position = Vector2(1600 - 190, 18)
	_paydos.size = Vector2(170, 56)
	_style_button(_paydos, WOOD, 26)
	_paydos.pressed.connect(func(): paydos_pressed.emit())
	root.add_child(_paydos)
	Juice.button(_paydos, 1.07, 0.93)

	# Chain popup + banner (centre)
	_popup = _label("", 76, GOLD)
	_popup.size = Vector2(700, 100)
	_popup.position = Vector2(450, 230)
	_popup.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_popup.pivot_offset = Vector2(350, 50)
	_popup.modulate.a = 0.0
	root.add_child(_popup)
	_banner = _label("", 96, CREAM)
	_banner.size = Vector2(700, 120)
	_banner.position = Vector2(450, 300)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.pivot_offset = Vector2(350, 60)
	_banner.modulate.a = 0.0
	root.add_child(_banner)


func set_values(time_left: float, gold: float, chain: int) -> void:
	var sec := int(ceil(time_left))
	_time_label.text = str(sec)
	var urgent := time_left <= 5.0 and time_left > 0.0
	_time_label.add_theme_color_override("font_color", DANGER if urgent else CREAM)
	if urgent and sec != _last_sec:
		_time_punch = 1.0
	_last_sec = sec
	if not _gold_primed:
		_gold_primed = true
		_gold_shown = gold
	if gold > _gold_target + 0.01:
		_gold_punch = 1.0
	_gold_target = gold
	if chain != _chain_value:
		if chain > _chain_value:
			_chain_punch = 1.0
		_chain_value = chain
		_chain_label.text = "Zincir: %d" % chain


func set_paydos_enabled(on: bool) -> void:
	_paydos.disabled = not on


## "Zincir xN!": scale-pop with a tilt that settles; colour runs gold -> orange -> hot pink as N grows.
func show_chain_popup(n: int) -> void:
	var k := clampf(float(n - 2) / 10.0, 0.0, 1.0)
	var col := GOLD.lerp(Color("#ff8a2a"), minf(k * 2.0, 1.0))
	col = col.lerp(Color("#ff4d7a"), maxf(k * 2.0 - 1.0, 0.0))
	_popup.add_theme_color_override("font_color", col)
	_popup.text = "Zincir x%d!" % n
	_popup.modulate = Color(1, 1, 1, 1)
	if _popup_tw:
		_popup_tw.kill()
	var big := 1.0 + 0.04 * minf(float(n), 12.0)
	var tilt := (0.1 + 0.012 * minf(float(n), 12.0)) * (1.0 if n % 2 == 0 else -1.0)
	_popup.scale = Vector2(0.45, 0.45)
	_popup.rotation = tilt * 2.2
	_popup_tw = create_tween()
	_popup_tw.set_parallel(true)
	_popup_tw.tween_property(_popup, "scale", Vector2(big, big), 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_popup_tw.tween_property(_popup, "rotation", tilt * 0.3, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_popup_tw.chain().tween_property(_popup, "scale", Vector2.ONE * big * 0.96, 0.4).set_trans(Tween.TRANS_SINE)
	_popup_tw.parallel().tween_property(_popup, "rotation", 0.0, 0.4).set_trans(Tween.TRANS_SINE)
	_popup_tw.chain().tween_property(_popup, "modulate:a", 0.0, 0.4)
	_popup_tw.parallel().tween_property(_popup, "position:y", 205.0, 0.4).from(230.0)


func show_banner(text: String) -> void:
	_banner.text = text
	_banner.modulate.a = 1.0
	_banner.scale = Vector2(0.6, 0.6)
	var tw := create_tween()
	tw.tween_property(_banner, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.6)
	tw.tween_property(_banner, "modulate:a", 0.0, 0.3)


## Results panel; every number comes from GameState.last_run.
func show_results(run: Dictionary, reaction: String = "") -> void:
	_paydos.visible = false
	_results_root = Control.new()
	_results_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_results_root)
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.03, 0.02, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.modulate.a = 0.0
	_results_root.add_child(dim)
	dim.create_tween().tween_property(dim, "modulate:a", 1.0, 0.35)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_results_root.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(660, 0)
	var sb: StyleBox = Juice.panel_box(PANEL_TINT, 22, 22)
	if sb == null:
		var flat := StyleBoxFlat.new()
		flat.bg_color = Color("#2d1d12")
		flat.border_color = WOOD
		flat.set_border_width_all(5)
		flat.set_corner_radius_all(22)
		flat.set_content_margin_all(30)
		flat.shadow_color = Color(0, 0, 0, 0.5)
		flat.shadow_size = 18
		sb = flat
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)

	var cells: Array = []     # [Control, row_index] revealed one row after another
	var title := _label("Vardiya Bitti", 48, GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	cells.append([title, 0])
	var sub := _label("%d ağaç devrildi  ·  en uzun zincir x%d" % [int(run.get("trees_felled", 0)), int(run.get("longest_chain", 0))], 22, CREAM.darkened(0.1))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sub)
	cells.append([sub, 1])
	vb.add_child(HSeparator.new())

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 36)
	grid.add_theme_constant_override("v_separation", 8)
	vb.add_child(grid)
	var logs: Dictionary = run.get("logs", {})
	var any := false
	var row := 2
	for id in Balance.tree_order:
		var cnt := int(logs.get(id, 0))
		if cnt <= 0:
			continue
		any = true
		var def: Dictionary = Balance.trees.get(id, {})
		var c1 := _row_label(str(def.get("name", id)), CREAM, HORIZONTAL_ALIGNMENT_LEFT)
		var c2 := _row_label("%d tomruk" % cnt, CREAM.darkened(0.1), HORIZONTAL_ALIGNMENT_RIGHT)
		var c3 := _row_label("%s altın" % Fmt.num(cnt * float(def.get("log_value", 0))), GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
		for c in [c1, c2, c3]:
			grid.add_child(c)
			cells.append([c, row])
		row += 1
	if not any:
		var none := _row_label("Hiç tomruk yok", CREAM.darkened(0.2), HORIZONTAL_ALIGNMENT_LEFT)
		grid.add_child(none)
		cells.append([none, row])
		grid.add_child(Control.new())
		grid.add_child(Control.new())
		row += 1
	var b1 := _row_label("Zincir bonusu", Color("#a8ecaa"), HORIZONTAL_ALIGNMENT_LEFT)
	var b2 := _row_label("x%d" % int(run.get("longest_chain", 0)), Color("#a8ecaa"), HORIZONTAL_ALIGNMENT_RIGHT)
	var b3 := _row_label("+%s altın" % Fmt.num(float(run.get("chain_bonus", 0))), Color("#a8ecaa"), HORIZONTAL_ALIGNMENT_RIGHT)
	for c in [b1, b2, b3]:
		grid.add_child(c)
		cells.append([c, row])
	row += 1
	vb.add_child(HSeparator.new())

	var total_val := float(run.get("total", 0))
	var total := _label("Toplam: +0 altın", 40, GOLD)
	total.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(total)
	cells.append([total, row])
	var bal_val := float(run.get("gold_after", 0))
	var bal := _label("Yeni bakiye: %s altın" % Fmt.num(bal_val - total_val), 26, CREAM)
	bal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(bal)
	cells.append([bal, row + 1])

	var btn := Button.new()
	btn.text = "Kampa Dön"
	btn.custom_minimum_size = Vector2(0, 62)
	btn.focus_mode = Control.FOCUS_NONE
	_style_button(btn, Color("#4e8f3a"), 30)
	btn.pressed.connect(func(): camp_pressed.emit())
	vb.add_child(btn)
	Juice.button(btn, 1.04, 0.95)
	cells.append([btn, row + 2])

	_results_root.modulate.a = 1.0
	for c in cells:
		(c[0] as Control).modulate.a = 0.0
	panel.modulate.a = 0.0
	_animate_results(panel, cells, total, bal, total_val, bal_val, run, row, reaction)


func _animate_results(panel: PanelContainer, cells: Array, total: Label, bal: Label, total_val: float, bal_val: float, run: Dictionary, last_row: int, kind: String = "") -> void:
	await get_tree().process_frame   # let containers lay out so sizes/pivots are real
	panel.pivot_offset = panel.size * 0.5
	panel.scale = Vector2(0.8, 0.8)
	panel.rotation = -0.03
	var pw := create_tween().set_parallel(true)
	pw.tween_property(panel, "modulate:a", 1.0, 0.18)
	pw.tween_property(panel, "scale", Vector2.ONE, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pw.tween_property(panel, "rotation", 0.0, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Rows appear one after another.
	for c in cells:
		_reveal(c[0], 0.38 + 0.1 * float(c[1]))
	# Total counts up once its row is in.
	var t0 := 0.38 + 0.1 * float(last_row) + 0.1
	var ctw := create_tween()
	ctw.tween_interval(t0)
	ctw.tween_method(func(v: float) -> void: total.text = "Toplam: +%s altın" % Fmt.num(v), 0.0, total_val, 0.85).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	ctw.tween_callback(func() -> void: Juice.pop(total, 1.18, 0.3))
	ctw.tween_interval(0.55)   # let the pop settle before anything opens over the panel
	ctw.tween_callback(func() -> void: results_revealed.emit())
	var btw := create_tween()
	btw.tween_interval(t0)
	btw.tween_method(func(v: float) -> void: bal.text = "Yeni bakiye: %s altın" % Fmt.num(v), bal_val - total_val, bal_val, 0.85).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	# Pipsy reacts on the panel corner.
	var tex := Art.tex("ui/pipsy_" + kind) if kind != "" else null
	if tex != null:
		var em := TextureRect.new()
		em.texture = tex
		em.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		em.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		em.custom_minimum_size = Vector2(130, 130)
		em.size = Vector2(130, 130)
		em.mouse_filter = Control.MOUSE_FILTER_IGNORE
		em.position = panel.global_position + Vector2(panel.size.x - 110.0, -78.0)
		em.pivot_offset = Vector2(65, 120)
		em.scale = Vector2.ZERO
		_results_root.add_child(em)
		var etw := em.create_tween()
		etw.tween_interval(0.6)
		etw.tween_property(em, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		var bob := em.create_tween().set_loops()
		bob.tween_interval(1.0)
		bob.tween_property(em, "rotation", 0.07, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		bob.tween_property(em, "rotation", -0.07, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _reveal(c: Control, delay: float) -> void:
	var tw := c.create_tween()
	tw.tween_interval(delay)
	tw.tween_callback(func() -> void:
		c.pivot_offset = c.size * 0.5
		c.scale = Vector2(0.86, 0.86))
	tw.tween_property(c, "modulate:a", 1.0, 0.16)
	tw.parallel().tween_property(c, "scale", Vector2.ONE, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# --- widget helpers ------------------------------------------------------------

func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", maxi(4, size / 8))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _row_label(text: String, color: Color, align: HorizontalAlignment) -> Label:
	var l := _label(text, 26, color)
	l.horizontal_alignment = align
	l.custom_minimum_size = Vector2(150, 0)
	return l


func _pill(parent: Node, preset: int, pos: Vector2, size: Vector2) -> PanelContainer:
	var p := PanelContainer.new()
	var sb: StyleBox = Juice.panel_box(PANEL_TINT, 18, 6)
	if sb != null:
		(sb as StyleBoxTexture).content_margin_left = 22
		(sb as StyleBoxTexture).content_margin_right = 22
		(sb as StyleBoxTexture).content_margin_top = 8
		(sb as StyleBoxTexture).content_margin_bottom = 8
	else:
		var flat := StyleBoxFlat.new()
		flat.bg_color = Color(0.12, 0.08, 0.05, 0.66)
		flat.border_color = Color(0.66, 0.41, 0.23, 0.9)
		flat.set_border_width_all(3)
		flat.set_corner_radius_all(20)
		flat.content_margin_left = 16
		flat.content_margin_right = 16
		flat.content_margin_top = 4
		flat.content_margin_bottom = 4
		sb = flat
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)
	if preset >= 0:
		p.position = Vector2(800, 0) + pos
	return p


func _icon(tex: Texture2D, px: float) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.custom_minimum_size = Vector2(px, px)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _coin_dot() -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(34, 34)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func():
		c.draw_circle(Vector2(17, 17), 15.0, Color("#b8860b"))
		c.draw_circle(Vector2(17, 17), 12.0, GOLD)
		c.draw_arc(Vector2(17, 17), 8.0, 0.0, TAU, 20, Color("#d4a017"), 2.0))
	return c


func _style_button(btn: Button, color: Color, font_size: int) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		var c := color
		if state == "hover":
			c = color.lightened(0.15)
		elif state == "pressed":
			c = color.darkened(0.2)
		elif state == "disabled":
			c = color.darkened(0.45)
		sb.bg_color = c
		sb.border_color = c.darkened(0.45)
		sb.set_border_width_all(4)
		sb.set_corner_radius_all(16)
		sb.shadow_color = Color(0, 0, 0, 0.35)
		sb.shadow_size = 5
		sb.content_margin_left = 16
		sb.content_margin_right = 16
		btn.add_theme_stylebox_override(state, sb)
	btn.add_theme_font_size_override("font_size", font_size)
	btn.add_theme_color_override("font_color", CREAM)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_outline_color", INK)
	btn.add_theme_constant_override("outline_size", 5)
