extends Control
## Round character portrait. Uses the character's art id when present (optionally cropped via
## `portrait_crop` = [x, y, w, h] fractions), otherwise a coloured disc with the initial.
## The art is clipped to the disc (textured polygon), width-fitted and top-aligned (busts).

const RING := Color("2b1d14")
const SEGMENTS := 72

var _tex: Texture2D = null
var _color := Color("8a6f4a")
var _initial := "?"


func set_character(ch: Dictionary, who_id: String = "") -> void:
	_color = Color.from_string(str(ch.get("color", "#8a6f4a")), Color("8a6f4a"))
	var nm := str(ch.get("name", who_id))
	_initial = nm.substr(0, 1) if not nm.is_empty() else "?"
	_tex = null
	var aid := str(ch.get("portrait", ""))
	if not aid.is_empty():
		var t: Texture2D = Art.tex(aid)
		if t != null:
			var crop = ch.get("portrait_crop")
			if typeof(crop) == TYPE_ARRAY and crop.size() == 4:
				var img := t.get_image()
				if img != null:
					var sz := img.get_size()
					var r := Rect2i(int(sz.x * float(crop[0])), int(sz.y * float(crop[1])), int(sz.x * float(crop[2])), int(sz.y * float(crop[3])))
					t = ImageTexture.create_from_image(img.get_region(r.intersection(Rect2i(Vector2i.ZERO, sz))))
			_tex = t
	queue_redraw()


func has_art() -> bool:
	return _tex != null


func _draw() -> void:
	var r := minf(size.x, size.y) * 0.5
	var c := size * 0.5
	var inner := r - 5.0
	draw_circle(c, r, RING)
	if _tex == null:
		draw_circle(c, inner, _color.darkened(0.15))
		var f := ThemeDB.fallback_font
		var fs := int(r * 1.1)
		var w := f.get_string_size(_initial, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		draw_string(f, c + Vector2(-w.x * 0.5, fs * 0.36), _initial, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("fdf6e0"))
		return
	draw_circle(c, inner, _color.lerp(Color("f6ead0"), 0.6))
	var ts := _tex.get_size()
	var dw := inner * 2.0
	var dh := dw * ts.y / ts.x
	var dst := Rect2(c.x - inner, c.y - inner, dw, dh)   # width-fit, top-aligned
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	for i in SEGMENTS:
		var a := TAU * float(i) / SEGMENTS
		var p := c + Vector2(cos(a), sin(a)) * inner
		pts.append(p)
		uvs.append(((p - dst.position) / dst.size).clamp(Vector2.ZERO, Vector2.ONE))
	draw_polygon(pts, PackedColorArray([Color.WHITE]), uvs, _tex)
	draw_arc(c, inner + 2.0, 0.0, TAU, SEGMENTS, RING, 5.0, true)
