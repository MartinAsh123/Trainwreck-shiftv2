class_name MenuStyle
extends RefCounted
## The look shared by the main menu, the pause menu and the settings: a 1930s railway timetable,
## dark lacquer with brass edges, Oswald for the text and Playfair for the titles.

const BG := Color(0.07, 0.06, 0.05, 0.94)
const EDGE := Color(0.89, 0.76, 0.49, 0.9)
const TEXT := Color(0.93, 0.9, 0.82)
const DIM := Color(0.6, 0.57, 0.5)
const HOVER := Color(0.2, 0.15, 0.09, 0.95)
const FONT := preload("res://assets/fonts/Oswald.ttf")
const TITLE_FONT := preload("res://assets/fonts/PlayfairDisplay.ttf")

## A Theme for buttons, sliders, check boxes and option lists in the brass-and-lacquer look.
static func theme() -> Theme:
	var t := Theme.new()
	t.default_font = FONT
	t.default_font_size = 20
	var normal := _box(Color(0.1, 0.085, 0.07, 0.9), Color(EDGE, 0.35), 1)
	var hover := _box(HOVER, EDGE, 1)
	var pressed := _box(Color(0.28, 0.21, 0.12, 0.95), EDGE, 2)
	var disabled := _box(Color(0.08, 0.07, 0.06, 0.6), Color(EDGE, 0.12), 1)
	for type: String in ["Button", "OptionButton"]:
		t.set_stylebox("normal", type, normal)
		t.set_stylebox("hover", type, hover)
		t.set_stylebox("pressed", type, pressed)
		t.set_stylebox("focus", type, _box(Color(0, 0, 0, 0), EDGE, 1))
		t.set_stylebox("disabled", type, disabled)
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, EDGE)
		t.set_color("font_pressed_color", type, EDGE)
		t.set_color("font_focus_color", type, EDGE)
		t.set_color("font_disabled_color", type, Color(DIM, 0.6))
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_color", "CheckBox", TEXT)
	t.set_color("font_hover_color", "CheckBox", EDGE)
	t.set_color("font_pressed_color", "CheckBox", TEXT)
	t.set_color("font_hover_pressed_color", "CheckBox", EDGE)
	for s: String in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		t.set_stylebox(s, "CheckBox", StyleBoxEmpty.new())
	t.set_icon("unchecked", "CheckBox", _tick_box(false))
	t.set_icon("checked", "CheckBox", _tick_box(true))
	var track := _box(Color(0.16, 0.13, 0.1), Color(EDGE, 0.25), 1)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", track)
	var fill := _box(Color(EDGE, 0.75), Color(0, 0, 0, 0), 0)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	t.set_icon("grabber", "HSlider", _dot(9, EDGE))
	t.set_icon("grabber_highlight", "HSlider", _dot(10, Color(1, 0.9, 0.65)))
	t.set_stylebox("panel", "PopupMenu", _box(BG, EDGE, 1))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", EDGE)
	t.set_stylebox("hover", "PopupMenu", _box(HOVER, Color(0, 0, 0, 0), 0))
	return t

## The framed panel every menu sits in.
static func panel() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := _box(BG, EDGE, 2)
	sb.set_content_margin_all(28)
	p.add_theme_stylebox_override("panel", sb)
	p.theme = theme()
	return p

static func label(text: String, size := 20, col := TEXT, title := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", TITLE_FONT if title else FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l

static func button(text: String, on_press: Callable, size := 24) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(320, 52)
	b.add_theme_font_size_override("font_size", size)
	b.pressed.connect(on_press)
	return b

## A thin brass rule with a diamond in the middle, as on a timetable heading.
static func rule(width := 320.0) -> Control:
	var r := _Rule.new()
	r.custom_minimum_size = Vector2(width, 14)
	return r

static func _box(bg: Color, edge: Color, w: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = edge
	sb.set_border_width_all(w)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb

static func _dot(r: int, col: Color) -> ImageTexture:
	var img := Image.create(r * 2 + 2, r * 2 + 2, false, Image.FORMAT_RGBA8)
	var c := Vector2(r + 1, r + 1)
	for y in img.get_height():
		for x in img.get_width():
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
			img.set_pixel(x, y, Color(col, clampf(r - d + 0.5, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)

# A brass-edged square, filled when on.
static func _tick_box(on: bool) -> ImageTexture:
	var n := 18
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.1, 0.085, 0.07, 0.9))
	for i in n:
		for e in [0, 1, n - 2, n - 1]:
			img.set_pixel(i, e, EDGE)
			img.set_pixel(e, i, EDGE)
	if on:
		img.fill_rect(Rect2i(5, 5, n - 10, n - 10), EDGE)
	return ImageTexture.create_from_image(img)

class _Rule extends Control:
	func _draw() -> void:
		var y := size.y * 0.5
		var mid := size.x * 0.5
		draw_line(Vector2(0, y), Vector2(mid - 10, y), Color(MenuStyle.EDGE, 0.7), 1.0)
		draw_line(Vector2(mid + 10, y), Vector2(size.x, y), Color(MenuStyle.EDGE, 0.7), 1.0)
		draw_colored_polygon(PackedVector2Array([Vector2(mid, y - 5), Vector2(mid + 5, y), Vector2(mid, y + 5), Vector2(mid - 5, y)]), MenuStyle.EDGE)
