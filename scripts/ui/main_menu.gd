extends Control
## The front of the game: a night line running off to a red signal, the title in brass, and a
## timetable card with Start shift, Continue (the day and wallet from user://campaign.json),
## Settings and Quit. The journey loads on a thread behind a "Boarding…" line.

const JOURNEY := "res://scenes/game/journey.tscn"
const IDLE := preload("res://assets/audio/loco_idle.mp3")

var _card: VBoxContainer
var _settings: SettingsPanel
var _status: Label
var _loading := false
var _hum: AudioStreamPlayer

func _ready() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	theme = MenuStyle.theme()
	var back := _Backdrop.new()
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 150)
	margin.add_theme_constant_override("margin_top", 120)
	margin.add_theme_constant_override("margin_bottom", 90)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	margin.add_child(v)
	v.add_child(MenuStyle.label("NIGHT SERVICE  ·  19.10 — 21.15", 18, MenuStyle.DIM))
	v.add_child(MenuStyle.label("Trainwreck", 92, MenuStyle.EDGE, true))
	v.add_child(MenuStyle.label("Shift", 92, MenuStyle.TEXT, true))
	v.add_child(MenuStyle.rule(420))
	v.add_child(MenuStyle.label("The attendant's night on the last train. Mind the passengers.", 19, MenuStyle.DIM))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 36)
	v.add_child(gap)

	_card = VBoxContainer.new()
	_card.add_theme_constant_override("separation", 12)
	v.add_child(_card)
	var save := Economy._read_save()
	var start := MenuStyle.button("Start shift", _start.bind(false))
	_card.add_child(start)
	var cont := MenuStyle.button("Continue", _start.bind(true))
	if save.is_empty():
		cont.disabled = true
	else:
		cont.text = "Continue  ·  day %d  ·  %s" % [int(save.get("day", 1)), Economy.money(int(save.get("wallet", 0)))]
	_card.add_child(cont)
	_card.add_child(MenuStyle.button("Settings", _open_settings))
	_card.add_child(MenuStyle.button("Quit", func() -> void: get_tree().quit()))
	for b: Button in _card.get_children():
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size.x = 420
	_status = MenuStyle.label("", 20, MenuStyle.EDGE)
	v.add_child(_status)
	(cont if not cont.disabled else start).grab_focus.call_deferred()

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_settings = SettingsPanel.new()
	_settings.visible = false
	_settings.closed.connect(_close_settings)
	center.add_child(_settings)

	_hum = AudioStreamPlayer.new()
	var s := IDLE.duplicate() as AudioStreamMP3
	s.loop = true
	_hum.stream = s
	_hum.volume_db = -16.0
	_hum.bus = "Ambience" if AudioServer.get_bus_index("Ambience") >= 0 else "Master"
	add_child(_hum)
	_hum.play()

func _open_settings() -> void:
	_card.visible = false
	_settings.visible = true

func _close_settings() -> void:
	_settings.visible = false
	_card.visible = true
	(_card.get_child(2) as Button).grab_focus()

# A fresh day 1, or the saved day and wallet. Yesterday's manifest and names are cleared as for a
# new day (Economy.start_next_day).
func _start(resume: bool) -> void:
	if _loading:
		return
	_loading = true
	Economy.carry = Economy._read_save() if resume else {}
	TerminalData.passengers.clear()
	PassengerTalk._names_used.clear()
	for b: Button in _card.get_children():
		b.disabled = true
	_status.text = "Boarding…"
	ResourceLoader.load_threaded_request(JOURNEY)

func _process(_delta: float) -> void:
	if not _loading:
		return
	var p := []
	var st := ResourceLoader.load_threaded_get_status(JOURNEY, p)
	if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		_status.text = "Boarding…  %d%%" % int(float(p[0]) * 100.0)
	elif st == ResourceLoader.THREAD_LOAD_LOADED:
		_loading = false
		set_process(false)
		get_tree().change_scene_to_packed(ResourceLoader.load_threaded_get(JOURNEY))
	else:
		_loading = false
		_status.text = "The train could not be boarded (load error)."

# Night over open country: sky, a low moon, the line running to a red signal at the horizon, and
# the glow of a lamp swaying as if from the last carriage.
class _Backdrop extends Control:
	var _t := 0.0
	var _stars := PackedVector2Array()

	func _ready() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = 1931
		for i in 140:
			_stars.append(Vector2(rng.randf(), rng.randf() * 0.55))

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var hz := h * 0.62
		# Sky and ground.
		_vgrad(0.0, hz, Color(0.02, 0.025, 0.05), Color(0.09, 0.07, 0.07))
		_vgrad(hz, h, Color(0.035, 0.03, 0.025), Color(0.01, 0.008, 0.006))
		for i in _stars.size():
			var p := _stars[i] * Vector2(w, h)
			var a := 0.25 + 0.35 * (0.5 + 0.5 * sin(_t * (0.6 + float(i % 7) * 0.17) + float(i)))
			draw_circle(p, 0.6 + float(i % 3) * 0.35, Color(0.9, 0.88, 0.8, a))
		var moon := Vector2(w * 0.78, h * 0.2)
		for k in 6:
			draw_circle(moon, 40.0 + k * 22.0, Color(0.85, 0.8, 0.65, 0.025))
		draw_circle(moon, 34.0, Color(0.88, 0.84, 0.72, 0.85))
		draw_circle(moon + Vector2(12, -6), 30.0, Color(0.05, 0.05, 0.07, 0.55))
		# Tree line on the horizon.
		var trees := PackedVector2Array([Vector2(0, hz)])
		for i in 61:
			var x := w * float(i) / 60.0
			trees.append(Vector2(x, hz - 10.0 - 18.0 * absf(sin(float(i) * 1.7)) - 9.0 * absf(sin(float(i) * 0.43))))
		trees.append(Vector2(w, hz))
		draw_colored_polygon(trees, Color(0.015, 0.014, 0.016))
		# The line: two rails and the sleepers, closer together towards the vanishing point.
		var vp := Vector2(w * 0.66, hz)
		var run := fmod(_t * 0.35, 1.0)
		for i in 26:
			var k := pow((float(i) + run) / 26.0, 2.2)
			var y := lerpf(hz, h + 40.0, k)
			var half := lerpf(4.0, w * 0.5, k)
			var cx := lerpf(vp.x, w * 0.56, k)
			draw_line(Vector2(cx - half * 1.25, y), Vector2(cx + half * 1.25, y), Color(0.12, 0.09, 0.06, 0.5 + 0.5 * k), maxf(1.0, 14.0 * k))
		for side in [-1.0, 1.0]:
			var near := Vector2(w * 0.56 + side * w * 0.5, h + 40.0)
			draw_line(vp, near, Color(0.55, 0.5, 0.45, 0.55), 3.0)
			draw_line(vp, near, Color(0.85, 0.8, 0.7, 0.2), 1.0)
		# The red signal at the end of the line, and its halo.
		var sig := vp + Vector2(26, -34)
		draw_line(sig + Vector2(0, 6), Vector2(sig.x, hz), Color(0.03, 0.03, 0.03), 2.0)
		var pulse := 0.8 + 0.2 * sin(_t * 1.3)
		for k in 5:
			draw_circle(sig, 6.0 + k * 9.0, Color(0.9, 0.1, 0.05, 0.05 * pulse))
		draw_circle(sig, 3.5, Color(1.0, 0.3, 0.2, pulse))
		# A warm lamp glow at the bottom right, swaying like a lantern on the rear platform.
		var lamp := Vector2(w * 0.93 + sin(_t * 0.9) * 10.0, h * 0.86)
		for k in 8:
			draw_circle(lamp, 30.0 + k * 34.0, Color(0.95, 0.65, 0.3, 0.018))
		# Vignette.
		for k in 10:
			var m := float(k) * 22.0
			draw_rect(Rect2(Vector2(m, m), size - Vector2(m, m) * 2.0), Color(0, 0, 0, 0.06), false, 44.0)

	func _vgrad(y0: float, y1: float, top: Color, bottom: Color) -> void:
		var pts := PackedVector2Array([Vector2(0, y0), Vector2(size.x, y0), Vector2(size.x, y1), Vector2(0, y1)])
		draw_polygon(pts, PackedColorArray([top, top, bottom, bottom]))
