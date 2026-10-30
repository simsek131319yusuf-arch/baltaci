extends CanvasLayer
## Blocking dialogue overlay, owned by the Story autoload (Story instantiates this scene).
## play(beat, characters) runs an optional letter + the beat's lines; emits finished(skipped).
## Click / Space / Enter: first completes the typewriter, then advances. "Geç" skips the beat.

signal finished(skipped: bool)

const StoryPortrait = preload("res://scenes/story/story_portrait.gd")
const PANEL_ART := "ui/panel"
const LETTER_ART := "story/letter"
const EMOTES := {"happy": "ui/pipsy_happy", "cry": "ui/pipsy_cry", "wow": "ui/pipsy_wow"}

const INK := Color("3a2514")
const INK_SOFT := Color("6b4a2e")
const CREAM := Color("fdf6e0")
const WOOD_DARK := Color("2b1d14")
const GOLD := Color("f2c14e")

const CPS := 52.0                 # typewriter speed, characters per second
const BOX_W := 1260.0
const BOX_H := 224.0
const BOX_BOTTOM := 36.0
const SLIDE := 70.0               # px the box slides up from
const INPUT_COOLDOWN := 0.14      # ignore clicks right after a line starts (double-click guard)

enum S { HIDDEN, LETTER, TYPING, WAITING, CLOSING }

var state: int = S.HIDDEN
var beat: Dictionary = {}
var chars: Dictionary = {}
var line_idx := -1

var _dim: ColorRect
var _slide: Control
var _box: Control
var _panel: Panel
var _portrait: StoryPortrait
var _plate: PanelContainer
var _plate_label: Label
var _text: RichTextLabel
var _arrow: Polygon2D
var _skip: Button
var _emote: TextureRect
var _emote_bubble: Panel
var _letter: Control = null
var _hint: Label

var _typed := 0.0
var _total := 0
var _t := 0.0
var _last_input := -1.0
var _cur_who := ""
var _speaking := false
var _tw_box: Tween
var _tw_dim: Tween
var _tw_emote: Tween
var _tw_pop: Tween


func _ready() -> void:
	layer = 100
	visible = false
	_build()


# ------------------------------------------------------------------ build

func _build() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0.04, 0.03, 0.02, 0.0)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP   # swallows all game input while open
	_dim.gui_input.connect(_on_dim_input)
	add_child(_dim)

	_slide = Control.new()
	_slide.set_anchors_preset(Control.PRESET_FULL_RECT)
	_slide.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_slide)

	_box = Control.new()
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.anchor_left = 0.5
	_box.anchor_right = 0.5
	_box.anchor_top = 1.0
	_box.anchor_bottom = 1.0
	_box.offset_left = -BOX_W * 0.5
	_box.offset_right = BOX_W * 0.5
	_box.offset_top = -(BOX_H + BOX_BOTTOM)
	_box.offset_bottom = -BOX_BOTTOM
	_slide.add_child(_box)

	_panel = Panel.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_theme_stylebox_override("panel", _panel_style())
	_box.add_child(_panel)

	_portrait = StoryPortrait.new()
	_portrait.size = Vector2(210, 210)
	_portrait.position = Vector2(34, -66)
	_portrait.pivot_offset = Vector2(105, 190)
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(_portrait)

	_plate = PanelContainer.new()
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ps := StyleBoxFlat.new()
	ps.bg_color = WOOD_DARK
	ps.border_color = Color("6b4a2e")
	ps.set_border_width_all(3)
	ps.set_corner_radius_all(12)
	ps.content_margin_left = 20
	ps.content_margin_right = 20
	ps.content_margin_top = 5
	ps.content_margin_bottom = 7
	ps.shadow_color = Color(0, 0, 0, 0.35)
	ps.shadow_size = 6
	ps.shadow_offset = Vector2(0, 3)
	_plate.add_theme_stylebox_override("panel", ps)
	_plate.position = Vector2(270, -24)
	_box.add_child(_plate)
	_plate_label = Label.new()
	_plate_label.add_theme_font_size_override("font_size", 26)
	_plate_label.add_theme_color_override("font_color", GOLD)
	_plate.add_child(_plate_label)

	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.scroll_active = false
	_text.fit_content = false
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.position = Vector2(274, 46)
	_text.size = Vector2(BOX_W - 274 - 70, BOX_H - 46 - 34)
	_text.add_theme_font_size_override("normal_font_size", 29)
	_text.add_theme_font_size_override("italics_font_size", 29)
	_text.add_theme_color_override("default_color", INK)
	_box.add_child(_text)

	_arrow = Polygon2D.new()
	_arrow.polygon = PackedVector2Array([Vector2(-11, 0), Vector2(11, 0), Vector2(0, 14)])
	_arrow.color = INK_SOFT
	_arrow.position = Vector2(BOX_W - 62, BOX_H - 42)
	_arrow.visible = false
	_box.add_child(_arrow)

	_skip = Button.new()
	_skip.text = "Geç"
	_skip.focus_mode = Control.FOCUS_NONE
	_skip.mouse_filter = Control.MOUSE_FILTER_STOP
	_skip.custom_minimum_size = Vector2(92, 40)
	_skip.position = Vector2(BOX_W - 116, -22)
	_skip.size = Vector2(92, 40)
	_skip.add_theme_font_size_override("font_size", 22)
	_skip.add_theme_color_override("font_color", CREAM)
	_skip.add_theme_color_override("font_hover_color", Color.WHITE)
	for st in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = {"normal": WOOD_DARK, "hover": Color("4a3222"), "pressed": Color("1d130c")}[st]
		sb.border_color = Color("6b4a2e")
		sb.set_border_width_all(3)
		sb.set_corner_radius_all(12)
		sb.shadow_color = Color(0, 0, 0, 0.3)
		sb.shadow_size = 5
		sb.shadow_offset = Vector2(0, 3)
		_skip.add_theme_stylebox_override(st, sb)
	_skip.pressed.connect(skip)
	_box.add_child(_skip)

	_emote_bubble = Panel.new()
	_emote_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var es := StyleBoxFlat.new()
	es.bg_color = Color("fdf6e0")
	es.border_color = WOOD_DARK
	es.set_border_width_all(4)
	es.set_corner_radius_all(60)
	es.shadow_color = Color(0, 0, 0, 0.3)
	es.shadow_size = 8
	es.shadow_offset = Vector2(0, 4)
	_emote_bubble.add_theme_stylebox_override("panel", es)
	_emote_bubble.size = Vector2(124, 124)
	_emote_bubble.position = Vector2(BOX_W - 250, -150)
	_emote_bubble.pivot_offset = Vector2(62, 124)
	_emote_bubble.visible = false
	_box.add_child(_emote_bubble)
	_emote = TextureRect.new()
	_emote.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_emote.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_emote.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_emote.position = Vector2(10, 8)
	_emote.size = Vector2(104, 104)
	_emote_bubble.add_child(_emote)

	_hint = Label.new()
	_hint.text = "devam etmek için tıkla"
	_hint.add_theme_font_size_override("font_size", 20)
	_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	_hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	_hint.add_theme_constant_override("shadow_offset_y", 2)
	_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.visible = false
	add_child(_hint)


func _panel_style() -> StyleBox:
	var t: Texture2D = Art.tex(PANEL_ART)
	if t != null:
		var sb := StyleBoxTexture.new()
		sb.texture = t
		sb.set_texture_margin_all(40)
		sb.set_content_margin_all(26)
		sb.draw_center = true
		return sb
	var f := StyleBoxFlat.new()
	f.bg_color = Color("e7c590")
	f.border_color = Color("6b4a2e")
	f.set_border_width_all(6)
	f.set_corner_radius_all(22)
	f.shadow_color = Color(0, 0, 0, 0.35)
	f.shadow_size = 10
	f.shadow_offset = Vector2(0, 5)
	return f


# ------------------------------------------------------------------ public API

func is_open() -> bool:
	return state != S.HIDDEN


## Starts a beat. Safe to call only when closed (Story guarantees this).
func play(b: Dictionary, characters: Dictionary) -> void:
	beat = b
	chars = characters
	line_idx = -1
	_cur_who = ""
	visible = true
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_fade_dim(0.5)
	_box.modulate.a = 0.0
	_slide.position.y = SLIDE
	_text.text = ""
	_emote_bubble.visible = false
	_arrow.visible = false
	var lt = b.get("letter")
	if typeof(lt) == TYPE_DICTIONARY:
		_show_letter(lt)
	else:
		_open_box_and_start()


## Same as clicking: completes the typewriter, or goes to the next line.
func advance() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_input < INPUT_COOLDOWN:
		return
	_last_input = now
	match state:
		S.LETTER:
			_close_letter()
		S.TYPING:
			_typed = float(_total)
			_text.visible_characters = -1
			_enter_waiting()
		S.WAITING:
			_next_line()


func skip() -> void:
	if state == S.HIDDEN or state == S.CLOSING:
		return
	_close(true)


# ------------------------------------------------------------------ input

func _on_dim_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		advance()
		_dim.accept_event()


func _input(ev: InputEvent) -> void:
	if state == S.HIDDEN or state == S.CLOSING:
		return
	if ev is InputEventKey and ev.pressed and not ev.echo:
		if ev.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
			advance()
			get_viewport().set_input_as_handled()
		elif ev.keycode == KEY_ESCAPE:
			skip()
			get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ flow

func _open_box_and_start() -> void:
	if _tw_box:
		_tw_box.kill()
	_tw_box = create_tween().set_parallel(true)
	_tw_box.tween_property(_slide, "position:y", 0.0, 0.42).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tw_box.tween_property(_box, "modulate:a", 1.0, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_next_line()


func _next_line() -> void:
	line_idx += 1
	var lines: Array = beat.get("lines", [])
	if line_idx >= lines.size():
		_close(false)
		return
	var l: Dictionary = lines[line_idx]
	var who := str(l.get("who", ""))
	var ch: Dictionary = chars.get(who, {})
	if who != _cur_who:
		_cur_who = who
		_portrait.set_character(ch, who)
		_plate_label.text = str(ch.get("name", who))
		_plate_label.add_theme_color_override("font_color", Color.from_string(str(ch.get("color", "#f2c14e")), GOLD).lightened(0.45))
		_pop_portrait()
	_speaking = not bool(ch.get("silent", false))
	var txt := str(l.get("text", ""))
	_total = txt.length()
	_text.text = txt if _speaking else "[i]%s[/i]" % txt.replace("[", "[lb]")
	_text.visible_characters = 0
	_typed = 0.0
	_arrow.visible = false
	_last_input = Time.get_ticks_msec() / 1000.0
	state = S.TYPING
	_set_emote(str(l.get("emote", "")))


func _enter_waiting() -> void:
	state = S.WAITING
	_arrow.visible = true


func _set_emote(kind: String) -> void:
	if _tw_emote:
		_tw_emote.kill()
	var t: Texture2D = null
	if not kind.is_empty() and EMOTES.has(kind):
		t = Art.tex(EMOTES[kind])
	if t == null:
		if _emote_bubble.visible:
			_tw_emote = create_tween()
			_tw_emote.tween_property(_emote_bubble, "scale", Vector2.ZERO, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
			_tw_emote.tween_callback(func(): _emote_bubble.visible = false)
		return
	_emote.texture = t
	_emote_bubble.visible = true
	_emote_bubble.scale = Vector2.ZERO
	_tw_emote = create_tween()
	_tw_emote.tween_interval(0.12)
	_tw_emote.tween_property(_emote_bubble, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _pop_portrait() -> void:
	if _tw_pop:
		_tw_pop.kill()
	_portrait.scale = Vector2(0.86, 0.86)
	_portrait.modulate.a = 0.0
	_tw_pop = create_tween().set_parallel(true)
	_tw_pop.tween_property(_portrait, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tw_pop.tween_property(_portrait, "modulate:a", 1.0, 0.18)


func _close(skipped: bool) -> void:
	state = S.CLOSING
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP   # stay solid until fully gone
	_hint.visible = false
	_arrow.visible = false
	if _tw_box:
		_tw_box.kill()
	_tw_box = create_tween().set_parallel(true)
	_tw_box.tween_property(_slide, "position:y", SLIDE, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tw_box.tween_property(_box, "modulate:a", 0.0, 0.26)
	if _letter != null:
		_tw_box.tween_property(_letter, "modulate:a", 0.0, 0.22)
	_fade_dim(0.0, 0.3)
	_tw_box.chain().tween_callback(func():
		_cleanup()
		finished.emit(skipped))


func _cleanup() -> void:
	if _letter != null:
		_letter.queue_free()
		_letter = null
	_emote_bubble.visible = false
	_hint.visible = false
	visible = false
	state = S.HIDDEN


func _fade_dim(a: float, dur := 0.35) -> void:
	if _tw_dim:
		_tw_dim.kill()
	_tw_dim = create_tween()
	_tw_dim.tween_property(_dim, "color:a", a, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	_t += delta
	if state == S.TYPING:
		_typed += delta * CPS
		var n := int(_typed)
		_text.visible_characters = n
		if n >= _total:
			_text.visible_characters = -1
			_enter_waiting()
	if state == S.TYPING and _speaking:
		_portrait.position.y = -66.0 - absf(sin(_t * 11.0)) * 6.0
	else:
		_portrait.position.y = lerpf(_portrait.position.y, -66.0, minf(1.0, delta * 14.0))
	if _arrow.visible:
		_arrow.position.y = BOX_H - 44 + sin(_t * 5.0) * 4.0


# ------------------------------------------------------------------ letter

func _show_letter(lt: Dictionary) -> void:
	state = S.LETTER
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	_letter = holder
	var from := str(lt.get("from", ""))
	var body := str(lt.get("text", ""))
	var sheet: Control
	var tex: Texture2D = Art.tex(LETTER_ART)
	var lw := 600.0
	var lh := 600.0
	var top := 0.075   # text block top, fraction of sheet height
	var bot := 0.92
	if tex != null:
		var ts := tex.get_size()
		lh = lw * ts.y / ts.x
		top = 0.105
		bot = 0.72
		sheet = TextureRect.new()
		sheet.texture = tex
		(sheet as TextureRect).expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		(sheet as TextureRect).stretch_mode = TextureRect.STRETCH_SCALE
	else:
		var pn := Panel.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("ecdcae")
		sb.border_color = Color("8a6a3a")
		sb.set_border_width_all(5)
		sb.set_corner_radius_all(10)
		sb.shadow_color = Color(0, 0, 0, 0.4)
		sb.shadow_size = 18
		sb.shadow_offset = Vector2(0, 8)
		pn.add_theme_stylebox_override("panel", sb)
		sheet = pn
	sheet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sheet.size = Vector2(lw, lh)
	sheet.position = Vector2(800 - lw * 0.5, 440 - lh * 0.5)
	sheet.pivot_offset = sheet.size * 0.5
	holder.add_child(sheet)
	if tex != null:
		# the letter art carries decorative scribbles: lay a soft parchment patch under our text
		var patch := Panel.new()
		var psb := StyleBoxFlat.new()
		psb.bg_color = Color("f4e1b0", 0.93)
		psb.set_corner_radius_all(18)
		psb.shadow_color = Color("f4e1b0", 0.9)
		psb.shadow_size = 14
		patch.add_theme_stylebox_override("panel", psb)
		patch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		patch.position = Vector2(lw * 0.115, lh * (top - 0.02))
		patch.size = Vector2(lw * 0.77, lh * (bot - top + 0.035))
		sheet.add_child(patch)
	var serif := SystemFont.new()
	serif.font_names = PackedStringArray(["Georgia", "Palatino Linotype", "Cambria", "Times New Roman", "serif"])
	var head := Label.new()
	head.text = "%s'dan mektup" % from if not from.is_empty() else "Mektup"
	head.add_theme_font_override("font", serif)
	head.add_theme_font_size_override("font_size", 22)
	head.add_theme_color_override("font_color", Color("8a5a2e"))
	head.position = Vector2(lw * 0.14, lh * top)
	head.size = Vector2(lw * 0.72, 30)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sheet.add_child(head)
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = false
	rt.scroll_active = false
	rt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rt.position = Vector2(lw * 0.14, lh * top + 38)
	rt.size = Vector2(lw * 0.72, lh * (bot - top) - 38)
	rt.text = body
	rt.add_theme_font_override("normal_font", serif)
	rt.add_theme_font_size_override("normal_font_size", 23)
	rt.add_theme_color_override("default_color", Color("3a2514"))
	sheet.add_child(rt)
	_hint.visible = true
	_hint.offset_top = -52
	_hint.offset_bottom = -16
	_hint.offset_left = -200
	_hint.offset_right = 200
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# entrance: drop in with a slight tilt
	sheet.modulate.a = 0.0
	sheet.scale = Vector2(0.92, 0.92)
	sheet.rotation = deg_to_rad(-3.0)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(sheet, "modulate:a", 1.0, 0.35)
	tw.tween_property(sheet, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(sheet, "rotation", deg_to_rad(-1.2), 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_last_input = Time.get_ticks_msec() / 1000.0 + 0.3


func _close_letter() -> void:
	_hint.visible = false
	var l := _letter
	_letter = null
	state = S.TYPING   # placeholder; _next_line sets the real state
	if l != null:
		var tw := create_tween().set_parallel(true)
		tw.tween_property(l, "modulate:a", 0.0, 0.25)
		tw.tween_property(l, "position:y", -30.0, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tw.chain().tween_callback(l.queue_free)
	_open_box_and_start()
