extends RefCounted
## Warm forest palette + shared Theme. `scenes/ui/theme.tres` is generated from build()
## by scenes/ui/make_theme.gd; code may also call build() directly.

const WOOD_DARK := Color("2b1d14")
const WOOD := Color("4a3222")
const WOOD_LIGHT := Color("6b4a2e")
const WOOD_EDGE := Color("1d130c")
const CREAM := Color("f6ead0")
const CREAM_DIM := Color("b8a98a")
const LEAF := Color("6aa13f")
const LEAF_DARK := Color("3f6b26")
const LEAF_LIGHT := Color("86bd55")
const GOLD := Color("f2c14e")
const RED := Color("b5482f")


static func box(bg: Color, border: Color, radius: int = 12, border_w: int = 2, bottom_w: int = -1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_border_width_all(border_w)
	if bottom_w >= 0:
		sb.border_width_bottom = bottom_w
	sb.border_color = border
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(12)
	sb.anti_aliasing = true
	return sb


static func build() -> Theme:
	var t := Theme.new()
	t.default_font_size = 20

	t.set_color("font_color", "Label", CREAM)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.45))
	t.set_constant("shadow_offset_x", "Label", 1)
	t.set_constant("shadow_offset_y", "Label", 2)

	var panel := box(Color(WOOD_DARK, 0.92), WOOD_LIGHT, 16, 3)
	panel.set_content_margin_all(16)
	panel.shadow_color = Color(0, 0, 0, 0.35)
	panel.shadow_size = 8
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)

	var card := box(Color(WOOD, 0.95), WOOD_LIGHT, 12, 2)
	card.set_content_margin_all(10)
	t.set_stylebox("panel", "CardPanel", card)
	t.set_type_variation("CardPanel", "PanelContainer")
	var card_off := card.duplicate() as StyleBoxFlat
	card_off.bg_color = Color(WOOD_DARK, 0.85)
	card_off.border_color = Color(WOOD_LIGHT, 0.5)
	t.set_stylebox("panel", "CardPanelOff", card_off)
	t.set_type_variation("CardPanelOff", "PanelContainer")

	# Buttons: chunky leaf-green with a darker lip.
	var normal := box(LEAF, LEAF_DARK, 12, 2, 5)
	var hover := box(LEAF_LIGHT, LEAF_DARK, 12, 2, 5)
	var pressed := box(LEAF_DARK, LEAF_DARK, 12, 2, 2)
	var disabled := box(Color("5a4636"), Color("3a2c20"), 12, 2, 4)
	var focus := box(Color(0, 0, 0, 0), CREAM, 12, 2)
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_stylebox("focus", "Button", focus)
	t.set_color("font_color", "Button", Color("fdf6e0"))
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color("e8dcc0"))
	t.set_color("font_disabled_color", "Button", Color("9c8b72"))
	t.set_font_size("font_size", "Button", 22)

	# Wooden variant (gear, secondary buttons).
	var w_n := box(WOOD_LIGHT, WOOD_EDGE, 12, 2, 4)
	var w_h := box(Color("80593a"), WOOD_EDGE, 12, 2, 4)
	var w_p := box(WOOD, WOOD_EDGE, 12, 2, 2)
	t.set_type_variation("WoodButton", "Button")
	t.set_stylebox("normal", "WoodButton", w_n)
	t.set_stylebox("hover", "WoodButton", w_h)
	t.set_stylebox("pressed", "WoodButton", w_p)

	var danger_n := box(RED, Color("6e2a1a"), 12, 2, 4)
	var danger_h := box(Color("cc5a3e"), Color("6e2a1a"), 12, 2, 4)
	t.set_type_variation("DangerButton", "Button")
	t.set_stylebox("normal", "DangerButton", danger_n)
	t.set_stylebox("hover", "DangerButton", danger_h)
	t.set_stylebox("pressed", "DangerButton", box(Color("8e3822"), Color("6e2a1a"), 12, 2, 2))

	# Headings / accents.
	t.set_type_variation("TitleLabel", "Label")
	t.set_font_size("font_size", "TitleLabel", 30)
	t.set_color("font_color", "TitleLabel", GOLD)
	t.set_type_variation("DimLabel", "Label")
	t.set_color("font_color", "DimLabel", CREAM_DIM)
	t.set_font_size("font_size", "DimLabel", 17)
	t.set_type_variation("GoldLabel", "Label")
	t.set_color("font_color", "GoldLabel", GOLD)
	t.set_font_size("font_size", "GoldLabel", 30)

	var sep := StyleBoxLine.new()
	sep.color = Color(WOOD_LIGHT, 0.8)
	sep.thickness = 2
	t.set_stylebox("separator", "VSeparator", sep)

	# Dialogs inherit panel look.
	t.set_stylebox("panel", "AcceptDialog", box(WOOD_DARK, WOOD_LIGHT, 14, 3))
	t.set_stylebox("embedded_border", "Window", box(WOOD_DARK, WOOD_LIGHT, 14, 3))
	return t
