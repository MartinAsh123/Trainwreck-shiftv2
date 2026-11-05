class_name XPStyle
extends RefCounted
## Colours and drawing helpers for the terminal's early-2000s desktop look: glossy blue title
## bars and taskbar, a green start button, beige dialog faces, rounded corners. Everything is drawn
## with vertex-coloured polygons (no image assets).

const FACE := Color("ece9d8")            # dialog / window body
const FACE_DARK := Color("aca899")
const WHITE := Color.WHITE
const TEXT := Color("000000")
const TITLE_TEXT := Color.WHITE
const SELECT := Color("316ac5")
const TITLE_ACTIVE: Array[Color] = [Color("0997ff"), Color("0053ee"), Color("0050ee"), Color("06f")]
const TITLE_INACTIVE: Array[Color] = [Color("a6b8e8"), Color("7b97e0"), Color("7a96df"), Color("8aa3e6")]
const TASKBAR: Array[Color] = [Color("3d95ff"), Color("245edb"), Color("245edb"), Color("1941a5")]
const START: Array[Color] = [Color("5fbf5f"), Color("3c9a3c"), Color("318a31"), Color("2a7a2a")]
const TRAY: Array[Color] = [Color("19b9f3"), Color("0d8dea"), Color("0d8dea"), Color("0a6fc7")]
const MENU_HEAD: Array[Color] = [Color("1c6ef0"), Color("0e57d6"), Color("0e57d6"), Color("1660e0")]
const CLOSE: Array[Color] = [Color("e8a78a"), Color("d8562f"), Color("c8401c"), Color("b8350f")]
const BUTTON: Array[Color] = [Color("ffffff"), Color("f3f3ef"), Color("ebeae4"), Color("d6d0c5")]
const BUTTON_HOT: Array[Color] = [Color("fff6dc"), Color("fbe6a8"), Color("f8d27a"), Color("eab547")]

static var _font: Font
static var _bold: Font

static func font() -> Font:
	if _font == null:
		_font = ThemeDB.fallback_font
	return _font

static func bold() -> Font:
	if _bold == null:
		var fv := FontVariation.new()
		fv.base_font = font()
		fv.variation_embolden = 0.9
		_bold = fv
	return _bold

## Rounded rectangle filled with a four-stop vertical gradient (top highlight, upper, lower,
## bottom). `r` = [top-left, top-right, bottom-right, bottom-left] radii.
static func gradient_rect(ci: CanvasItem, rect: Rect2, cols: Array, r: Array = [0, 0, 0, 0]) -> void:
	var pts := PackedVector2Array()
	var colors := PackedColorArray()
	var corners := [[rect.position + Vector2(r[0], r[0]), PI, 1.5 * PI, r[0]],
			[Vector2(rect.end.x - r[1], rect.position.y + r[1]), 1.5 * PI, TAU, r[1]],
			[rect.end - Vector2(r[2], r[2]), 0.0, 0.5 * PI, r[2]],
			[Vector2(rect.position.x + r[3], rect.end.y - r[3]), 0.5 * PI, PI, r[3]]]
	for ci_i in 4:
		var c: Array = corners[ci_i]
		var rad: float = c[3]
		var steps := 1 if rad <= 0.0 else 6
		for k in steps + 1:
			var a := lerpf(c[1], c[2], float(k) / steps)
			var p: Vector2 = c[0] + Vector2(cos(a), sin(a)) * rad
			pts.append(p)
		# Extra points down the sides so the gradient has its middle stops.
		if ci_i == 1 or ci_i == 3:
			var x := rect.end.x if ci_i == 1 else rect.position.x
			var y_lo: float = rect.position.y + (r[1] if ci_i == 1 else r[0]) + 0.5
			var y_hi: float = rect.end.y - (r[2] if ci_i == 1 else r[3]) - 0.5
			var ys := [0.12, 0.5, 0.88] if ci_i == 1 else [0.88, 0.5, 0.12]
			for f: float in ys:
				var y: float = rect.position.y + rect.size.y * f
				if y > y_lo and y < y_hi:
					pts.append(Vector2(x, y))
	for p in pts:
		colors.append(_grad(cols, (p.y - rect.position.y) / maxf(rect.size.y, 1.0)))
	ci.draw_polygon(pts, colors)

static func _grad(c: Array, t: float) -> Color:
	if t < 0.12:
		return c[0].lerp(c[1], t / 0.12)
	if t < 0.5:
		return c[1].lerp(c[2], (t - 0.12) / 0.38)
	return c[2].lerp(c[3], (t - 0.5) / 0.5)

static func bevel(ci: CanvasItem, rect: Rect2, sunken: bool) -> void:
	var hi := Color("ffffff") if not sunken else Color("716f64")
	var lo := Color("716f64") if not sunken else Color("ffffff")
	ci.draw_line(rect.position, Vector2(rect.end.x, rect.position.y), hi)
	ci.draw_line(rect.position, Vector2(rect.position.x, rect.end.y), hi)
	ci.draw_line(Vector2(rect.position.x, rect.end.y), rect.end, lo)
	ci.draw_line(Vector2(rect.end.x, rect.position.y), rect.end, lo)

static func text(ci: CanvasItem, p: Vector2, s: String, size: int, col: Color, f: Font = null, shadow := false) -> void:
	var fnt := f if f else font()
	if shadow:
		ci.draw_string(fnt, p + Vector2(1, 1), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, 0.55))
	ci.draw_string(fnt, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

## A themed Theme for the standard controls inside windows (buttons, line edits, lists).
static func theme() -> Theme:
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 13
	var btn := StyleBoxFlat.new()
	btn.bg_color = Color("f4f3ee")
	btn.border_color = Color("003c74")
	btn.set_border_width_all(1)
	btn.set_corner_radius_all(3)
	btn.content_margin_left = 10
	btn.content_margin_right = 10
	btn.content_margin_top = 3
	btn.content_margin_bottom = 3
	var btn_hot := btn.duplicate() as StyleBoxFlat
	btn_hot.bg_color = Color("fdf1d2")
	btn_hot.border_color = Color("e5a50a")
	var btn_down := btn.duplicate() as StyleBoxFlat
	btn_down.bg_color = Color("e3e2da")
	for s in ["normal", "focus"]:
		t.set_stylebox(s, "Button", btn)
	t.set_stylebox("hover", "Button", btn_hot)
	t.set_stylebox("pressed", "Button", btn_down)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", TEXT)
	t.set_color("font_pressed_color", "Button", TEXT)
	t.set_color("font_focus_color", "Button", TEXT)
	var field := StyleBoxFlat.new()
	field.bg_color = WHITE
	field.border_color = Color("7f9db9")
	field.set_border_width_all(1)
	field.content_margin_left = 4
	field.content_margin_right = 4
	field.content_margin_top = 2
	field.content_margin_bottom = 2
	for ty in ["LineEdit", "TextEdit"]:
		t.set_stylebox("normal", ty, field)
		t.set_stylebox("focus", ty, field)
		t.set_color("font_color", ty, TEXT)
		t.set_color("caret_color", ty, TEXT)
		t.set_color("selection_color", ty, SELECT)
	var list := field.duplicate() as StyleBoxFlat
	t.set_stylebox("panel", "Tree", list)
	t.set_stylebox("panel", "ItemList", list)
	t.set_color("font_color", "Tree", TEXT)
	t.set_color("font_color", "ItemList", TEXT)
	t.set_color("font_selected_color", "Tree", WHITE)
	var sel := StyleBoxFlat.new()
	sel.bg_color = SELECT
	t.set_stylebox("selected", "Tree", sel)
	t.set_stylebox("selected_focus", "Tree", sel)
	t.set_stylebox("selected", "ItemList", sel)
	t.set_stylebox("selected_focus", "ItemList", sel)
	t.set_color("font_color", "Label", TEXT)
	var head := StyleBoxFlat.new()
	head.bg_color = Color("ebeadb")
	head.border_color = Color("c7c5b2")
	head.border_width_bottom = 2
	head.border_width_right = 1
	t.set_stylebox("title_button_normal", "Tree", head)
	t.set_stylebox("title_button_hover", "Tree", head)
	t.set_stylebox("title_button_pressed", "Tree", head)
	t.set_color("title_button_color", "Tree", TEXT)
	t.set_constant("v_separation", "Tree", 2)
	return t
