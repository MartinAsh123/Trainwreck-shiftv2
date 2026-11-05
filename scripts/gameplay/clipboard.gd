class_name Clipboard
extends Node3D
## Kevin's clipboard: Tab brings it up in front of him (and puts it away). On it a sheet in his own
## hand: tonight's jobs from the TaskBoard with their times, a box ticked and the line struck through
## once each is done. When something strange turns up (a haunting he has noticed) he writes in:
##   "I need to investigate this strange incident soon"  at the time it was found + 5 minutes,
##   "* call Jim he is an expert when it comes to these strange things"  under it.
## The sheet is drawn into a SubViewport (a lined page, Caveat handwriting) and only redrawn when
## what is on it changes.

const HAND := preload("res://assets/fonts/Caveat.ttf")
const MODEL := preload("res://assets/viewmodels/clipboard.glb")
const INK := Color(0.12, 0.16, 0.42)
const PAGE := Vector2i(600, 800)
var _up := Transform3D(Basis.from_euler(Vector3(-0.3, 0.04, 0.02)), Vector3(0.0, -0.03, -0.37))
var _down := Transform3D(Basis.from_euler(Vector3(-1.1, 0.25, 0.1)), Vector3(0.08, -0.5, -0.3))
const NOTE := "I need to investigate this strange incident soon"
const JIM := "* call Jim he is an expert when it comes to these strange things"

var shown := false
var _k := 0.0                            # 0 put away .. 1 up in front of him
var _cam: Camera3D
var _player: Node
var _vp: SubViewport
var _sheet: _Sheet
var _sig := ""
var _poll := 0.0
var _notes: Array = []                   # [{due, done}] strange incidents written in
var _was_known := false
var _ts: Node

func _ready() -> void:
	add_to_group("clipboard")
	_ts = get_node_or_null("/root/TrainState")
	visible = false
	_attach.call_deferred()

func _attach() -> void:
	await get_tree().process_frame
	_player = get_tree().root.find_child("Player", true, false)
	_cam = _player.get_node_or_null("Head/Camera") as Camera3D if _player else null
	if _cam == null:
		return
	get_parent().remove_child(self)
	_cam.add_child(self)
	_build()
	transform = _down

static func of(n: Node) -> Clipboard:
	return n.get_tree().get_first_node_in_group("clipboard") as Clipboard

func toggle() -> void:
	shown = not shown
	if shown:
		var w := Wristwatch.of(self)
		if w:
			w.shown = false
		_refresh(true)

func _unhandled_input(e: InputEvent) -> void:
	var pressed: bool = e.is_action_pressed("fp_clipboard") if InputMap.has_action("fp_clipboard") \
			else (e is InputEventKey and e.pressed and not e.echo and (e as InputEventKey).physical_keycode == KEY_TAB)
	if pressed and _cam:
		toggle()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if _cam == null:
		return
	_track_haunting()
	var hd := HorrorDirector.of(self)
	var busy := (_player.has_method("is_focused") and bool(_player.call("is_focused"))) or (hd != null and hd.hold)
	if busy:
		shown = false
	_k = move_toward(_k, 1.0 if shown else 0.0, delta * 3.2)
	visible = _k > 0.0
	if visible:
		var e := smoothstep(0.0, 1.0, _k)
		transform = _down.interpolate_with(_up, e)
		_poll -= delta
		if _poll <= 0.0:
			_poll = 0.5
			_refresh(false)

# A haunting he has noticed goes on the sheet at the moment he notices it.
func _track_haunting() -> void:
	var h := get_tree().get_first_node_in_group("haunt")
	var known := h != null and bool(h.get("known"))
	if known and not _was_known:
		var clock := float(_ts.get("clock")) if _ts else 19.0
		_notes.append({"due": clock + 5.0 / 60.0, "done": false})
	elif _was_known and not known and not _notes.is_empty():
		_notes.back().done = true                       # (laid to rest, or gone: struck through)
	_was_known = known

# ————— the sheet —————

func _refresh(force: bool) -> void:
	var rows: Array = []
	var board := TaskBoard.of(self)
	if board:
		for t: TaskBoard.Task in board.tasks:
			if t.state == "void":
				continue
			var what := t.title + (" - " + t.where if t.where != "" else "")
			rows.append({"due": t.due, "time": TaskBoard.hhmm(t.due) if t.due >= 0.0 else "", "text": what,
					"done": t.state in ["done", "late"], "missed": t.state == "missed", "sub": ""})
	for n: Dictionary in _notes:
		rows.append({"due": n.due, "time": TaskBoard.hhmm(n.due), "text": NOTE, "done": n.done, "missed": false,
				"sub": JIM, "strange": true})
	rows.sort_custom(func(a, b): return (a.due if a.due >= 0.0 else 99.0) < (b.due if b.due >= 0.0 else 99.0))
	var sig := str(rows)
	if sig == _sig and not force:
		return
	_sig = sig
	_sheet.rows = rows
	_sheet.queue_redraw()
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE

func _build() -> void:
	_vp = SubViewport.new()
	_vp.size = PAGE
	_vp.transparent_bg = false
	_vp.disable_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_vp)
	_sheet = _Sheet.new()
	_sheet.size = Vector2(PAGE)
	_vp.add_child(_sheet)
	# The board, its clip, the sheets under the top one and a pencil (assets/viewmodels/clipboard.glb).
	var model := MODEL.instantiate() as Node3D
	add_child(model)
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var sm := mi.get_active_material(0)
		if sm and sm.resource_name == "hardboard":
			mi.material_override = _hardboard()
		elif sm and sm.resource_name == "clip_steel":
			var st := StandardMaterial3D.new()          # (worn nickel plate: grey, not a white glare)
			st.albedo_color = Color(0.42, 0.42, 0.44)
			st.metallic = 0.8
			st.roughness = 0.42
			mi.material_override = st
	# The top sheet: the page, under the jaw of the clip.
	var paper := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.21, 0.29)
	paper.mesh = q
	var m := StandardMaterial3D.new()
	m.albedo_texture = _vp.get_texture()
	m.roughness = 0.92
	m.emission_enabled = true                          # (readable in a dim car)
	m.emission_texture = _vp.get_texture()
	m.emission_energy_multiplier = 0.1
	paper.material_override = m
	paper.position = Vector3(0, -0.007, 0.0034)
	paper.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(paper)

# Brown hardboard: a fine fibrous mottle and a faint grain, satin rather than shiny.
func _hardboard() -> StandardMaterial3D:
	var n := FastNoiseLite.new()
	n.frequency = 0.06
	n.fractal_octaves = 4
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.noise = n
	var g := Gradient.new()
	g.set_color(0, Color(0.24, 0.14, 0.07))
	g.set_color(1, Color(0.37, 0.23, 0.12))
	tex.color_ramp = g
	var nn := FastNoiseLite.new()
	nn.frequency = 0.15
	var nt := NoiseTexture2D.new()
	nt.width = 512
	nt.height = 512
	nt.seamless = true
	nt.as_normal_map = true
	nt.bump_strength = 1.6
	nt.noise = nn
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.normal_enabled = true
	m.normal_texture = nt
	m.normal_scale = 0.35
	m.roughness = 0.62
	m.uv1_scale = Vector3(3, 3, 3)
	return m

## The page itself: ruled paper, and the rows written on it in a slightly uneven hand.
class _Sheet:
	extends Control
	var rows: Array = []

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.94, 0.92, 0.85))
		# Grain, a little shading at the edges, an old coffee ring at the foot of the page.
		var grain := RandomNumberGenerator.new()
		grain.seed = 3
		for i in 2600:
			draw_rect(Rect2(Vector2(grain.randf() * size.x, grain.randf() * size.y), Vector2(1.5, 1.5)), Color(0.35, 0.3, 0.2, grain.randf_range(0.02, 0.07)))
		for e in 10:
			var a := 0.022 * (1.0 - e / 10.0)
			draw_rect(Rect2(Vector2(e * 3, e * 3), size - Vector2(e * 6, e * 6)), Color(0.45, 0.38, 0.25, a), false, 3.0)
		var ring_at := Vector2(size.x * 0.74, size.y * 0.86)
		for k in 3:
			draw_arc(ring_at, 58.0 - k * 2.5, 0.4 + k * 0.3, TAU - 0.9 + k * 0.2, 48, Color(0.5, 0.33, 0.15, 0.09 - k * 0.02), 5.0 - k, true)
		var rule := 46.0
		var top := 130.0
		var size_px := 34
		var need := 0
		for r: Dictionary in rows:
			need += _lines_for(r, size_px)
		if need > int((size.y - top) / rule):
			size_px = 28
			rule = 38.0
		var y := top
		while y < size.y - 10.0:
			draw_line(Vector2(0, y), Vector2(size.x, y), Color(0.55, 0.68, 0.85, 0.55), 1.5)
			y += rule
		draw_line(Vector2(78, 0), Vector2(78, size.y), Color(0.85, 0.35, 0.35, 0.6), 1.5)
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		_write("Tonight's jobs", Vector2(92, 82), 52, rng, INK)
		var ul := PackedVector2Array()
		for i in 9:
			ul.append(Vector2(94 + i * 33, 92 + rng.randf_range(-1.5, 1.5)))
		draw_polyline(ul, Color(INK, 0.8), 2.0, true)
		var line := 0
		for r: Dictionary in rows:
			var base := top + rule * line - 7.0
			if base > size.y - 10.0:
				break
			var ink: Color = Color(0.55, 0.12, 0.1) if r.get("strange", false) else INK
			# The box, ticked when done.
			_box_mark(Vector2(26, base - 24), rng, r.done)
			var time_w := 0.0
			if r.time != "":
				_write(r.time, Vector2(90, base), size_px, rng, ink)
				time_w = HAND.get_string_size(r.time + "  ", HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
			var x0 := 90.0 + time_w
			var wrapped := _wrap(r.text, size.x - x0 - 18.0, size_px)
			for i in wrapped.size():
				var at := Vector2(x0 if i == 0 else 104.0, top + rule * line - 7.0)
				_write(wrapped[i], at, size_px, rng, ink)
				if r.done:
					_strike(at, HAND.get_string_size(wrapped[i], HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x, rng)
				line += 1
			if r.missed:
				_write("missed", Vector2(size.x - 120, top + rule * (line - 1) - 7.0), size_px - 6, rng, Color(0.7, 0.1, 0.08))
			if r.get("sub", "") != "":
				for s in _wrap(r.sub, size.x - 130.0, size_px - 4):
					_write(s, Vector2(118, top + rule * line - 7.0), size_px - 4, rng, ink)
					line += 1

	func _lines_for(r: Dictionary, px: int) -> int:
		var n := _wrap(r.text, size.x - 200.0, px).size()
		if r.get("sub", "") != "":
			n += _wrap(r.sub, size.x - 130.0, px - 4).size()
		return n

	func _wrap(text: String, width: float, px: int) -> Array:
		var out: Array = []
		var cur := ""
		for w in text.split(" "):
			var t := w if cur == "" else cur + " " + w
			if HAND.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > width and cur != "":
				out.append(cur)
				cur = w
			else:
				cur = t
		if cur != "":
			out.append(cur)
		return out

	# A line of handwriting: a hair off the rule and off straight, never twice the same.
	func _write(text: String, at: Vector2, px: int, rng: RandomNumberGenerator, col: Color) -> void:
		var ang := rng.randf_range(-0.012, 0.012)
		draw_set_transform(at + Vector2(rng.randf_range(-2, 2), rng.randf_range(-2, 1.5)), ang)
		draw_string(HAND, Vector2.ZERO, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)
		draw_set_transform(Vector2.ZERO)

	func _strike(at: Vector2, w: float, rng: RandomNumberGenerator) -> void:
		var pts := PackedVector2Array()
		var n := 8
		for i in n + 1:
			pts.append(at + Vector2(w * i / n, -11.0 + rng.randf_range(-2.0, 2.0)))
		draw_polyline(pts, Color(INK, 0.85), 2.2, true)

	func _box_mark(at: Vector2, rng: RandomNumberGenerator, ticked: bool) -> void:
		var s := 24.0
		var j := func() -> Vector2: return Vector2(rng.randf_range(-1.5, 1.5), rng.randf_range(-1.5, 1.5))
		var p := PackedVector2Array([at + j.call(), at + Vector2(s, 0) + j.call(), at + Vector2(s, s) + j.call(),
				at + Vector2(0, s) + j.call(), at + j.call()])
		draw_polyline(p, Color(INK, 0.9), 2.0, true)
		if ticked:
			draw_polyline(PackedVector2Array([at + Vector2(4, 12), at + Vector2(11, 21), at + Vector2(28, -6)]), INK, 3.0, true)
