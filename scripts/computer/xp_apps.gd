class_name XPApps
extends RefCounted
## The terminal's programs. Each make_* returns the body Control for an XPWindow.
##   Passenger Manifest — search by name, place or ticket; filter by car; mark tickets checked
##   Timetable          — every station on the line, the train's progress and the next stop
##   Train Status       — live speed, position, doors, weather and the time
##   Shift Log          — a notepad for the conductor's log (shared by all terminals)
##   Dispatch Messages  — telegrams from the line; new ones arrive at stations
##   Private Line       — Kevin's line to his friend Jim: send him a passenger's name

const APPS := {
	"manifest": ["Passenger Manifest", Vector2(700, 470)],
	"timetable": ["Timetable", Vector2(560, 430)],
	"status": ["Train Status", Vector2(400, 360)],
	"log": ["Shift Log - Notepad", Vector2(560, 420)],
	"messages": ["Dispatch Messages", Vector2(600, 400)],
	"friend": ["Private Line - Jim", Vector2(600, 430)],
}

static func make(kind: String) -> Control:
	TerminalData.ensure()
	match kind:
		"manifest": return _manifest()
		"timetable": return _timetable()
		"status": return _status()
		"log": return _log()
		"messages": return _messages()
		"friend": return _friend()
	return Control.new()

static func _margin(c: Control, m: int = 8) -> MarginContainer:
	var mc := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		mc.add_theme_constant_override("margin_" + side, m)
	mc.add_child(c)
	return mc

# ————— manifest —————

static func _manifest() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	var bar := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = "Find:"
	bar.add_child(lbl)
	var q := LineEdit.new()
	q.placeholder_text = "name, seat, berth or ticket no."
	q.custom_minimum_size.x = 260
	bar.add_child(q)
	var car := OptionButton.new()
	for it in ["All cars", "CAR 1", "CAR 2", "CAR 3"]:
		car.add_item(it)
	bar.add_child(car)
	var unchecked := CheckBox.new()
	unchecked.text = "Unchecked only"
	bar.add_child(unchecked)
	v.add_child(bar)
	var tree := Tree.new()
	tree.columns = 6
	tree.column_titles_visible = true
	tree.hide_root = true
	tree.select_mode = Tree.SELECT_ROW
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var heads := ["Passenger", "Car", "Place", "Ticket", "From - To", "Checked"]
	var widths := [170, 60, 70, 110, 190, 60]
	for i in 6:
		tree.set_column_title(i, heads[i])
		tree.set_column_custom_minimum_width(i, widths[i])
		tree.set_column_expand(i, i == 4)
	v.add_child(tree)
	var detail := Label.new()
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.custom_minimum_size.y = 40
	detail.text = "Select a passenger."
	v.add_child(detail)
	var mark := Button.new()
	mark.text = "Mark ticket checked"
	mark.disabled = true
	var count := Label.new()
	var foot := HBoxContainer.new()
	foot.add_child(mark)
	foot.add_child(count)
	v.add_child(foot)
	var refresh := func() -> void:
		tree.clear()
		var root := tree.create_item()
		var needle := q.text.strip_edges().to_lower()
		var shown := 0
		var done := 0
		for i in TerminalData.passengers.size():
			var p: Dictionary = TerminalData.passengers[i]
			if car.selected > 0 and p.car != car.get_item_text(car.selected):
				continue
			if unchecked.button_pressed and p.checked:
				continue
			var hay := ("%s %s %s %s" % [p.name, p.place, p.ticket, p.car]).to_lower()
			if needle != "" and not hay.contains(needle):
				continue
			var it := root.create_child()
			it.set_text(0, p.name)
			it.set_text(1, p.car.replace("CAR ", ""))
			it.set_text(2, p.place)
			it.set_text(3, p.ticket)
			it.set_text(4, "%s - %s" % [p.from, p.to])
			it.set_text(5, str(p.get("status", "Yes" if p.checked else "-")))
			it.set_metadata(0, i)
			shown += 1
			if p.checked:
				done += 1
		var total_checked := 0
		for p in TerminalData.passengers:
			if p.checked:
				total_checked += 1
		count.text = "   %d shown  ·  %d of %d tickets checked" % [shown, total_checked, TerminalData.passengers.size()]
	q.text_changed.connect(func(_t): refresh.call())
	car.item_selected.connect(func(_i): refresh.call())
	unchecked.toggled.connect(func(_b): refresh.call())
	tree.item_selected.connect(func() -> void:
		var i: int = tree.get_selected().get_metadata(0)
		var p: Dictionary = TerminalData.passengers[i]
		detail.text = "%s  —  %s, %s (%s).  Ticket %s, %s to %s.%s" % [p.name, p.car, p.place, p.class, p.ticket,
				p.from, p.to, ("  Note: " + p.note) if p.note != "" else ""]
		mark.disabled = p.checked)
	mark.pressed.connect(func() -> void:
		var sel := tree.get_selected()
		if sel == null:
			return
		var i: int = sel.get_metadata(0)
		TerminalData.passengers[i].checked = true
		mark.disabled = true
		refresh.call())
	refresh.call()
	return _margin(v)

# ————— timetable —————

static func _timetable() -> Control:
	var v := VBoxContainer.new()
	var head := Label.new()
	head.text = "The Continental Express  ·  train 1930  ·  Královec - Kamenný Most"
	v.add_child(head)
	var tree := Tree.new()
	tree.columns = 5
	tree.column_titles_visible = true
	tree.hide_root = true
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var heads := ["Station", "Km", "Booked", "Calls", "Status"]
	for i in 5:
		tree.set_column_title(i, heads[i])
		tree.set_column_expand(i, i == 0 or i == 4)
	v.add_child(tree)
	var root := tree.create_item()
	var items: Array[TreeItem] = []
	for st in RouteData.STATIONS:
		var it := root.create_child()
		it.set_text(0, st.name)
		it.set_text(1, "%.1f" % (st.s / 1000.0))
		it.set_text(2, st.time if st.stop else "pass")
		it.set_text(3, "Yes" if st.stop else "-")
		items.append(it)
	var foot := Label.new()
	v.add_child(foot)
	var timer := Timer.new()
	timer.wait_time = 0.5
	timer.autostart = true
	v.add_child(timer)
	var update := func() -> void:
		var ts := v.get_node_or_null("/root/TrainState")
		if ts == null:
			return
		var d: float = float(ts.get("distance")) + 29.0          # the train's middle
		for i in items.size():
			var st: Dictionary = RouteData.STATIONS[i]
			var status := ""
			if absf(d - st.s) < 60.0 and float(ts.get("speed")) < 0.3:
				status = "STANDING HERE"
			elif d > st.s + 60.0:
				status = "departed" if st.stop else "passed"
			elif st.name == ts.get("next_stop"):
				status = "NEXT STOP"
			items[i].set_text(4, status)
			var col := Color("1a5e1a") if status == "STANDING HERE" or status == "NEXT STOP" else (Color("777") if status in ["departed", "passed"] else XPStyle.TEXT)
			for c in 5:
				items[i].set_custom_color(c, col)
		var left: float = ts.get("to_next_stop")
		var v_ms: float = ts.get("speed")
		var eta := "-" if v_ms < 1.0 else "%d min" % int(ceil(left / v_ms / 60.0 * 3.0))
		foot.text = "Next stop: %s  ·  %.1f km  ·  about %s" % [ts.get("next_stop"), left / 1000.0, eta] if str(ts.get("next_stop")) != "" else "Terminus."
	timer.timeout.connect(update)
	update.call_deferred()
	return _margin(v)

# ————— status —————

static func _status() -> Control:
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 18)
	g.add_theme_constant_override("v_separation", 7)
	var rows := ["Time", "Speed", "Line position", "Running", "Next stop", "Exterior doors", "Weather", "Outside air", "Heating"]
	var vals := {}
	for r in rows:
		var a := Label.new()
		a.text = r + ":"
		a.add_theme_font_override("font", XPStyle.bold())
		g.add_child(a)
		var b := Label.new()
		g.add_child(b)
		vals[r] = b
	var timer := Timer.new()
	timer.wait_time = 0.25
	timer.autostart = true
	g.add_child(timer)
	var update := func() -> void:
		var ts := g.get_node_or_null("/root/TrainState")
		if ts == null:
			return
		vals["Time"].text = TerminalData.clock_text()
		vals["Speed"].text = "%d km/h" % int(round(float(ts.get("speed")) * 3.6))
		vals["Line position"].text = "km %.2f" % ((float(ts.get("distance")) + 29.0) / 1000.0)
		var ph: String = ts.get("phase")
		vals["Running"].text = {"stopped": "Standing at %s" % ts.get("station"), "departing": "Departing - doors closing",
				"running": "Running", "braking": "Braking for %s" % ts.get("next_stop")}.get(ph, ph)
		vals["Next stop"].text = str(ts.get("next_stop")) if str(ts.get("next_stop")) != "" else "-"
		var open := 0
		var total := 0
		for d in g.get_tree().get_nodes_in_group("train_door"):
			if bool(d.get("lock_while_moving")):
				total += 1
				if d.call("is_open"):
					open += 1
		vals["Exterior doors"].text = ("All %d closed and locked" % total) if open == 0 else ("%d of %d OPEN" % [open, total])
		vals["Exterior doors"].add_theme_color_override("font_color", Color("1a5e1a") if open == 0 else Color("b01010"))
		var w := g.get_tree().get_first_node_in_group("weather")
		if w:
			vals["Weather"].text = str(w.get("state")).replace("_", " ").capitalize() + ("  ·  wind %d km/h" % int(Vector3(w.get("wind")).length() * 3.6))
			vals["Outside air"].text = "%d °C" % int(-9.0 - float(w.get("wind_strength")) * 8.0 - (float(ts.get("clock")) - 19.0) * 1.5)
		vals["Heating"].text = "On, all cars  ·  21 °C"
	timer.timeout.connect(update)
	update.call_deferred()
	return _margin(g, 14)

# ————— shift log —————

static func _log() -> Control:
	var v := VBoxContainer.new()
	var bar := HBoxContainer.new()
	var stamp := Button.new()
	stamp.text = "Insert time"
	bar.add_child(stamp)
	var save := Button.new()
	save.text = "Save"
	bar.add_child(save)
	var saved := Label.new()
	bar.add_child(saved)
	v.add_child(bar)
	var te := TextEdit.new()
	te.text = TerminalData.log_text
	te.size_flags_vertical = Control.SIZE_EXPAND_FILL
	te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	te.add_theme_font_size_override("font_size", 14)
	v.add_child(te)
	stamp.pressed.connect(func() -> void:
		te.insert_text_at_caret("\n%s  " % TerminalData.clock_text())
		te.grab_focus())
	save.pressed.connect(func() -> void:
		TerminalData.log_text = te.text
		saved.text = "  Saved %s" % TerminalData.clock_text())
	te.text_changed.connect(func() -> void:
		TerminalData.log_text = te.text
		saved.text = "")
	te.ready.connect(func(): te.grab_focus.call_deferred())
	return _margin(v, 4)

# ————— messages —————

static func _messages() -> Control:
	var h := HSplitContainer.new()
	var list := ItemList.new()
	list.custom_minimum_size.x = 210
	h.add_child(list)
	var body := Label.new()
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.WHITE
	sb.border_color = Color("7f9db9")
	sb.set_border_width_all(1)
	sb.content_margin_left = 10
	sb.content_margin_top = 8
	sb.content_margin_right = 10
	panel.add_theme_stylebox_override("panel", sb)
	panel.add_child(body)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(panel)
	var fill := func() -> void:
		var sel := list.get_selected_items()
		list.clear()
		for m in TerminalData.messages:
			list.add_item(("● " if not m.read else "   ") + "%s  %s" % [m.time, m.subject])
		if not sel.is_empty() and sel[0] < list.item_count:
			list.select(sel[0])
	list.item_selected.connect(func(i: int) -> void:
		var m: Dictionary = TerminalData.messages[i]
		m.read = true
		body.text = "From: %s\nTime: %s\nSubject: %s\n\n%s" % [m.from, m.time, m.subject, m.body]
		list.set_item_text(i, "   %s  %s" % [m.time, m.subject]))
	var timer := Timer.new()
	timer.wait_time = 2.0
	timer.autostart = true
	h.add_child(timer)
	var known := [TerminalData.messages.size()]
	timer.timeout.connect(func() -> void:
		if TerminalData.messages.size() != known[0]:
			known[0] = TerminalData.messages.size()
			fill.call())
	fill.call()
	return _margin(h, 6)

# ————— private line —————

static func _friend() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	var head := Label.new()
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.text = "Send Jim a passenger's name. His answer comes in Dispatch Messages, within a minute or two."
	v.add_child(head)
	var list := ItemList.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(list)
	var send := Button.new()
	send.text = "Send name to Jim"
	send.disabled = true
	v.add_child(send)
	var status := Label.new()
	v.add_child(status)
	var names: Array = []
	var fill := func() -> void:
		var h := HauntDirector.of(v) if v.is_inside_tree() else null
		var sel := list.get_selected_items()
		list.clear()
		names.clear()
		if h == null:
			return
		for e: Array in h.known_names():
			names.append(e[0])
			list.add_item(str(e[0]) + ("   (sent)" if h.already_asked(e[0]) else ""))
		if not sel.is_empty() and sel[0] < list.item_count:
			list.select(sel[0])
		if names.is_empty():
			status.text = "No names yet: ask the passengers who they are."
	list.item_selected.connect(func(i: int) -> void:
		var h := HauntDirector.of(v)
		send.disabled = h == null or h.already_asked(names[i]))
	send.pressed.connect(func() -> void:
		var sel := list.get_selected_items()
		var h := HauntDirector.of(v)
		if sel.is_empty() or h == null:
			return
		h.send_name(names[sel[0]])
		status.text = "Sent: %s" % names[sel[0]]
		send.disabled = true
		fill.call())
	var timer := Timer.new()
	timer.wait_time = 3.0
	timer.autostart = true
	v.add_child(timer)
	timer.timeout.connect(func() -> void: fill.call())
	v.ready.connect(func() -> void: fill.call())
	return _margin(v)
