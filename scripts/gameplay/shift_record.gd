class_name ShiftRecord
extends Node
## The shift's account: every passenger who rode (by its journey number, Passengers' pid), whether
## it was an anomaly (hidden until the end), whether the player investigated it and what evidence
## it gave, reports, detentions and how each ended. Each outcome is paid or charged once (never twice
## for the same passenger and outcome) into Kevin's wallet (Economy), and the shift log and the
## manifest are written. The summary is shown when he turns in at the end of the day (EndOfDay).
## Outcomes kept apart (dollars, from Economy):
##   resolved       an anomaly held in the cage (confirmed, or handed over at the end)         +15
##   unresolved     an anomaly the player had questioned, left free (aboard or gone)          -15
##   escaped        an anomaly out of a cage left open, never caught again in its new form    -15
##   fled           an anomaly that attacked him and leapt from the train (AnomalyFrenzy)      0
##   not_checked    an anomaly the player never spoke to                                       -10
##   wrongful       an ordinary passenger held                                                 -20
##   cleared        an ordinary passenger reported but released before the cage, or never held
##   ghost          a passenger who was never alive: laid to rest before it broke anything     +15
##   ghost_left     ... still riding at the end of the day                                     -20
##   breakdown      each breakdown a ghost caused                                              -10

signal changed

var points_resolved := 15
var points_wrongful := -20                 # on being found wrongly held (once)
var points_unresolved := -15               # each questioned anomaly still free at the end
var points_not_checked := -10              # each anomaly never spoken to
var points_ghost := 15                     # a ghost laid to rest in time
var points_ghost_left := -20
var points_breakdown := -10

var reputation := 0                        # the money this record has booked today
var entries := {}                          # pid -> Dictionary (see entry_for)
var _applied := {}                         # "pid:outcome" -> true
var _pax: Passengers
var _poll := 0.0
var finished := false
var shift_over := false                    # the train stands at the end of the line
var breakdowns := 0

static func of(n: Node) -> ShiftRecord:
	return n.get_tree().get_first_node_in_group("shift_record") as ShiftRecord

func _ready() -> void:
	add_to_group("shift_record")
	var ts := get_node_or_null("/root/TrainState")
	if ts:
		ts.connect("arrived", _on_arrived)
	_rates.call_deferred()

# The amounts are the wallet's.
func _rates() -> void:
	var eco := Economy.of(self)
	if eco == null:
		return
	points_resolved = eco.anomaly_held
	points_wrongful = eco.wrongly_held
	points_unresolved = eco.anomaly_left_free
	points_not_checked = eco.anomaly_not_checked
	points_ghost = eco.ghost_rested
	points_ghost_left = eco.ghost_left
	points_breakdown = eco.ghost_breakdown

func _process(delta: float) -> void:
	_poll -= delta
	if _poll > 0.0:
		return
	_poll = 1.5
	if _pax == null:
		_pax = get_tree().root.find_child("Passengers", true, false) as Passengers
		if _pax == null:
			return
	var seen := {}
	for r in _pax.riders():
		if r.state in [Passengers.State.WAITING]:
			continue
		seen[r.pid] = true
		var e := entry_for(r)
		e.ghost = r.ghost
		var t := PassengerTalk.of(r.body)
		if t:
			e.investigated = t.investigated()
			e.evidence = t.evidence()
			e.name = t.full_name
			e.known = t.known
		if r.state == Passengers.State.LEFT and e.left_at == "":
			e.left_at = _station_or_line()
	for pid in entries:
		var e: Dictionary = entries[pid]
		if not seen.has(pid) and e.left_at == "" and not e.revealed:
			e.left_at = _station_or_line()

func _station_or_line() -> String:
	var ts := get_node_or_null("/root/TrainState")
	return str(ts.get("station")) if ts and str(ts.get("station")) != "" else "the line"

## The record for a rider (made on first sight).
func entry_for(r) -> Dictionary:
	if not entries.has(r.pid):
		var t := PassengerTalk.of(r.body)
		entries[r.pid] = {
			"pid": r.pid, "slug": r.slug, "name": t.full_name if t else r.slug, "known": false,
			"anomaly": r.anomaly != "", "kind": r.anomaly,
			"car": _car_code(r), "place": _place_code(r),
			"ticket": "%05d" % t.ticket_no if t else "", "from": t.ticket_from if t else "", "to": t.ticket_to if t else "",
			"investigated": false, "evidence": [], "status": "", "reported": false, "held": false,
			"confirmed": false, "released": false, "fled": false, "left_at": "", "missed": [],
			"ghost": r.ghost, "revealed": false, "broke": false, "escaped": false, "alias_of": -1, "recaught": false,
		}
	return entries[r.pid]

static func _car_code(r) -> String:
	match String(r.car.name) if r.car else "":
		"SleeperCar1": return "CAR 1"
		"PassengerCar": return "CAR 2"
		"PassengerCar3": return "CAR 3"
	return "-"

static func _place_code(r) -> String:
	if r.bed:
		return "Berth %s" % String(r.bed.name).trim_prefix("Bed_")
	if not r.seat.is_empty():
		var parts := String(r.seat.marker.name).split("_")          # Seat_L_03_Back
		var row := int(parts[2]) if parts.size() > 2 else 0
		return "Row %d %s, %s" % [row, "left" if parts.size() > 1 and parts[1] == "L" else "right",
				"window" if absf((r.seat.marker as Node3D).to_global(Vector3(r.seat.lat, 0, 0)).z) > 0.7 else "aisle"]
	return "-"

const WHAT := {
	"resolved": "Anomaly held: %s", "wrongful": "Wrongly held: %s", "unresolved": "Anomaly left free: %s",
	"not_checked": "Anomaly never checked: %s", "ghost": "Ghost laid to rest: %s", "ghost_left": "Ghost still riding: %s",
	"escaped": "Escaped from the cage: %s",
}

## Pays or charges an outcome once per passenger (dollars, into the wallet); false if already counted.
func apply(pid: int, outcome: String, points: int) -> bool:
	var key := "%d:%s" % [pid, outcome]
	if _applied.has(key):
		return false
	_applied[key] = true
	reputation += points
	var eco := Economy.of(self)
	if eco and points != 0:
		var who: String = str(entries[pid].name) if entries.has(pid) else "?"
		eco.book("rec:" + key, points, str(WHAT.get(outcome, outcome + ": %s")) % who, "ghost" if outcome.begins_with("ghost") or outcome == "breakdown" else "anomaly")
	changed.emit()
	return true

## A status change: the entry, the manifest (short status + note) and a log line.
func set_status(pid: int, status: String, short: String, log_text: String) -> void:
	if not entries.has(pid):
		return
	var e: Dictionary = entries[pid]
	e.status = status
	TerminalData.set_status(e.name, e.car, e.place, e.ticket, e.from, e.to, short, status)
	if log_text != "":
		TerminalData.log_line(log_text)
	changed.emit()

func _on_arrived(station: String) -> void:
	if station != str(RouteData.stops().back().name) or shift_over:
		return
	shift_over = true
	TerminalData.add_message("Dispatch", "End of the line",
			"Kamenný Most. That's the shift, Kevin. Hand in what's outstanding and turn in - your berth is in the crew car.")
	var p := get_tree().root.find_child("Player", true, false)
	if p and p.has_method("show_message"):
		p.call("show_message", "End of the line - turn in when you're done (your room, crew car)", 6.0)

## The end of the day: counts what is left (once) and returns the summary.
func finish() -> Dictionary:
	if finished:
		return summary()
	finished = true
	_poll = 0.0
	_process(0.0)
	for pid in entries:
		var e: Dictionary = entries[pid]
		if e.ghost:
			if not e.revealed and e.left_at == "":
				apply(pid, "ghost_left", points_ghost_left)
			continue
		if e.anomaly:
			if e.held:
				if apply(pid, "resolved", points_resolved):
					set_status(pid, "Handed to the police at the terminus", "HELD", "%s handed over to the police at the terminus." % e.name)
				if e.alias_of >= 0 and entries.has(e.alias_of):
					entries[e.alias_of].recaught = true
			elif e.alias_of >= 0:
				pass                                   # (its escape is charged once, below)
			elif e.escaped:
				pass
			elif e.fled:
				pass
			elif e.investigated:
				apply(pid, "unresolved", points_unresolved)
			else:
				apply(pid, "not_checked", points_not_checked)
		elif e.held and not e.released:
			apply(pid, "wrongful", points_wrongful)
	for pid in entries:
		var e: Dictionary = entries[pid]
		if e.escaped and not e.recaught:
			apply(pid, "escaped", points_unresolved)
	var s := summary()
	TerminalData.log_line("End of shift. Anomalies held %d, left free %d (unchecked %d). Wrongly held %d. Today %s." % [
			s.resolved.size(), s.unresolved.size(), s.not_checked.size(), s.wrongful.size(), Economy.money(reputation)])
	return s

func summary() -> Dictionary:
	var out := {"resolved": [], "fled": [], "unresolved": [], "not_checked": [], "wrongful": [], "cleared": [],
			"escaped": [], "ghost_revealed": [], "ghost_missed": [], "breakdowns": breakdowns, "reputation": reputation}
	for pid in entries:
		var e: Dictionary = entries[pid]
		if e.ghost:
			(out.ghost_revealed if e.revealed else out.ghost_missed).append(e)
			continue
		if e.anomaly:
			if e.held:
				out.resolved.append(e)
			elif e.escaped:
				if not e.recaught:
					out.escaped.append(e)
			elif e.alias_of >= 0:
				pass
			elif e.fled:
				out.fled.append(e)
			elif e.investigated:
				out.unresolved.append(e)
			else:
				out.not_checked.append(e)
		elif e.held:
			out.wrongful.append(e)
		elif e.reported:
			out.cleared.append(e)
	return out

## An anomaly turned on the inspector and went out of a door of the moving train.
func anomaly_fled(r) -> void:
	var e := entry_for(r)
	e.fled = true
	set_status(r.pid, "Attacked the inspector and leapt from the moving train", "FLED",
			"%s (%s, %s) attacked the inspector and leapt from the moving train." % [e.name, e.car, e.place])

## A held anomaly got out of the cage (left open) and rides on as `new_r`, another face.
func anomaly_escaped(r, new_r) -> void:
	var e := entry_for(r)
	e.escaped = true
	e.held = false
	var n := entry_for(new_r)
	n.alias_of = r.pid
	set_status(r.pid, "Escaped from the holding cage - the gate was left open", "ESC",
			"%s got out of the holding cage: the gate was left open. Nobody saw where it went." % e.name)

## A ghost passenger laid to rest: paid once, if it never broke anything.
func ghost_revealed(r, _how: String) -> void:
	var e := entry_for(r)
	e.ghost = true
	e.revealed = true
	apply(r.pid, "ghost", 0 if e.broke else points_ghost)
	set_status(r.pid, "Not a living passenger - laid to rest", "GONE", "%s (%s, %s), ticket dated 14.01.1931: laid to rest, and gone from the seat." % [e.name, e.car, e.place])

## A breakdown a ghost caused: charged once each (the ghost that caused it, when given, earns nothing
## when it is laid to rest afterwards).
func apply_incident(haunting: int, n: int, _points: int, text: String, ghost_rider = null) -> void:
	breakdowns += 1
	if ghost_rider == null and HauntDirector.of(self):
		ghost_rider = HauntDirector.of(self).ghost          # (the haunting under way)
	if ghost_rider != null:
		entry_for(ghost_rider).broke = true
	var key := "%d:breakdown" % (-haunting * 100 - n)
	if not _applied.has(key):
		_applied[key] = true
		reputation += points_breakdown
		var eco := Economy.of(self)
		if eco:
			eco.book("rec:" + key, points_breakdown, text.trim_suffix("."), "ghost")
	TerminalData.log_line(text)
	changed.emit()
