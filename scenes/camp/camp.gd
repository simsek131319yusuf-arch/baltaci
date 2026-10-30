extends Control
## Camp hub: top bar, upgrade bench ("Balta Tezgahı"), mascot, start button, settings.
## All UI is built in code from Balance.upgrades so new upgrades appear without scene edits.

signal sfx_requested(sfx_name: String)   # placeholder hook for the audio layer

const Fmt := preload("res://scenes/ui/fmt.gd")
const UiTheme := preload("res://scenes/ui/ui_theme.gd")
const IconDot := preload("res://scenes/ui/icon_dot.gd")
const Backdrop := preload("res://scenes/camp/camp_backdrop.gd")
const CatPlaceholder := preload("res://scenes/camp/cat_placeholder.gd")
const Juice := preload("res://scenes/ui/juice.gd")
const CoinBurst := preload("res://scenes/ui/coin_burst.gd")
const SceneTransition := preload("res://scenes/ui/scene_transition.gd")

const FOREST_SCENE := "res://scenes/forest/forest.tscn"
const THEME_PATH := "res://scenes/ui/theme.tres"
const GOLD_COUNT_TIME := 0.55
const TOAST_TIME := 4.5

## Display info per stat: label + value formatter.
const STAT_LABELS := {
	"axe_damage": "Hasar",
	"swing_interval": "Vuruş aralığı",
	"run_time": "Vardiya süresi",
	"fall_power": "Devrilme hasarı",
	"crit_chance": "Kritik şansı",
}

var _gold_label: Label
var _chain_label: Label
var _runs_label: Label
var _cards: Dictionary = {}          # upgrade id -> {root, level, stat, cost, button}
var _shown_gold: float = 0.0
var _gold_tween: Tween
var _toast: PanelContainer
var _toast_label: Label
var _toast_tween: Tween
var _settings_overlay: Control
var _confirm: ConfirmationDialog
var _start_button: Button
var _message_label: Label
var _cat: Control
var _autoshot_path := ""
var _coins: Control
var _gold_icon: Control
var _gold_punch_tw: Tween
var _hop_tw: Tween
var _idle_tw: Tween
var _coin_target: Control            # card the paying coins are flying to
var _card_punch_tw: Tween


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = load(THEME_PATH) if ResourceLoader.exists(THEME_PATH) else UiTheme.build()
	var args := _parse_args()
	if args.has("autoshot") or args.has("autoshot-gold") or args.has("autoshot-toast"):
		GameState.persist = false   # preview runs never write the real save
	if args.has("autoshot-gold"):
		GameState.gold = float(args["autoshot-gold"])   # in-memory only
	if args.has("autoshot-toast") and GameState.last_run.is_empty():
		GameState.last_run = {"total": 1280.0, "longest_chain": 4, "logs": {}}
	_build_backdrop()
	_build_cat()
	_build_top_bar()
	_build_bench()
	_build_start_button()
	_build_toast()
	_build_settings()
	_coins = CoinBurst.new()
	add_child(_coins)
	_coins.arrived.connect(_on_coin_arrived)
	GameState.changed.connect(_refresh)
	_shown_gold = GameState.gold
	var arrival_delay := 0.0
	if not GameState.last_run.is_empty():
		# Coming back from a shift: count the shown gold up from the pre-run balance.
		_shown_gold = maxf(0.0, GameState.gold - float(GameState.last_run.get("total", 0.0)))
		arrival_delay = 0.55
	_refresh(arrival_delay)
	_show_last_run_toast()
	if args.has("autoshot-buy"):
		_autobuy.call_deferred()
	if args.has("autoshot"):
		_autoshot_path = str(args["autoshot"])
		_run_autoshot()
	if not (args.has("autoshot") or args.has("autoshot-gold") or args.has("autoshot-toast") or args.has("autoshot-buy")):
		_notify_camp_enter.call_deferred()   # preview runs never open story dialogs


# ---------------------------------------------------------------- building

func _build_backdrop() -> void:
	var bd := Backdrop.new()
	bd.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bd)


func _build_cat() -> void:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.anchor_top = 1.0
	holder.anchor_bottom = 1.0
	holder.offset_left = 190.0
	holder.offset_right = 490.0
	holder.offset_top = -475.0
	holder.offset_bottom = -185.0
	add_child(holder)
	var tex := Art.tex("cat/idle")
	if tex != null:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(tr)
	else:
		var cat := CatPlaceholder.new()
		cat.set_anchors_preset(Control.PRESET_FULL_RECT)
		holder.add_child(cat)
	_cat = holder
	# Gentle idle bob: squash/stretch from the feet.
	_cat.pivot_offset = Vector2(150.0, 290.0)
	var tw := create_tween().set_loops()
	_idle_tw = tw
	tw.tween_property(_cat, "scale", Vector2(1.015, 0.975), 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_cat, "scale", Vector2(0.99, 1.02), 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _icon(art_id: String, kind: String, px: float = 32.0) -> Control:
	var tex := Art.tex(art_id)
	if tex != null:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.custom_minimum_size = Vector2(px, px)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return tr
	var dot := IconDot.new()
	dot.kind = kind
	dot.icon_size = px
	return dot


func _build_top_bar() -> void:
	var bar := PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = 24.0
	bar.offset_right = -24.0
	bar.offset_top = 16.0
	var bar_wood: StyleBox = Juice.panel_box(Color(0.46, 0.34, 0.29), 20, 2)
	if bar_wood != null:
		bar.add_theme_stylebox_override("panel", bar_wood)
	add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	bar.add_child(row)

	_gold_icon = _icon("ui/coin", "coin", 40.0)
	row.add_child(_gold_icon)
	_gold_label = Label.new()
	_gold_label.theme_type_variation = "GoldLabel"
	_gold_label.custom_minimum_size.x = 110.0
	row.add_child(_gold_label)
	row.add_child(VSeparator.new())

	row.add_child(_icon("ui/chain", "chain", 32.0))
	_chain_label = Label.new()
	_chain_label.add_theme_font_size_override("font_size", 22)
	row.add_child(_chain_label)
	row.add_child(VSeparator.new())

	row.add_child(_icon("ui/clock", "runs", 32.0))
	_runs_label = Label.new()
	_runs_label.add_theme_font_size_override("font_size", 22)
	row.add_child(_runs_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	var gear := Button.new()
	gear.theme_type_variation = "WoodButton"
	gear.text = "⚙ Ayarlar"
	gear.focus_mode = Control.FOCUS_NONE
	gear.pressed.connect(_open_settings)
	row.add_child(gear)
	Juice.button(gear, 1.07, 0.92)


func _build_bench() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -740.0
	panel.offset_right = -24.0
	panel.offset_top = 104.0
	var wood: StyleBox = Juice.panel_box(Color(0.46, 0.34, 0.29), 22, 12)
	if wood != null:
		panel.add_theme_stylebox_override("panel", wood)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	var title := Label.new()
	title.theme_type_variation = "TitleLabel"
	title.text = "Balta Tezgahı"
	box.add_child(title)
	var sub := Label.new()
	sub.theme_type_variation = "DimLabel"
	sub.text = "Altınını balta ve vardiya geliştirmeye harca."
	box.add_child(sub)

	for u in Balance.upgrades:
		var card := _make_card(u)
		box.add_child(card.root)
		_cards[u.id] = card


func _make_card(u: Dictionary) -> Dictionary:
	var root := PanelContainer.new()
	root.theme_type_variation = "CardPanel"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	root.add_child(row)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)
	row.add_child(info)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	info.add_child(head)
	var name_lbl := Label.new()
	name_lbl.text = str(u.name)
	name_lbl.add_theme_font_size_override("font_size", 24)
	head.add_child(name_lbl)
	var level_lbl := Label.new()
	level_lbl.theme_type_variation = "DimLabel"
	head.add_child(level_lbl)
	var stat_lbl := Label.new()
	stat_lbl.add_theme_font_size_override("font_size", 19)
	info.add_child(stat_lbl)

	var buy_box := VBoxContainer.new()
	buy_box.add_theme_constant_override("separation", 4)
	buy_box.custom_minimum_size.x = 150.0
	row.add_child(buy_box)
	var cost_row := HBoxContainer.new()
	cost_row.alignment = BoxContainer.ALIGNMENT_CENTER
	cost_row.add_theme_constant_override("separation", 6)
	buy_box.add_child(cost_row)
	cost_row.add_child(_icon("ui/coin", "coin", 22.0))
	var cost_lbl := Label.new()
	cost_lbl.add_theme_font_size_override("font_size", 21)
	cost_row.add_child(cost_lbl)
	var button := Button.new()
	button.text = "Geliştir"
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(_on_buy.bind(str(u.id)))
	buy_box.add_child(button)
	Juice.button(button, 1.06, 0.92)

	root.resized.connect(func() -> void: root.pivot_offset = root.size * 0.5)
	return {"root": root, "level": level_lbl, "stat": stat_lbl, "cost": cost_lbl, "button": button, "cost_color_ok": cost_lbl.get_theme_color("font_color", "Label")}


func _build_start_button() -> void:
	_start_button = Button.new()
	_start_button.text = "Vardiyaya Başla"
	_start_button.add_theme_font_size_override("font_size", 36)
	_start_button.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_start_button.offset_left = 110.0
	_start_button.offset_right = 520.0
	_start_button.offset_top = -150.0
	_start_button.offset_bottom = -52.0
	_start_button.focus_mode = Control.FOCUS_NONE
	_start_button.pressed.connect(_on_start)
	add_child(_start_button)
	Juice.button(_start_button, 1.05, 0.95)
	var lift := create_tween().set_loops()
	lift.tween_property(_start_button, "modulate", Color(1.12, 1.12, 1.05), 0.9).set_trans(Tween.TRANS_SINE)
	lift.tween_property(_start_button, "modulate", Color.WHITE, 0.9).set_trans(Tween.TRANS_SINE)

	_message_label = Label.new()
	_message_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_message_label.offset_left = 110.0
	_message_label.offset_right = 620.0
	_message_label.offset_top = -44.0
	_message_label.offset_bottom = -12.0
	_message_label.add_theme_color_override("font_color", Color("ffd9a0"))
	add_child(_message_label)


func _build_toast() -> void:
	_toast = PanelContainer.new()
	_toast.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_toast.offset_left = 40.0
	_toast.offset_top = 96.0
	_toast.modulate.a = 0.0
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_label = Label.new()
	_toast_label.add_theme_font_size_override("font_size", 24)
	_toast.add_child(_toast_label)
	add_child(_toast)


func _build_settings() -> void:
	_settings_overlay = Control.new()
	_settings_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings_overlay.visible = false
	add_child(_settings_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings_overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 440.0
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	var title := Label.new()
	title.theme_type_variation = "TitleLabel"
	title.text = "Ayarlar"
	box.add_child(title)
	var note := Label.new()
	note.theme_type_variation = "DimLabel"
	note.text = "İlerleme otomatik kaydedilir."
	box.add_child(note)
	var reset := Button.new()
	reset.theme_type_variation = "DangerButton"
	reset.text = "İlerlemeyi Sıfırla"
	reset.focus_mode = Control.FOCUS_NONE
	reset.pressed.connect(func() -> void: _confirm.popup_centered())
	box.add_child(reset)
	Juice.button(reset, 1.04, 0.95)
	var close := Button.new()
	close.theme_type_variation = "WoodButton"
	close.text = "Kapat"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func() -> void: _settings_overlay.visible = false)
	box.add_child(close)
	Juice.button(close, 1.04, 0.95)

	_confirm = ConfirmationDialog.new()
	_confirm.theme = theme
	_confirm.title = "Emin misin?"
	_confirm.dialog_text = "Tüm altın ve geliştirmeler silinecek. Bu işlem geri alınamaz."
	_confirm.ok_button_text = "Sıfırla"
	_confirm.cancel_button_text = "Vazgeç"
	_confirm.confirmed.connect(_on_reset_confirmed)
	add_child(_confirm)


# ---------------------------------------------------------------- state -> UI

func _refresh(delay: float = 0.0) -> void:
	_chain_label.text = "En uzun zincir: %d" % GameState.best_chain
	_runs_label.text = "Vardiya: %d" % GameState.runs
	_count_gold_to(GameState.gold, delay)
	for id in _cards:
		_refresh_card(str(id))


func _count_gold_to(target: float, delay: float = 0.0) -> void:
	if _gold_tween != null and _gold_tween.is_valid():
		_gold_tween.kill()
	if is_equal_approx(_shown_gold, target):
		_set_shown_gold(target)
		return
	_gold_tween = create_tween()
	if delay > 0.0:
		_set_shown_gold(_shown_gold)
		_gold_tween.tween_interval(delay)
	_gold_tween.tween_method(_set_shown_gold, _shown_gold, target, GOLD_COUNT_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _set_shown_gold(v: float) -> void:
	_shown_gold = v
	_gold_label.text = Fmt.num(v)


func _refresh_card(id: String) -> void:
	var card: Dictionary = _cards[id]
	var u := Balance.get_upgrade(id)
	var lvl := GameState.level_of(id)
	var maxed := Balance.is_maxed(id, lvl)
	var affordable := GameState.can_buy(id)
	var stat_name := str(u.stat)
	var cur := GameState.stat(stat_name)

	card.level.text = "Sv %d/%d" % [lvl, int(u.max_level)]
	var label: String = STAT_LABELS.get(stat_name, stat_name)
	var suffix := ""
	if stat_name == "fall_power":
		suffix = " (%s)" % _fall_ref_name()
	if maxed:
		card.stat.text = "%s: %s%s" % [label, _fmt_stat(stat_name, cur), suffix]
		card.cost.text = "MAKS"
		card.button.text = "MAKS"
	else:
		var nxt := Balance.compute_stat(stat_name, _levels_plus(id))
		card.stat.text = "%s: %s  →  %s%s" % [label, _fmt_stat(stat_name, cur), _fmt_stat(stat_name, nxt), suffix]
		card.cost.text = Fmt.num(GameState.next_cost(id))
		card.button.text = "Geliştir"
	card.button.disabled = not affordable
	card.cost.add_theme_color_override("font_color", card.cost_color_ok if (affordable or maxed) else Color("d9806a"))
	card.root.theme_type_variation = "CardPanel" if affordable else "CardPanelOff"
	card.root.modulate = Color.WHITE if (affordable or maxed) else Color(1, 1, 1, 0.8)


func _levels_plus(id: String) -> Dictionary:
	var lv: Dictionary = GameState.levels.duplicate()
	lv[id] = GameState.level_of(id) + 1
	return lv


func _fmt_stat(stat_name: String, v: float) -> String:
	match stat_name:
		"axe_damage":
			return Fmt.dec(v, 1)
		"swing_interval", "run_time":
			return Fmt.seconds(v)
		"fall_power":
			# fall_power is damage per px of tree height: show the real damage dealt to a neighbour
			# of the reference tree (kavak), which is what the player feels.
			return str(int(round(v * _fall_ref_height())))
		"crit_chance":
			return Fmt.percent(v)
	return Fmt.dec(v, 2)


func _fall_ref_id() -> String:
	return str(Balance.tree_order[0]) if not Balance.tree_order.is_empty() else ""


func _fall_ref_height() -> float:
	return float(Balance.trees.get(_fall_ref_id(), {}).get("height", 260))


func _fall_ref_name() -> String:
	return str(Balance.trees.get(_fall_ref_id(), {}).get("name", "ağaç"))


# ---------------------------------------------------------------- actions

func _on_buy(id: String) -> void:
	var card: Dictionary = _cards[id]
	var btn: Control = card.button
	var from := btn.global_position + btn.size * 0.5
	if not GameState.buy(id):
		return
	sfx_requested.emit("buy")
	var root: Control = card.root
	# Card: squash-pop plus a warm flash that fades back.
	root.pivot_offset = root.size * 0.5
	var tw := create_tween()
	tw.tween_property(root, "scale", Vector2(1.035, 1.07), 0.07).set_ease(Tween.EASE_OUT)
	tw.tween_property(root, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var fl := create_tween()
	fl.tween_property(root, "self_modulate", Color(1.9, 1.7, 1.1), 0.06)
	fl.tween_property(root, "self_modulate", Color.WHITE, 0.4).set_trans(Tween.TRANS_SINE)
	Juice.pop(card.level, 1.55, 0.36)
	Juice.pop(card.stat, 1.08, 0.3)
	# Paying: coins leave the gold counter and fly to the bought card; each landing nudges the card.
	var src := _gold_icon.global_position + _gold_icon.size * 0.5
	_coin_target = root
	_coins.burst(src, root.global_position + root.size * 0.5, 9, 0.45)
	_gold_dip()
	_cat_hop()


## The counter flinches as the coins leave it.
func _gold_dip() -> void:
	_gold_label.pivot_offset = Vector2(0.0, _gold_label.size.y * 0.5)
	_gold_label.scale = Vector2(0.86, 0.86)
	_gold_icon.pivot_offset = _gold_icon.size * 0.5
	_gold_icon.scale = Vector2(0.82, 0.82)
	if _gold_punch_tw != null and _gold_punch_tw.is_valid():
		_gold_punch_tw.kill()
	_gold_punch_tw = create_tween().set_parallel(true)
	_gold_punch_tw.tween_property(_gold_label, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_gold_punch_tw.tween_property(_gold_icon, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## A coin landed on the bought card: small nudge + warm flash.
func _on_coin_arrived() -> void:
	if _coin_target == null or not is_instance_valid(_coin_target):
		return
	_coin_target.pivot_offset = _coin_target.size * 0.5
	_coin_target.scale = Vector2(1.018, 1.03)
	if _card_punch_tw != null and _card_punch_tw.is_valid():
		_card_punch_tw.kill()
	_card_punch_tw = create_tween()
	_card_punch_tw.tween_property(_coin_target, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Pipsy hops for joy: squash, stretch up, land with a bounce.
func _cat_hop() -> void:
	if _cat == null:
		return
	if _hop_tw != null and _hop_tw.is_valid():
		_hop_tw.kill()
	var base_y := _cat.position.y if _hop_base < 0.0 else _hop_base
	_hop_base = base_y
	if _idle_tw != null and _idle_tw.is_valid():
		_idle_tw.pause()
	_hop_tw = create_tween()
	_hop_tw.tween_property(_cat, "scale", Vector2(1.06, 0.93), 0.07)
	_hop_tw.tween_property(_cat, "position:y", base_y - 34.0, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_hop_tw.parallel().tween_property(_cat, "scale", Vector2(0.97, 1.05), 0.16)
	_hop_tw.tween_property(_cat, "position:y", base_y, 0.2).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	_hop_tw.parallel().tween_property(_cat, "scale", Vector2(1.0, 1.0), 0.2)
	_hop_tw.tween_callback(func() -> void:
		if _idle_tw != null and _idle_tw.is_valid():
			_idle_tw.play())


var _hop_base := -1.0


func _autobuy() -> void:
	# Preview helper (--autoshot-buy): buys the first affordable upgrade so the effect can be captured.
	for id in _cards:
		if GameState.can_buy(str(id)):
			_on_buy(str(id))
			return


## Story: camp_enter beats open only after the scene transition finished (and the gold count-up had a moment).
func _notify_camp_enter() -> void:
	while is_inside_tree() and _transition_busy():
		await get_tree().process_frame
	if not is_inside_tree():
		return
	await get_tree().create_timer(0.6).timeout
	if not is_inside_tree() or _transition_busy():
		return   # already leaving again
	Story.notify("camp_enter", {"runs": GameState.runs, "gold": GameState.gold, "best_chain": GameState.best_chain,
		"max_depth": GameState.max_depth, "last_run": GameState.last_run})


func _transition_busy() -> bool:
	var tr := get_tree().root.get_node_or_null(SceneTransition.NODE_NAME)
	return tr != null and bool(tr.get("busy"))


func _on_start() -> void:
	if not ResourceLoader.exists(FOREST_SCENE):
		_message_label.text = "Orman henüz hazır değil, birazdan açılacak."
		return
	sfx_requested.emit("start")
	var c := (_start_button.global_position + _start_button.size * 0.5) / Vector2(1600, 900)
	SceneTransition.go(get_tree(), FOREST_SCENE, c)


func _open_settings() -> void:
	_settings_overlay.visible = true


func _on_reset_confirmed() -> void:
	GameState.reset()
	_settings_overlay.visible = false
	_show_toast("İlerleme sıfırlandı.")


func _show_last_run_toast() -> void:
	if GameState.last_run.is_empty():
		return
	var lr: Dictionary = GameState.last_run
	_show_toast("Son vardiya: +%s altın, en uzun zincir %d" % [Fmt.num(float(lr.get("total", 0.0))), int(lr.get("longest_chain", 0))])
	GameState.last_run = {}   # shown once; the forest scene refills it on the next run


func _show_toast(text: String) -> void:
	_toast_label.text = text
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast.offset_top = 80.0
	_toast_tween = create_tween()
	_toast_tween.set_parallel(true)
	_toast_tween.tween_property(_toast, "modulate:a", 1.0, 0.25)
	_toast_tween.tween_property(_toast, "offset_top", 96.0, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_toast_tween.chain().tween_interval(TOAST_TIME)
	_toast_tween.chain().tween_property(_toast, "modulate:a", 0.0, 0.6)


# ---------------------------------------------------------------- autoshot

func _parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			continue
		var kv := a.substr(2).split("=", true, 1)
		out[kv[0]] = kv[1] if kv.size() > 1 else "1"
	return out


func _run_autoshot() -> void:
	await get_tree().create_timer(1.5 if not OS.get_cmdline_user_args().has("--autoshot-buy") else 0.4).timeout
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(_autoshot_path)
	print("autoshot: ", _autoshot_path, " -> ", error_string(err))
	get_tree().quit(0 if err == OK else 1)
