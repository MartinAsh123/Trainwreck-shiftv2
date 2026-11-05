class_name XPWindow
extends Control
## A desktop window: glossy title bar with an icon, title and the minimise / maximise / close
## buttons, a beige body holding the app's content. Drag by the title bar; double-click it to
## maximise. Clicking anywhere brings it to the front.

signal closed(win: XPWindow)
signal minimized(win: XPWindow)
signal activated(win: XPWindow)

const TITLE_H := 28.0
const BORDER := 4.0

var title: String = "Window"
var icon_kind: String = "app"
var active := true
var content: Control
var maximized := false
var _restore := Rect2()
var _drag := false
var _drag_off := Vector2.ZERO
var _hot := -1                     # hovered title button 0 min, 1 max, 2 close
var _last_click := 0

func _init(win_title: String, body: Control, size_px: Vector2, icon: String = "app") -> void:
	title = win_title
	icon_kind = icon
	size = size_px
	custom_minimum_size = Vector2(220, 120)
	mouse_filter = Control.MOUSE_FILTER_STOP
	content = body
	content.position = Vector2(BORDER, TITLE_H)
	content.size = size_px - Vector2(BORDER * 2.0, TITLE_H + BORDER)
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.offset_left = BORDER
	content.offset_top = TITLE_H
	content.offset_right = -BORDER
	content.offset_bottom = -BORDER
	add_child(content)

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var cols: Array = XPStyle.TITLE_ACTIVE if active else XPStyle.TITLE_INACTIVE
	# Frame (same blue as the title bar), title bar, body.
	XPStyle.gradient_rect(self, r, [cols[1], cols[2], cols[2], cols[3]], [8, 8, 0, 0])
	XPStyle.gradient_rect(self, Rect2(0, 0, size.x, TITLE_H), cols, [8, 8, 0, 0])
	draw_rect(Rect2(BORDER - 1, TITLE_H - 1, size.x - BORDER * 2.0 + 2, size.y - TITLE_H - BORDER + 2), Color(0, 0, 0, 0.25), false)
	draw_rect(Rect2(BORDER, TITLE_H, size.x - BORDER * 2.0, size.y - TITLE_H - BORDER), XPStyle.FACE)
	XPIcons.draw(self, icon_kind, Rect2(6, 6, 16, 16))
	XPStyle.text(self, Vector2(27, 19), title, 13, XPStyle.TITLE_TEXT, XPStyle.bold(), true)
	for i in 3:
		var b := _button_rect(i)
		var bc: Array = (XPStyle.CLOSE as Array) if i == 2 else [Color("6f9cf6"), Color("2f6ef0"), Color("2a63e0"), Color("1b4fc4")]
		if _hot == i:
			bc = [bc[0].lightened(0.2), bc[1].lightened(0.15), bc[2].lightened(0.15), bc[3].lightened(0.1)]
		XPStyle.gradient_rect(self, b, bc, [3, 3, 3, 3])
		draw_rect(b, Color(1, 1, 1, 0.8), false, 1.0)
		var c := b.get_center()
		match i:
			0: draw_rect(Rect2(c.x - 4, c.y + 3, 8, 2.5), Color.WHITE)
			1:
				draw_rect(Rect2(c.x - 5, c.y - 5, 10, 10), Color.WHITE, false, 1.0)
				draw_rect(Rect2(c.x - 5, c.y - 5, 10, 2.5), Color.WHITE)
			2:
				draw_line(c + Vector2(-4, -4), c + Vector2(4, 4), Color.WHITE, 2.0)
				draw_line(c + Vector2(4, -4), c + Vector2(-4, 4), Color.WHITE, 2.0)

func _button_rect(i: int) -> Rect2:
	return Rect2(size.x - 6 - 23 * (3 - i), 4, 21, 21)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			activated.emit(self)
			for i in 3:
				if _button_rect(i).has_point(mb.position):
					accept_event()
					match i:
						0: minimized.emit(self)
						1: toggle_maximize()
						2: closed.emit(self)
					return
			if mb.position.y < TITLE_H:
				var now := Time.get_ticks_msec()
				if now - _last_click < 400:
					toggle_maximize()
				_last_click = now
				_drag = not maximized
				_drag_off = mb.position
			accept_event()
		else:
			_drag = false
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		var hot := -1
		for i in 3:
			if _button_rect(i).has_point(mm.position):
				hot = i
		if hot != _hot:
			_hot = hot
			queue_redraw()
		if _drag:
			var parent_size := get_parent_area_size()
			position = (position + mm.position - _drag_off).clamp(Vector2(-size.x + 80, 0), parent_size - Vector2(80, 60))

func toggle_maximize() -> void:
	if maximized:
		position = _restore.position
		size = _restore.size
	else:
		_restore = Rect2(position, size)
		position = Vector2.ZERO
		size = get_parent_area_size() - Vector2(0, XPDesktop.TASKBAR_H)
	maximized = not maximized
	queue_redraw()

func set_active(a: bool) -> void:
	active = a
	queue_redraw()
