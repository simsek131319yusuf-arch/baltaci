extends CanvasLayer
## Small non-blocking speech bubble for mid-run story hints. Never takes input.
## show_line(character, who_id, text, emote) slides in at the bottom-left, stays ~3 s, fades out.

const StoryPortrait = preload("res://scenes/story/story_portrait.gd")
const PANEL_ART := "ui/panel"
const EMOTES := {"happy": "ui/pipsy_happy", "cry": "ui/pipsy_cry", "wow": "ui/pipsy_wow"}
const HOLD := 3.0
const W := 640.0
const H := 134.0
const X0 := 28.0

var _root: Control
var _portrait: StoryPortrait
var _name: Label
var _text: Label
var _emote: TextureRect
var _tw: Tween


func _ready() -> void:
	layer = 99
	_build()
	_root.visible = false


func _build() -> void:
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.anchor_top = 1.0
	_root.anchor_bottom = 1.0
	_root.offset_left = 28
	_root.offset_right = 28 + W
	_root.offset_top = -(H + 26)
	_root.offset_bottom = -26
	add_child(_root)

	var bg := Panel.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t: Texture2D = Art.tex(PANEL_ART)
	if t != null:
		var sb := StyleBoxTexture.new()
		sb.texture = t
		sb.set_texture_margin_all(34)
		bg.add_theme_stylebox_override("panel", sb)
	else:
		var f := StyleBoxFlat.new()
		f.bg_color = Color("e7c590")
		f.border_color = Color("6b4a2e")
		f.set_border_width_all(5)
		f.set_corner_radius_all(18)
		bg.add_theme_stylebox_override("panel", f)
	_root.add_child(bg)

	_portrait = StoryPortrait.new()
	_portrait.size = Vector2(92, 92)
	_portrait.position = Vector2(24, 20)
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_portrait)

	_name = Label.new()
	_name.position = Vector2(132, 22)
	_name.add_theme_font_size_override("font_size", 20)
	_name.add_theme_color_override("font_shadow_color", Color("3a2514"))
	_name.add_theme_constant_override("shadow_offset_y", 2)
	_name.add_theme_color_override("font_color", Color("fdf0cc"))
	_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_name)

	_text = Label.new()
	_text.position = Vector2(132, 52)
	_text.size = Vector2(W - 132 - 44, 60)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.add_theme_font_size_override("font_size", 22)
	_text.add_theme_color_override("font_color", Color("3a2514"))
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_text)

	_emote = TextureRect.new()
	_emote.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_emote.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_emote.size = Vector2(56, 56)
	_emote.position = Vector2(W - 44, -30)
	_emote.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_emote.visible = false
	_root.add_child(_emote)


func show_line(ch: Dictionary, who_id: String, text: String, emote: String = "") -> void:
	if _tw:
		_tw.kill()
	_portrait.set_character(ch, who_id)
	_name.text = str(ch.get("name", who_id))
	_text.text = text
	var et: Texture2D = Art.tex(EMOTES[emote]) if EMOTES.has(emote) else null
	_emote.texture = et
	_emote.visible = et != null
	_root.visible = true
	_root.modulate.a = 0.0
	_root.position.x = X0 - 60.0
	_tw = create_tween()
	_tw.set_parallel(true)
	_tw.tween_property(_root, "position:x", X0, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tw.tween_property(_root, "modulate:a", 1.0, 0.25)
	_tw.chain().tween_interval(HOLD)
	_tw.chain().tween_property(_root, "modulate:a", 0.0, 0.5).set_trans(Tween.TRANS_SINE)
	_tw.chain().tween_callback(func(): _root.visible = false)
