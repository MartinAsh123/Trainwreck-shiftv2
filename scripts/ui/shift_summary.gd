class_name ShiftSummary
extends CanvasLayer
## The end of the day, when Kevin turns in (EndOfDay): on the left who was held and rightly so, who
## was let ride on, who was never looked at, who was held for nothing, the ghosts; on the right the
## day's money line by line (the base pay, each work order, the anomalies and ghosts, Jim's fee),
## the day's total and the wallet. "Sleep" starts the next day.

const BG := Color(0.07, 0.06, 0.05, 0.94)
const EDGE := Color(0.89, 0.76, 0.49, 0.9)
const FONT := preload("res://assets/fonts/Oswald.ttf")

signal sleep

var _panel: PanelContainer

func show_summary(s: Dictionary, eco: Economy = null) -> void:
	layer = 20
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG
	sb.border_color = EDGE
	sb.set_border_width_all(2)
	sb.set_content_margin_all(24)
	_panel.add_theme_stylebox_override("panel", sb)
	root.add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_panel.add_child(v)
	var title := _label("END OF DAY %d  —  %s" % [eco.day if eco else 1, str(RouteData.stops().back().name)], 28, EDGE)
	v.add_child(title)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 36)
	v.add_child(cols)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(520, 0)
	left.add_theme_constant_override("separation", 4)
	cols.add_child(left)
	_section(left, "Anomalies held", s.resolved, Color(0.6, 0.9, 0.6))
	_section(left, "Anomalies that attacked you and leapt from the train", s.get("fled", []), Color(0.9, 0.55, 0.65))
	_section(left, "Anomalies questioned but left free", s.unresolved, Color(0.95, 0.75, 0.4))
	_section(left, "Anomalies out of a cage left open", s.get("escaped", []), Color(0.95, 0.6, 0.4))
	_section(left, "Anomalies never checked", s.not_checked, Color(0.8, 0.8, 0.8))
	_section(left, "Ordinary passengers wrongly held", s.wrongful, Color(0.95, 0.5, 0.45))
	_section(left, "Reported, then cleared", s.cleared, Color(0.75, 0.75, 0.9))
	_section(left, "Ghosts laid to rest", s.get("ghost_revealed", []), Color(0.72, 0.78, 0.86))
	_section(left, "Ghosts left riding", s.get("ghost_missed", []), Color(0.55, 0.6, 0.7))
	if int(s.get("breakdowns", 0)) > 0:
		left.add_child(_label("Breakdowns caused by ghosts: %d" % int(s.breakdowns), 18, Color(0.95, 0.75, 0.4)))
	if eco:
		cols.add_child(_ledger(eco))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(row)
	var go := Button.new()
	go.text = "  Sleep  (day %d)  " % ((eco.day if eco else 1) + 1)
	go.add_theme_font_size_override("font_size", 20)
	go.pressed.connect(func() -> void: sleep.emit())
	row.add_child(go)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_center.call_deferred(root)

func _center(root: Control) -> void:
	_panel.position = (root.get_viewport_rect().size - _panel.get_combined_minimum_size()) * 0.5

func _label(text: String, size: int, col := Color(0.93, 0.9, 0.82)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l

func _section(v: VBoxContainer, head: String, list: Array, col: Color) -> void:
	if list.is_empty():
		return
	v.add_child(_label("%s: %d" % [head, list.size()], 18, col))
	for e: Dictionary in list:
		var what := (" — " + str(e.kind).replace("_", " ")) if e.anomaly else ""
		var gone: String = ("  · left at " + PassengerTalk.nice(e.left_at)) if e.left_at != "" and not e.get("escaped", false) else ""
		var d := _label("     %s (%s, %s)%s%s" % [e.name, e.car, e.place, what, gone], 14)
		v.add_child(d)

# The day's money, line by line.
func _ledger(eco: Economy) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(430, 0)
	v.add_theme_constant_override("separation", 2)
	v.add_child(_label("PAY SLIP", 20, EDGE))
	var lines := eco.lines.duplicate()
	lines.sort_custom(func(a, b): return _order(a) < _order(b))
	for l: Dictionary in lines:
		var h := HBoxContainer.new()
		var t := _label(str(l.text), 15)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t.clip_text = true
		h.add_child(t)
		var amt := int(l.amount)
		h.add_child(_label(("+" if amt > 0 else "") + Economy.money(amt), 15, Color(0.62, 0.92, 0.6) if amt > 0 else Color(1.0, 0.5, 0.45)))
		v.add_child(h)
	v.add_child(HSeparator.new())
	var today := eco.today()
	v.add_child(_label("Today  %s%s" % ["+" if today >= 0 else "", Economy.money(today)], 20))
	v.add_child(_label("Wallet  %s" % Economy.money(eco.balance()), 24, EDGE))
	return v

static func _order(l: Dictionary) -> int:
	return {"wage": 0, "routine": 1, "special": 2, "repair": 3, "anomaly": 4, "ghost": 5, "medium": 6}.get(str(l.kind), 7)
