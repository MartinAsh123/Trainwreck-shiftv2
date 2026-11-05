class_name XPDesktop
extends Control
## The staff terminal's operating system, in the style of a 2001-era desktop. Lives in a
## SubViewport (1024 × 768) shown on the monitor; ComputerTerminal feeds it the mouse and keys.
## Screens: boot -> welcome (click the user to log on) -> desktop; Start > Log Off returns to the
## welcome screen, Turn Off shows the safe-to-switch-off screen (click to boot again).

signal sound(kind: String)           # "startup", "logon", "logoff", "shutdown", "click", "open", "close", "error", "notify"

const W := 1024
const H := 768
const TASKBAR_H := 32.0
const ICONS := [["manifest", "Passenger\nManifest"], ["timetable", "Timetable"], ["status", "Train Status"],
		["log", "Shift Log"], ["messages", "Dispatch\nMessages"], ["friend", "Private\nLine"], ["bin", "Recycle Bin"]]

enum Mode { OFF, BOOT, WELCOME, DESKTOP, BROKEN }

var mode: Mode = Mode.WELCOME
var cursor := Vector2(W * 0.5, H * 0.5)
var _wallpaper: ImageTexture
var _windows_layer: Control
var _start_open := false
var _selected_icon := -1
var _last_icon_click := 0
var _boot_t := 0.0
var _windows: Array[XPWindow] = []
var _theme: Theme
var _seen_messages := 0
var _overlay: Control
var live := false                    # set by the terminal while someone sits at it
var _idle_t := 0.0
var install_progress := 0.0          # 0: a dead machine; above that, a reinstall going

func _paint_overlay() -> void:
	if mode == Mode.DESKTOP:
		_draw_taskbar(_overlay)
		_draw_cursor(_overlay)

# While the start menu is open it takes every click (it is drawn over the windows).
func _overlay_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_desktop_click((event as InputEventMouseButton).position)
		_overlay.accept_event()

func _ready() -> void:
	size = Vector2(W, H)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_theme = XPStyle.theme()
	_wallpaper = _make_wallpaper()
	_windows_layer = Control.new()
	_windows_layer.name = "Windows"
	_windows_layer.size = Vector2(W, H - TASKBAR_H)
	_windows_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_windows_layer.theme = _theme
	_windows_layer.visible = false
	add_child(_windows_layer)
	# Above the windows: taskbar, start menu and the pointer.
	_overlay = Control.new()
	_overlay.name = "Overlay"
	_overlay.size = Vector2(W, H)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_paint_overlay)
	_overlay.gui_input.connect(_overlay_input)
	add_child(_overlay)
	TerminalData.ensure()
	_seen_messages = TerminalData.messages.size()
	var ts := get_node_or_null("/root/TrainState")
	if ts:
		ts.connect("arrived", _on_arrived)

## Dead until reinstalled: back to the welcome screen after.
func set_broken(on: bool) -> void:
	for w in _windows.duplicate():
		if is_instance_valid(w):
			w.queue_free()
	_windows.clear()
	_windows_layer.visible = false
	install_progress = 0.0
	mode = Mode.BROKEN if on else Mode.BOOT
	_boot_t = 0.0
	queue_redraw()

func _on_arrived(station: String) -> void:
	if TerminalData.messages.size() > 2 + 6:
		return
	var texts := {
		"DOBŘANY": "Drifts reported in the cutting beyond Zlatníky. Speed restriction 40 km/h may be imposed. Stand by.",
		"VRCHOVINA": "Water for the locomotive is ready at Sněžná. Please confirm the number of sleeper passengers alighting at the terminus.",
		"SNĚŽNÁ": "Heavy snow forecast after 20.30. Keep the vestibule doors shut; check the gangway plates for ice.",
		"VYSOKÉ POLE": "A passenger's luggage left at Královec has been sent on by the next train. Inform the passenger if found on board.",
		"STŘÍBRNÁ HORA": "Kamenný Most reports platform 2 cleared of snow. Arrival on time expected.",
	}
	if texts.has(station):
		TerminalData.add_message("Dispatch " + station.capitalize(), "Message at " + station.capitalize(), texts[station])

# ————— drawing —————

func _process(delta: float) -> void:
	if mode == Mode.BOOT:
		_boot_t += delta
		if _boot_t > 3.2:
			mode = Mode.WELCOME
			sound.emit("startup")
	if TerminalData.messages.size() != _seen_messages:
		_seen_messages = TerminalData.messages.size()
		if mode == Mode.DESKTOP:
			sound.emit("notify")
	# Redraw every frame only while someone is using the terminal (or it is booting); otherwise
	# once a second, enough for the clock.
	_idle_t += delta
	if live or mode == Mode.BOOT or _idle_t >= 1.0:
		_idle_t = 0.0
		queue_redraw()
		_overlay.queue_redraw()
	# The taskbar always takes clicks; the rest of the screen only while the menu is open.
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP if (mode == Mode.DESKTOP and (_start_open or cursor.y > H - TASKBAR_H)) else Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	match mode:
		Mode.OFF:
			draw_rect(Rect2(0, 0, W, H), Color.BLACK)
			XPStyle.text(self, Vector2(300, 380), "It is now safe to turn off your computer.", 22, Color("e8a33a"), XPStyle.bold())
		Mode.BOOT:
			draw_rect(Rect2(0, 0, W, H), Color.BLACK)
			_logo(Vector2(W * 0.5 - 120, 300), 1.0)
			# Progress: three blue blocks sliding through a rounded trough.
			var tr := Rect2(W * 0.5 - 90, 470, 180, 16)
			draw_rect(tr, Color("b2b2b2"), false, 1.5)
			var k := fmod(_boot_t * 1.4, 1.6) - 0.3
			for i in 3:
				var x := tr.position.x + 4 + (k * tr.size.x) + i * 11
				if x > tr.position.x + 2 and x < tr.end.x - 10:
					XPStyle.gradient_rect(self, Rect2(x, tr.position.y + 3, 8, 10), [Color("8ec5ff"), Color("2e6be0"), Color("2459c8"), Color("1a3f9a")], [2, 2, 2, 2])
			XPStyle.text(self, Vector2(20, H - 24), "Copyright © Grand Continental Railway", 12, Color("888"))
		Mode.WELCOME:
			_draw_welcome()
		Mode.DESKTOP:
			_draw_desktop()
		Mode.BROKEN:
			draw_rect(Rect2(0, 0, W, H), Color.BLACK)
			if install_progress <= 0.0:
				XPStyle.text(self, Vector2(60, 110), "Disk read error.", 40, Color("c8c8c8"))
				XPStyle.text(self, Vector2(60, 170), "Insert the reinstall disk.", 40, Color("c8c8c8"))
			else:
				XPStyle.text(self, Vector2(60, 110), "Reinstalling Railnet 2000...", 40, Color("c8c8c8"))
				draw_rect(Rect2(60, 160, 800, 34), Color("777"), false, 2.0)
				draw_rect(Rect2(64, 164, 792 * clampf(install_progress, 0.0, 1.0), 26), Color("2e6be0"))
			return
	if mode != Mode.DESKTOP:
		_draw_cursor(self)

func _logo(p: Vector2, s: float) -> void:
	_emblem(p + Vector2(26, 26) * s, 24.0 * s)
	XPStyle.text(self, p + Vector2(64 * s, 26 * s), "Railnet", int(40 * s), Color.WHITE, XPStyle.bold())
	XPStyle.text(self, p + Vector2(206 * s, 12 * s), "2000", int(16 * s), Color("ffb347"), XPStyle.bold())
	XPStyle.text(self, p + Vector2(66 * s, 48 * s), "Grand Continental Railway staff terminal", int(13 * s), Color("ddd"))

func _draw_welcome() -> void:
	draw_rect(Rect2(0, 0, W, H), Color("5a7edc"))
	XPStyle.gradient_rect(self, Rect2(0, 0, W, 80), [Color("00309c"), Color("00309c"), Color("00309c"), Color("00309c")])
	XPStyle.gradient_rect(self, Rect2(0, H - 80, W, 80), [Color("003ba8"), Color("00309c"), Color("00309c"), Color("00309c")])
	draw_line(Vector2(0, 80), Vector2(W, 80), Color("e8b35a"), 2.0)
	draw_line(Vector2(0, H - 80), Vector2(W, H - 80), Color("e8b35a"), 2.0)
	draw_line(Vector2(W * 0.5, 160), Vector2(W * 0.5, H - 160), Color(1, 1, 1, 0.45), 1.0)
	_logo(Vector2(170, 320), 1.0)
	XPStyle.text(self, Vector2(250, 440), "To begin, click your user name", 16, Color.WHITE)
	var tile := _user_tile_rect()
	var hot := tile.has_point(cursor)
	if hot:
		XPStyle.gradient_rect(self, tile.grow(4), [Color("2c55c8"), Color("1b3fa8"), Color("1b3fa8"), Color("1b3fa8")], [6, 6, 6, 6])
	XPIcons.draw(self, "user", Rect2(tile.position + Vector2(6, 6), Vector2(48, 48)))
	XPStyle.text(self, tile.position + Vector2(68, 28), "Conductor", 20, Color.WHITE, XPStyle.bold())
	XPStyle.text(self, tile.position + Vector2(68, 50), "Train 1930 · Car 2", 13, Color("cfe0ff"))
	var off := _turn_off_rect()
	XPStyle.gradient_rect(self, off, [Color("f08a5a"), Color("dd4a1a"), Color("d04010"), Color("b03008")], [4, 4, 4, 4])
	XPStyle.text(self, off.position + Vector2(34, 19), "Turn off computer", 14, Color.WHITE)
	XPStyle.text(self, Vector2(W - 330, H - 40), "After you log on, you can use the staff programs.", 12, Color("cfe0ff"))

# The railway's winged wheel: a spoked gold wheel with a wing either side.
func _emblem(c: Vector2, r: float, ci: CanvasItem = null) -> void:
	if ci == null:
		ci = self
	var gold := Color("f0c040")
	var dark := Color("8a6a10")
	for side: float in [-1.0, 1.0]:
		for f in 4:
			var y := -r * 0.45 + f * r * 0.28
			var pts := PackedVector2Array([c + Vector2(side * r * 0.7, y), c + Vector2(side * r * (1.9 - f * 0.22), y - r * 0.12),
					c + Vector2(side * r * (1.85 - f * 0.22), y + r * 0.16), c + Vector2(side * r * 0.7, y + r * 0.22)])
			ci.draw_colored_polygon(pts, gold.darkened(f * 0.08))
	ci.draw_circle(c, r, dark)
	ci.draw_circle(c, r * 0.86, gold)
	ci.draw_circle(c, r * 0.68, dark)
	for i in 8:
		var a := TAU * i / 8.0
		ci.draw_line(c, c + Vector2(cos(a), sin(a)) * r * 0.68, gold, maxf(1.0, r * 0.12))
	ci.draw_circle(c, r * 0.2, gold)

func _user_tile_rect() -> Rect2:
	return Rect2(W * 0.5 + 40, 300, 300, 60)

func _turn_off_rect() -> Rect2:
	return Rect2(30, H - 56, 170, 28)

func _draw_desktop() -> void:
	draw_texture(_wallpaper, Vector2.ZERO)
	for i in ICONS.size():
		var r := _icon_rect(i)
		if i == _selected_icon:
			draw_rect(Rect2(r.position + Vector2(18, 0), Vector2(36, 36)), Color(0.19, 0.42, 0.77, 0.45))
		XPIcons.draw(self, ICONS[i][0], Rect2(r.position + Vector2(20, 2), Vector2(32, 32)))
		var lines: PackedStringArray = str(ICONS[i][1]).split("\n")
		for li in lines.size():
			var tw := XPStyle.font().get_string_size(lines[li], HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			var tp := Vector2(r.position.x + 36 - tw * 0.5, r.position.y + 50 + li * 14)
			if i == _selected_icon:
				draw_rect(Rect2(tp - Vector2(2, 11), Vector2(tw + 4, 14)), XPStyle.SELECT)
			XPStyle.text(self, tp, lines[li], 12, Color.WHITE, null, true)

func _icon_rect(i: int) -> Rect2:
	return Rect2(14, 14 + i * 84, 72, 76)

func _draw_taskbar(ci: CanvasItem) -> void:
	var y := H - TASKBAR_H
	XPStyle.gradient_rect(ci, Rect2(0, y, W, TASKBAR_H), XPStyle.TASKBAR)
	ci.draw_line(Vector2(0, y), Vector2(W, y), Color("3a7bf0"), 1.0)
	var sr := _start_rect()
	XPStyle.gradient_rect(ci, sr, XPStyle.START if not _start_open else [Color("2e8b2e"), Color("2a7a2a"), Color("2a7a2a"), Color("246a24")], [0, 12, 12, 0])
	# Railway emblem + "start".
	_emblem(sr.position + Vector2(19, 16), 9.0, ci)
	XPStyle.text(ci, sr.position + Vector2(33, 22), "start", 18, Color.WHITE, XPStyle.bold(), true)
	# Task buttons.
	for i in _windows.size():
		var w := _windows[i]
		var r := _task_rect(i)
		var pressed := w.active and w.visible
		XPStyle.gradient_rect(ci, r, [Color("1e52b7"), Color("1d4fae"), Color("1a49a3"), Color("173f8f")] if pressed else [Color("5f9bf7"), Color("3c81f3"), Color("3a7cee"), Color("2f6ae0")], [3, 3, 3, 3])
		XPIcons.draw(ci, w.icon_kind, Rect2(r.position + Vector2(5, 5), Vector2(16, 16)))
		var t := w.title
		if t.length() > 20:
			t = t.substr(0, 19) + "…"
		XPStyle.text(ci, r.position + Vector2(26, 18), t, 12, Color.WHITE)
	# Tray with the clock.
	var tr := Rect2(W - 96, y, 96, TASKBAR_H)
	XPStyle.gradient_rect(ci, tr, XPStyle.TRAY)
	ci.draw_line(tr.position, tr.position + Vector2(0, TASKBAR_H), Color("1042af"), 1.0)
	XPStyle.text(ci, tr.position + Vector2(10, 20), "", 12, Color.WHITE)
	var unread := 0
	for m in TerminalData.messages:
		if not m.read:
			unread += 1
	if unread > 0:
		XPIcons.draw(ci, "messages", Rect2(tr.position + Vector2(8, 8), Vector2(16, 16)))
	XPStyle.text(ci, tr.position + Vector2(44, 21), TerminalData.clock_text().replace(".", ":"), 12, Color.WHITE)
	if _start_open:
		_draw_start_menu(ci)

func _start_rect() -> Rect2:
	return Rect2(0, H - TASKBAR_H, 104, TASKBAR_H)

func _task_rect(i: int) -> Rect2:
	return Rect2(112 + i * 164, H - TASKBAR_H + 4, 158, TASKBAR_H - 7)

func _menu_rect() -> Rect2:
	return Rect2(0, H - TASKBAR_H - 420, 300, 420)

func _menu_item_rect(i: int) -> Rect2:
	var m := _menu_rect()
	return Rect2(m.position.x + 6, m.position.y + 70 + i * 46, m.size.x - 12, 42)

func _draw_start_menu(ci: CanvasItem) -> void:
	var m := _menu_rect()
	ci.draw_rect(m, Color.WHITE)
	XPStyle.gradient_rect(ci, Rect2(m.position, Vector2(m.size.x, 62)), XPStyle.MENU_HEAD, [8, 8, 0, 0])
	XPIcons.draw(ci, "user", Rect2(m.position + Vector2(8, 8), Vector2(46, 46)))
	XPStyle.text(ci, m.position + Vector2(64, 38), "Conductor", 17, Color.WHITE, XPStyle.bold(), true)
	for i in 5:
		var r := _menu_item_rect(i)
		if r.has_point(cursor):
			ci.draw_rect(r, XPStyle.SELECT)
		var kind: String = ICONS[i][0]
		XPIcons.draw(ci, kind, Rect2(r.position + Vector2(4, 5), Vector2(32, 32)))
		XPStyle.text(ci, r.position + Vector2(44, 26), str(ICONS[i][1]).replace("\n", " "), 13, Color.WHITE if r.has_point(cursor) else XPStyle.TEXT, XPStyle.bold())
	var foot := Rect2(m.position.x, m.end.y - 46, m.size.x, 46)
	XPStyle.gradient_rect(ci, foot, XPStyle.MENU_HEAD)
	for i in 2:
		var b := _menu_foot_rect(i)
		XPStyle.gradient_rect(ci, Rect2(b.position, Vector2(22, 22)), [Color("f6c46a"), Color("e8a33a"), Color("e09a2a"), Color("c8801a")] if i == 0 else [Color("f08a5a"), Color("dd4a1a"), Color("d04010"), Color("b03008")], [4, 4, 4, 4])
		XPStyle.text(ci, b.position + Vector2(28, 16), "Log Off" if i == 0 else "Turn Off", 13, Color.WHITE)

func _menu_foot_rect(i: int) -> Rect2:
	var m := _menu_rect()
	return Rect2(m.position.x + 120 + i * 92, m.end.y - 34, 90, 24)

func _draw_cursor(ci: CanvasItem) -> void:
	var p := cursor
	var pts := PackedVector2Array([p, p + Vector2(0, 17), p + Vector2(4, 13), p + Vector2(7, 20), p + Vector2(10, 19), p + Vector2(7, 12), p + Vector2(12, 12)])
	ci.draw_colored_polygon(pts, Color.WHITE)
	pts.append(p)
	ci.draw_polyline(pts, Color.BLACK, 1.0)

# ————— input —————

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		cursor = (event as InputEventMouseMotion).position
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var p := (event as InputEventMouseButton).position
		cursor = p
		_click(p)

## Cursor tracking even over the windows (they consume their own events).
func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		cursor = (event as InputEventMouse).position

func _click(p: Vector2) -> void:
	match mode:
		Mode.OFF:
			mode = Mode.BOOT
			_boot_t = 0.0
		Mode.WELCOME:
			if _user_tile_rect().grow(4).has_point(p):
				mode = Mode.DESKTOP
				_windows_layer.visible = true
				sound.emit("logon")
			elif _turn_off_rect().has_point(p):
				_turn_off()
		Mode.DESKTOP:
			_desktop_click(p)

func _desktop_click(p: Vector2) -> void:
	if _start_open:
		_start_open = false
		for i in 5:
			if _menu_item_rect(i).has_point(p):
				open_app(ICONS[i][0])
				return
		if _menu_foot_rect(0).has_point(p):
			_log_off()
			return
		if _menu_foot_rect(1).has_point(p):
			_turn_off()
			return
		if _menu_rect().has_point(p):
			return
	if _start_rect().has_point(p):
		_start_open = true
		sound.emit("click")
		return
	for i in _windows.size():
		if _task_rect(i).has_point(p):
			var w := _windows[i]
			if w.visible and w.active:
				w.visible = false
				w.set_active(false)
			else:
				w.visible = true
				_activate(w)
			sound.emit("click")
			return
	_selected_icon = -1
	for i in ICONS.size():
		if _icon_rect(i).has_point(p):
			var now := Time.get_ticks_msec()
			if _selected_icon == i or now - _last_icon_click < 450:
				pass
			_selected_icon = i
			if now - _last_icon_click < 450 and ICONS[i][0] != "bin":
				open_app(ICONS[i][0])
			_last_icon_click = now
			return

func open_app(kind: String) -> void:
	for w in _windows:
		if w.get_meta("kind") == kind:
			w.visible = true
			_activate(w)
			return
	var spec: Array = XPApps.APPS[kind]
	var win := XPWindow.new(spec[0], XPApps.make(kind), spec[1], kind)
	win.set_meta("kind", kind)
	win.position = Vector2(140 + _windows.size() * 28, 40 + _windows.size() * 24)
	_windows_layer.add_child(win)
	_windows.append(win)
	win.closed.connect(_close_window)
	win.minimized.connect(func(w: XPWindow) -> void:
		w.visible = false
		w.set_active(false))
	win.activated.connect(_activate)
	_activate(win)
	sound.emit("open")

func _activate(win: XPWindow) -> void:
	for w in _windows:
		w.set_active(w == win)
	win.move_to_front()

func _close_window(win: XPWindow) -> void:
	_windows.erase(win)
	win.queue_free()
	sound.emit("close")

func _log_off() -> void:
	for w in _windows.duplicate():
		_close_window(w)
	_windows_layer.visible = false
	mode = Mode.WELCOME
	sound.emit("logoff")

func _turn_off() -> void:
	for w in _windows.duplicate():
		_close_window(w)
	_windows_layer.visible = false
	mode = Mode.OFF
	sound.emit("shutdown")

# ————— wallpaper —————

# Night-blue sky over snowy rolling hills with a line of pines and a lit train crossing a
# viaduct — the railway's own desktop picture.
static var _wall_cache: ImageTexture

func _make_wallpaper() -> ImageTexture:
	if _wall_cache:
		return _wall_cache
	var img := Image.create(W, H, false, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.004
	for y in H:
		var t := float(y) / H
		img.fill_rect(Rect2i(0, y, W, 1), Color("0b2a6b").lerp(Color("5f8fd8"), pow(t, 1.4)))
	# Hills: two layers, far bluish and near white.
	for layer in 2:
		var base := 470.0 if layer == 0 else 560.0
		var amp := 70.0 if layer == 0 else 90.0
		var col_top := Color("c9d8f2") if layer == 0 else Color("f4f8ff")
		var col_low := Color("8ea9d6") if layer == 0 else Color("c3d3ee")
		for x in W:
			var h := base - amp * (0.5 + 0.5 * noise.get_noise_1d(x * (1.0 + layer) + layer * 500.0)) - (40.0 if layer == 0 else 0.0) * sin(float(x) / W * PI)
			for y in range(int(h), H):
				img.set_pixel(x, y, col_top.lerp(col_low, clampf((y - h) / 220.0, 0.0, 1.0)))
	# Pines on the far ridge.
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 70:
		var x := rng.randi_range(0, W - 1)
		var top := 470.0 - 70.0 * (0.5 + 0.5 * noise.get_noise_1d(float(x))) - 40.0 * sin(float(x) / W * PI)
		var th := rng.randf_range(16.0, 34.0)
		for yy in int(th):
			var hw := int((float(yy) / th) * th * 0.32)
			for xx in range(-hw, hw + 1):
				var px := x + xx
				var py := int(top - th + yy + 6)
				if px >= 0 and px < W and py >= 0 and py < H:
					img.set_pixel(px, py, Color("1d3550"))
	# Stars.
	for i in 160:
		var sx := rng.randi_range(0, W - 1)
		var sy := rng.randi_range(0, 300)
		img.set_pixel(sx, sy, Color(1, 1, 1).lerp(Color("0b2a6b"), rng.randf() * 0.6))
	_wall_cache = ImageTexture.create_from_image(img)
	return _wall_cache
