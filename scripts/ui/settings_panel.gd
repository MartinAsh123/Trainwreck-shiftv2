class_name SettingsPanel
extends PanelContainer
## The settings page, shared by the main menu and the pause menu: sound, controls, comfort and
## accessibility, display. Every control writes straight into the Settings autoload, so a change is
## live (FOV, volume, subtitles) while the game sits paused behind it. "Back" emits `closed`.

signal closed

var _sync := {}                    # setting key -> Callable(value) that shows it without re-sending

func _init() -> void:
	var p := MenuStyle.panel()
	add_theme_stylebox_override("panel", p.get_theme_stylebox("panel"))
	p.free()
	theme = MenuStyle.theme()
	process_mode = Node.PROCESS_MODE_ALWAYS
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	add_child(v)
	v.add_child(MenuStyle.label("SETTINGS", 34, MenuStyle.EDGE, true))
	v.add_child(MenuStyle.rule(760))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 48)
	v.add_child(cols)
	var left := _column(cols)
	var right := _column(cols)
	var s := _settings()

	_head(left, "Sound")
	_slider(left, "Master", "master_volume", 0.0, 1.0, 0.05, "%d%%", 100.0)
	_slider(left, "Music", "music_volume", 0.0, 1.0, 0.05, "%d%%", 100.0)
	_slider(left, "Effects", "sfx_volume", 0.0, 1.0, 0.05, "%d%%", 100.0)
	_slider(left, "Ambience", "ambience_volume", 0.0, 1.0, 0.05, "%d%%", 100.0)
	_slider(left, "Voices", "voice_volume", 0.0, 1.0, 0.05, "%d%%", 100.0)
	_slider(left, "Interface", "ui_volume", 0.0, 1.0, 0.05, "%d%%", 100.0)
	_head(left, "Controls")
	_slider(left, "Mouse sensitivity", "mouse_sensitivity", 0.2, 3.0, 0.05, "%.2f×")
	_check(left, "Invert mouse Y", "invert_y")

	_head(right, "Comfort and accessibility")
	_slider(right, "Field of view", "fov", 70.0, 100.0, 1.0, "%d°")
	_check(right, "Head bob", "head_bob")
	_slider(right, "Camera shake", "camera_shake", 0.0, 1.0, 0.05, "%d%%", 100.0)
	_check(right, "Reduced flashes", "reduced_flashes")
	_options(right, "Jumpscares", "jumpscare", ["Full", "Soft", "Off"], [0, 1, 2])
	var sizes: Array = s.SUBTITLE_SIZES.keys() if s else []
	_options(right, "Subtitle size", "subtitle_size", sizes, sizes.map(func(k: String) -> int: return s.SUBTITLE_SIZES[k]))
	_head(right, "Display")
	var res: Array = s.RESOLUTIONS if s else []
	_options(right, "Resolution", "resolution", res.map(func(r: Vector2i) -> String: return "%d × %d" % [r.x, r.y]), res)
	_check(right, "Fullscreen", "fullscreen")
	_check(right, "Vertical sync", "vsync")

	v.add_child(MenuStyle.rule(760))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(row)
	var back := MenuStyle.button("Back", func() -> void: closed.emit(), 22)
	back.custom_minimum_size = Vector2(180, 46)
	row.add_child(back)
	if s:
		s.changed.connect(_on_changed)

func _on_changed(key: String) -> void:
	if _sync.has(key):
		_sync[key].call(_settings().get(key))

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		closed.emit()

func _settings() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("Settings") if Engine.get_main_loop() else null

func _column(parent: Control) -> GridContainer:
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 18)
	g.add_theme_constant_override("v_separation", 8)
	g.custom_minimum_size = Vector2(360, 0)
	parent.add_child(g)
	return g

func _head(g: GridContainer, text: String) -> void:
	var l := MenuStyle.label(text.to_upper(), 17, MenuStyle.EDGE)
	l.custom_minimum_size = Vector2(0, 34)
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	g.add_child(l)
	g.add_child(Control.new())

func _name(g: GridContainer, text: String) -> void:
	var l := MenuStyle.label(text, 18)
	l.custom_minimum_size = Vector2(170, 0)
	g.add_child(l)

func _slider(g: GridContainer, text: String, key: String, lo: float, hi: float, step: float, fmt: String, shown := 1.0) -> void:
	_name(g, text)
	var s := _settings()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	g.add_child(row)
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = step
	sl.custom_minimum_size = Vector2(170, 24)
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl.value = float(s.get(key)) if s else lo
	row.add_child(sl)
	var val := MenuStyle.label("", 16, MenuStyle.DIM)
	val.custom_minimum_size = Vector2(52, 0)
	row.add_child(val)
	var show := func(x: float) -> void: val.text = fmt % (roundi(x * shown) if fmt.contains("%d") else x)
	show.call(sl.value)
	_sync[key] = func(x: Variant) -> void:
		sl.set_value_no_signal(float(x))
		show.call(float(x))
	sl.value_changed.connect(func(x: float) -> void:
		show.call(x)
		if s:
			s.set_value(key, x))

func _check(g: GridContainer, text: String, key: String) -> void:
	_name(g, text)
	var s := _settings()
	var c := CheckBox.new()
	c.button_pressed = bool(s.get(key)) if s else false
	c.text = "On" if c.button_pressed else "Off"
	c.add_theme_font_size_override("font_size", 18)
	_sync[key] = func(x: Variant) -> void:
		c.set_pressed_no_signal(bool(x))
		c.text = "On" if x else "Off"
	c.toggled.connect(func(on: bool) -> void:
		c.text = "On" if on else "Off"
		if s:
			s.set_value(key, on))
	g.add_child(c)

func _options(g: GridContainer, text: String, key: String, names: Array, values: Array) -> void:
	_name(g, text)
	var s := _settings()
	var o := OptionButton.new()
	o.add_theme_font_size_override("font_size", 18)
	o.custom_minimum_size = Vector2(170, 0)
	for n: String in names:
		o.add_item(n)
	var cur: Variant = s.get(key) if s else null
	o.select(maxi(values.find(cur), 0))
	_sync[key] = func(x: Variant) -> void: o.select(maxi(values.find(x), 0))
	o.item_selected.connect(func(i: int) -> void:
		if s:
			s.set_value(key, values[i]))
	g.add_child(o)
