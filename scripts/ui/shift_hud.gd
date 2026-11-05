class_name ShiftHUD
extends CanvasLayer
## The shift on screen: the toolbar of what Kevin carries (Inventory: four slots, the one in hand
## lit, its name over the bar), the train's clock with the time left in the shift, the money (the
## wallet and today's account), the ghost's timer once he knows of it (HauntDirector.ghost_timer()),
## and the open work orders (TaskBoard) with their deadlines. Hidden while his eye is held elsewhere
## (a terminal, a conversation) and over a big scare (HorrorDirector.hold).
## Cheap per frame: the slot styles are made once, a property is only set when its value changes
## (theme overrides re-layout the control), and the clock, money and work orders refresh at 10 Hz.

const FONT := preload("res://assets/fonts/Oswald.ttf")
const BG := Color(0.07, 0.06, 0.05, 0.72)
const EDGE := Color(0.89, 0.76, 0.49, 0.95)
const DIM := Color(0.62, 0.58, 0.5, 0.8)
const TEXT := Color(0.96, 0.93, 0.85)
const RED := Color(1.0, 0.42, 0.36)
const GREEN := Color(0.62, 0.92, 0.6)
const SLOT := 78.0
const REFRESH := 0.1                       # seconds between corner/work-order updates
## The time, the shift left, the ghost's timer and the work orders are on Kevin's wristwatch and his
## clipboard now (the user's call, 2026-11-04): the screen keeps only the toolbar and the money.
const ON_SCREEN_TIME := false
const ON_SCREEN_TASKS := false

var _root: Control
var _slots: Array = []                     # [{panel, icon, num, letter}]
var _hand: Label
var _clock: Label
var _shift: Label
var _money: Label
var _ghost: Label
var _tasks: VBoxContainer
var _icons := {}                           # item id -> Texture2D
var _making := {}
var _inv: Inventory
var _board: TaskBoard
var _eco: Economy
var _ts: Node
var _player: Node
var _t := 0.0
var _next := 0.0                           # _t of the next corner/work-order refresh
var _box_sel: StyleBoxFlat
var _box_dim: StyleBoxFlat
var _cols := {}                            # Label -> the font colour last set on it
var _rows: Array = []                      # the work orders shown, for the per-frame fade
var _route_end := -1.0                     # the last stop's time, in hours
var _route_last := ""

func _ready() -> void:
	layer = 4
	_ts = get_node_or_null("/root/TrainState")
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_box_sel = _box(EDGE, 3)
	_box_dim = _box(DIM, 1)
	_build_toolbar()
	_build_corner()
	_build_tasks()

# ————— building —————

func _label(size: int, col := TEXT) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _box(border: Color, width := 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(3)
	sb.set_content_margin_all(8)
	return sb

func _build_toolbar() -> void:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	var w := SLOT * Inventory.SLOTS + 8.0 * (Inventory.SLOTS - 1)
	bar.offset_left = -w * 0.5
	bar.offset_right = w * 0.5
	bar.offset_top = -SLOT - 22.0
	bar.offset_bottom = -22.0
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bar)
	for i in Inventory.SLOTS:
		var p := Panel.new()
		p.custom_minimum_size = Vector2(SLOT, SLOT)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.add_child(p)
		var icon := TextureRect.new()
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.offset_left = 6
		icon.offset_top = 6
		icon.offset_right = -6
		icon.offset_bottom = -6
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(icon)
		var letter := _label(26)
		letter.set_anchors_preset(Control.PRESET_FULL_RECT)
		letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		p.add_child(letter)
		var num := _label(14, DIM)
		num.position = Vector2(5, 1)
		num.text = str(i + 1)
		p.add_child(num)
		p.add_theme_stylebox_override("panel", _box_dim)
		_slots.append({"panel": p, "icon": icon, "num": num, "letter": letter, "sel": false})
	_hand = _label(18)
	_hand.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hand.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hand.offset_left = -260
	_hand.offset_right = 260
	_hand.offset_top = -SLOT - 54.0
	_hand.offset_bottom = -SLOT - 26.0
	_root.add_child(_hand)

func _build_corner() -> void:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _box(EDGE))
	pc.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	pc.offset_left = -250
	pc.offset_right = -18
	pc.offset_top = 18
	pc.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	pc.add_child(v)
	_clock = _label(34, EDGE)
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(_clock)
	_shift = _label(17)
	_shift.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(_shift)
	_money = _label(17)
	_money.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(_money)
	_ghost = _label(19, RED)
	_ghost.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ghost.visible = false
	v.add_child(_ghost)
	_clock.visible = ON_SCREEN_TIME
	_shift.visible = ON_SCREEN_TIME

func _build_tasks() -> void:
	_tasks = VBoxContainer.new()
	_tasks.add_theme_constant_override("separation", 2)
	_tasks.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_tasks.position = Vector2(20, 18)
	_tasks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tasks.visible = ON_SCREEN_TASKS
	_root.add_child(_tasks)

# ————— every frame —————

func _process(delta: float) -> void:
	_t += delta
	if _inv == null:
		_inv = Inventory.of(self)
	if _board == null:
		_board = TaskBoard.of(self)
	if _eco == null:
		_eco = Economy.of(self)
	if _player == null:
		_player = get_tree().root.find_child("Player", true, false)
	var hd := HorrorDirector.of(self)
	var focused := _player != null and _player.has_method("is_focused") and bool(_player.call("is_focused"))
	_root.visible = not focused and not (hd and hd.hold)        # (nothing on the screen over a big scare)
	if not _root.visible:
		return
	_update_toolbar()
	if _t >= _next:
		_next = _t + REFRESH
		_update_corner()
		_update_tasks()
	_fade_tasks()

# A theme colour override re-lays out the label, so only when the colour really changes.
func _set_col(l: Label, col: Color) -> void:
	if _cols.get(l) != col:
		_cols[l] = col
		l.add_theme_color_override("font_color", col)

func _update_toolbar() -> void:
	for i in _slots.size():
		var s: Dictionary = _slots[i]
		var it: HauntItem = null
		if _inv and i < _inv.slots.size() and _inv.slots[i] != null and is_instance_valid(_inv.slots[i]):
			it = _inv.slots[i]
		var sel := _inv != null and _inv.selected == i
		if s.sel != sel:
			s.sel = sel
			(s.panel as Panel).add_theme_stylebox_override("panel", _box_sel if sel else _box_dim)
		var tex: Texture2D = _icon(it) if it else null
		(s.icon as TextureRect).texture = tex
		(s.letter as Label).text = it.label.trim_prefix("the ").substr(0, 1).to_upper() if it and tex == null else ""
		(s.icon as TextureRect).modulate = Color.WHITE if sel else Color(1, 1, 1, 0.75)
	var held := _inv.in_hand() if _inv else null
	var what := held.label.trim_prefix("the ").trim_prefix("a ") if held else ""
	_hand.text = what.substr(0, 1).to_upper() + what.substr(1)

func _update_corner() -> void:
	var clock := float(_ts.get("clock")) if _ts else 19.0
	_clock.text = TaskBoard.hhmm(clock)
	if _route_end < 0.0:
		var last: Dictionary = RouteData.stops().back()
		var hm := str(last.time).split(".")
		_route_end = float(hm[0]) + float(hm[1]) / 60.0
		_route_last = str(last.name)
	var over := _ts and str(_ts.get("station")) == _route_last
	if over:
		_shift.text = "Shift over - turn in (your room)"
		_set_col(_shift, EDGE if fmod(_t, 1.2) < 0.8 else TEXT)
	else:
		var left := maxf((_route_end - clock) / TaskBoard.hours_per_second(self), 0.0)
		_shift.text = "Shift  %s left" % _mmss(left)
		_set_col(_shift, TEXT)
	if _eco:
		var tday := _eco.today()
		_money.text = "%s   today %s%s" % [Economy.money(_eco.balance()), "+" if tday >= 0 else "", Economy.money(tday)]
	var h := HauntDirector.of(self)
	var g: Dictionary = h.call("ghost_timer") if h and h.has_method("ghost_timer") else {}
	_ghost.visible = ON_SCREEN_TIME and not g.is_empty()
	if _ghost.visible:
		var left_g := float(g.get("left", 0.0))
		_ghost.text = "%s  %s" % [str(g.get("text", "Ghost")), _mmss(left_g)]
		_ghost.modulate.a = 1.0 if left_g > 60.0 or fmod(_t, 0.8) < 0.55 else 0.35

func _update_tasks() -> void:
	var rows: Array = []
	if _board:
		for t: TaskBoard.Task in _board.tasks:
			if t.state == "open" or (t.state == "missed" and t.check.is_valid()) or (t.state in ["done", "late", "missed"] and t.closed_t < 4.0):
				rows.append(t)
	while _tasks.get_child_count() < rows.size() + 1:
		_tasks.add_child(_label(16))
	var head := _tasks.get_child(0) as Label
	head.text = "WORK ORDERS" if not rows.is_empty() else ""
	_set_col(head, EDGE)
	_rows = rows
	for i in range(1, _tasks.get_child_count()):
		var l := _tasks.get_child(i) as Label
		if i - 1 >= rows.size():
			l.text = ""
			continue
		var t: TaskBoard.Task = rows[i - 1]
		var where := ("  ·  " + t.where) if t.where != "" else ""
		var col := TEXT
		var tail := ""
		match t.state:
			"open":
				if t.due >= 0.0:
					var left := _board.time_left(t)
					tail = "   by %s  ·  %s" % [TaskBoard.hhmm(t.due), _left_words(maxf(left, 0.0))]
					if left < 60.0:
						col = Color(1.0, 0.75, 0.4)
			"done":
				tail = "   done"
				col = GREEN
			"late":
				tail = "   done late"
				col = DIM
			"missed":
				tail = "   missed"
				col = RED
		l.text = "%s %s%s%s" % ["✓" if t.state in ["done", "late"] else "•", t.title, where, tail]
		_set_col(l, col)

# A closed work order fades out over its last second: every frame, so it stays smooth.
func _fade_tasks() -> void:
	for i in _rows.size():
		if i + 1 >= _tasks.get_child_count():
			break
		var t: TaskBoard.Task = _rows[i]
		var stays := t.state == "open" or (t.state == "missed" and t.check.is_valid())
		(_tasks.get_child(i + 1) as Label).modulate.a = 1.0 if stays else clampf(4.0 - t.closed_t, 0.0, 1.0)

static func _left_words(s: float) -> String:
	return "%d min left" % int(ceil(s / 60.0)) if s >= 60.0 else "%d s left" % int(ceil(s))

static func _mmss(s: float) -> String:
	var n := int(ceil(s))
	return "%d:%02d" % [n / 60, n % 60]

# ————— item pictures —————

## A picture of the item, made once per kind by photographing its model in a small world of its own.
func _icon(it: HauntItem) -> Texture2D:
	if _icons.has(it.item):
		return _icons[it.item]
	if not _making.has(it.item) and DisplayServer.get_name() != "headless":
		_making[it.item] = true
		_shoot.call_deferred(it)
	return null

func _shoot(it: HauntItem) -> void:
	var id := it.item
	var vp := SubViewport.new()
	vp.size = Vector2i(160, 160)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var stage := Node3D.new()
	vp.add_child(stage)
	var box := AABB()
	var first := true
	for c in it.get_children():
		if c is Area3D or not (c is Node3D):
			continue
		var d := (c as Node3D).duplicate() as Node3D
		d.transform = (c as Node3D).transform
		d.visible = true
		stage.add_child(d)
		for mi: Node in [d] + d.find_children("*", "VisualInstance3D", true, false):
			if mi is MeshInstance3D and (mi as MeshInstance3D).mesh:
				var b := (mi as MeshInstance3D).get_aabb()
				b = (stage.global_transform.affine_inverse() * (mi as MeshInstance3D).global_transform) * b
				box = b if first else box.merge(b)
				first = false
			elif mi is GPUParticles3D or mi is CPUParticles3D:
				(mi as Node3D).visible = false
	if first:
		box = AABB(Vector3(-0.1, 0, -0.1), Vector3(0.2, 0.2, 0.2))
	var cam := Camera3D.new()
	var mid := box.get_center()
	var r := maxf(box.size.length() * 0.5, 0.03)
	cam.fov = 30.0
	var dir := Vector3(0.55, 0.62, 0.9).normalized()
	cam.position = mid + dir * r / tan(deg_to_rad(cam.fov * 0.5)) * 1.05
	stage.add_child(cam)
	cam.look_at(mid, Vector3.UP)
	cam.current = true
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.6, 0)
	sun.light_energy = 1.4
	stage.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.8, 0.78, 0.72)
	env.environment.ambient_light_energy = 0.7
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	stage.add_child(env)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	if img and not img.is_empty():
		_icons[id] = ImageTexture.create_from_image(img)
