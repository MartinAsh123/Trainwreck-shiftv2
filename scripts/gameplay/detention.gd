class_name Detention
extends Node
## Reports and the holding cage. Kevin reports a passenger to Mike (StaffTalk); Detention decides
## whether Mike takes it on (one at a time, never the same passenger twice, never past the cage's
## places) and keeps the passenger's standing: reported -> escorting -> held -> confirmed (an
## anomaly) or found wrongly held -> released and walked back to its seat. MikeDuty does the
## walking. A report is an accusation only: nothing about the passenger's true nature is shown
## until its papers have been checked, `verify_minutes` (game time) after it is locked in.
## A held passenger whose stop comes and goes stays in the cage (logged); released afterwards, it
## gets off at the next stop instead.

signal report_accepted(pid: int)

@export var verify_minutes := 12.0          # game minutes from the lock to the papers' check

var pending_pid := -1                       # accepted, Mike not yet on it
var active_pid := -1                        # Mike on it (walking to, escorting)
var held := {}                              # pid -> {place, verify_at, checked}
var to_release: Array[int] = []
var _pax: Passengers
var _cage: HoldingCage
var _ts: Node

static func of(n: Node) -> Detention:
	return n.get_tree().get_first_node_in_group("detention") as Detention

func _ready() -> void:
	add_to_group("detention")
	_ts = get_node_or_null("/root/TrainState")
	if _ts:
		_ts.connect("arrived", _on_arrived)

func _pax_() -> Passengers:
	if _pax == null:
		_pax = get_tree().root.find_child("Passengers", true, false) as Passengers
	return _pax

func _cage_() -> HoldingCage:
	if _cage == null:
		_cage = HoldingCage.of(self)
	return _cage

func _record() -> ShiftRecord:
	return ShiftRecord.of(self)

## Riders Kevin can name to Mike: aboard, spoken to, not already reported or held.
func reportable() -> Array:
	var out: Array = []
	var pax := _pax_()
	if pax == null:
		return out
	for r in pax.riders():
		if not (r.state in [Passengers.State.SEATED, Passengers.State.ERRAND, Passengers.State.PREPARING, Passengers.State.SLEEPING]):
			continue
		var t := PassengerTalk.of(r.body)
		if t == null or not t.investigated():
			continue
		if r.pid == pending_pid or r.pid == active_pid or held.has(r.pid):
			continue
		out.append(r)
	return out

## How Kevin names it in the report.
func label(r) -> String:
	var t := PassengerTalk.of(r.body)
	var who := t.full_name if t and t.known else "the passenger"
	var e: Dictionary = _record().entry_for(r) if _record() else {}
	var car: String = {"CAR 1": "the sleeping car", "CAR 2": "coach two", "CAR 3": "coach three"}.get(e.get("car", ""), "the train")
	return "%s — %s, %s" % [who, car, str(e.get("place", "")).to_lower()]

## Kevin reports `r`. Returns {ok, line}: whether Mike takes it on, and what he says.
func report(r) -> Dictionary:
	var pax := _pax_()
	var rec := _record()
	var cage := _cage_()
	if r == null or pax == null or not pax.riders().has(r) or not (r.state in [Passengers.State.SEATED, Passengers.State.ERRAND, Passengers.State.PREPARING, Passengers.State.SLEEPING]):
		return {"ok": false, "line": "Who? I don't see anyone like that aboard."}
	if held.has(r.pid):
		return {"ok": false, "line": "That one's already in the cage, Kevin."}
	if r.pid == pending_pid or r.pid == active_pid:
		return {"ok": false, "line": "I heard you the first time. I'm on it."}
	if pending_pid >= 0 or active_pid >= 0:
		return {"ok": false, "line": "One at a time, Kevin. I'm still dealing with the last one."}
	if cage == null or not cage.ready_() or cage.free_place() < 0:
		return {"ok": false, "line": "The cage is full. Nobody else goes in tonight - keep an eye on them instead."}
	if r.state == Passengers.State.SLEEPING:
		return {"ok": false, "line": "Asleep in a berth? I'm not dragging anyone out of bed on a hunch. Wait till they're up."}
	var e := rec.entry_for(r)
	var t := PassengerTalk.of(r.body)
	var ev: Array = t.evidence() if t else []
	e.reported = true
	pending_pid = r.pid
	rec.set_status(r.pid, "Reported by the inspector%s" % ((" (" + ", ".join(ev) + ")") if not ev.is_empty() else " (no stated grounds)"), "REP?",
			"Reported %s, %s %s, to the guard. Grounds: %s." % [e.name, e.car, e.place, ", ".join(ev) if not ev.is_empty() else "none given"])
	report_accepted.emit(r.pid)
	var station := str(_ts.get("phase")) in ["stopped", "departing"] if _ts else false
	var line := ""
	if not ev.is_empty():
		line = "%s? Right. I'll fetch them." % ev[0].capitalize()
	else:
		line = "On what grounds? ...All right. It's your call, Kevin. I'll bring them in."
	if station:
		line += " Once we're away from the platform."
	return {"ok": true, "line": line}

## MikeDuty takes the pending report.
func take_pending() -> int:
	var pid := pending_pid
	pending_pid = -1
	active_pid = pid
	return pid

## The escort fell through (blocked, the passenger gone...): the report is closed, not counted.
func on_cancelled(r, why: String) -> void:
	if r != null and _record():
		_record().set_status(r.pid, "Report closed: %s" % why, "-", "Escort of %s called off: %s." % [_record().entry_for(r).name, why])
	active_pid = -1

## Locked in the cage.
func on_detained(r, place: int) -> void:
	active_pid = -1
	var rec := _record()
	var e := rec.entry_for(r)
	e.held = true
	held[r.pid] = {"place": place, "verify_at": float(_ts.get("clock")) + verify_minutes / 60.0, "checked": false}
	rec.set_status(r.pid, "Held in the van cage, not yet identified", "HELD?", "%s locked in the holding cage by the guard." % e.name)

## Walked out and back to the seat (a wrongly held passenger).
func on_released(r) -> void:
	held.erase(r.pid)
	to_release.erase(r.pid)
	if _cage_():
		_cage.leave_place(r.pid)
	var rec := _record()
	var e := rec.entry_for(r)
	e.released = true
	rec.set_status(r.pid, "Released with apologies, back in its seat", "FREED", "%s released from the cage and returned to the seat." % e.name)
	if not e.missed.is_empty():
		var nxt := str(_ts.get("next_stop")) if _ts else ""
		var t := PassengerTalk.of(r.body)
		if t and nxt != "":
			t.dest = nxt
			TerminalData.log_line("%s missed %s while held; will leave at %s." % [e.name, PassengerTalk.nice(e.missed[0]), PassengerTalk.nice(nxt)])

func _process(_delta: float) -> void:
	if _ts == null or _record() == null:
		return
	var clock := float(_ts.get("clock"))
	for pid in held.keys():
		var h: Dictionary = held[pid]
		if h.checked or clock < h.verify_at:
			continue
		h.checked = true
		var e: Dictionary = _record().entries.get(pid, {})
		if e.is_empty():
			continue
		if e.anomaly:
			e.confirmed = true
			_record().apply(pid, "resolved", _record().points_resolved)
			_record().set_status(pid, "Identity false - held for the police", "HELD",
					"Guard checked %s's papers against dispatch: no such passenger booked. Held for the police." % e.name)
		else:
			_record().apply(pid, "wrongful", _record().points_wrongful)
			_record().set_status(pid, "Papers in order - to be released", "FREE?",
					"Guard checked %s's papers: in order. Wrongly held; to be released." % e.name)
			if not to_release.has(pid):
				to_release.append(pid)

func _on_arrived(station: String) -> void:
	var pax := _pax_()
	if pax == null or _record() == null:
		return
	for r in pax.riders():
		if (held.has(r.pid) or r.pid == active_pid) and pax._dest(r) == station:
			var e := _record().entry_for(r)
			if not e.missed.has(station):
				e.missed.append(station)
				TerminalData.log_line("%s's stop, %s, passed while held." % [e.name, PassengerTalk.nice(station)])

## A release Mike should go and do (or -1).
func next_release() -> int:
	return to_release[0] if not to_release.is_empty() else -1

## The reported passenger was a ghost (the guard could not lay a hand on it): the report is closed.
func on_vanished(r) -> void:
	active_pid = -1
	if r != null and _record():
		_record().set_status(r.pid, "Reported - the guard could not take hold of it", "?", "")
