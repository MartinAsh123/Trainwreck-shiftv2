class_name Chores
extends Node
## The shift's ordinary work, handed to the TaskBoard as work orders.
## Every day (routine):
##   - the heating on in both coaches (it starts the night off)
##   - the sleeping car put to night lights (main lamps off, the blue night lights on)
##   - every ticket checked in coach two, then coach three (those aboard as the train leaves the first
##     station; anyone who gets off in the meantime doesn't count)
##   - wake-up calls: sleepers who asked to be woken before their stop (Passengers: they oversleep it
##     otherwise, and the order is missed)
##   - berths to make up in the sleeping car (BerthJob), with the brush, the clean linen and the hamper
##     in the service room, and the W.C.s for whatever was left on them
## Now and then (special): a passenger asks for a coffee (Kevin's desk), brought within a few minutes;
## or whoever sits in the holding cage asks for something to drink - the cage has to be opened for
## that (the key is on the safe in Mike's room), and locked again after (HoldingCage); or a fault in
## a coach with no ghost behind it (HauntDirector.start_fault: the brake, the heating unit, the W.C.,
## the terminal), paid as an ordinary order.
## Pacing: the wake-up calls go to different stops, the middle and the end of the night first
## (`call_stops`); the wrong sleeper (WakeScare) gets one of them, so the scare comes with the job, and
## its order is called off when it springs (sprung_call). Requests keep coming to near the end of the
## line (`special_last`), never over a big scare (HorrorDirector.big).

@export var heating_due := "19.30"
@export var night_due := "19.50"
@export var ticket_due := {"PassengerCar": "19.40", "PassengerCar3": "19.55"}
@export var berths_due := "20.20"
@export var wake_calls := 2
@export var berths_to_make := 2
@export var call_stops := [3, 5, 4, 2, 6]          # where the wake-up calls go (RouteData.stops() indices), first choice first
@export var special_first := 150.0                 # real seconds into the run before the first request
@export var special_gap := Vector2(140.0, 200.0)   # real seconds between requests
@export var special_last := 1500.0                 # metres before the end of the line: no more requests
@export var coffee_window := 200.0                 # real seconds to bring it

const CAR_WORD := {"PassengerCar": "coach two", "PassengerCar3": "coach three", "SleeperCar1": "sleeping car"}

var berths: Array = []                     # BerthJob
var _board: TaskBoard
var _pax: Passengers
var _ts: Node
var _train: Node3D
var _rng := RandomNumberGenerator.new()
var _tickets_set := false
var _wake := {}                            # pid -> task id
var _coffee := {}                          # pid -> task id
var _special_t := 0.0
var _run_t := 0.0
var _spots: Array = []                     # [HauntSpot, item id it wants] shown only while carrying it

static func of(n: Node) -> Chores:
	return n.get_tree().get_first_node_in_group("chores") as Chores

static func clock_of(hhmm: String) -> float:
	var p := hhmm.split(".")
	return float(p[0]) + float(p[1]) / 60.0

func _ready() -> void:
	add_to_group("chores")
	_rng.randomize()
	_ts = get_node_or_null("/root/TrainState")
	_special_t = special_first
	if _ts:
		_ts.connect("departing", _on_departing)
		_ts.connect("arrived", _on_arrived)
	_setup.call_deferred()

func _setup() -> void:
	for i in 3:
		await get_tree().process_frame
	_board = TaskBoard.of(self)
	_pax = get_tree().root.find_child("Passengers", true, false) as Passengers
	_train = get_tree().root.find_child("Train", true, false) as Node3D
	if _board == null or _train == null:
		return
	_heating()
	_night_lights()
	_service_room()
	_waste_bowls()
	_berths()
	_wake_calls()

func _car(n: String) -> Node3D:
	return _train.get_node_or_null(n) as Node3D

func _panels(car: Node3D) -> Array:
	return car.find_children("*", "StaffPanel", true, false) if car else []

# ————— heating and lights —————

func _heating() -> void:
	var panels: Array = []
	for cn in ["PassengerCar", "PassengerCar3"]:
		for p: Node in _panels(_car(cn)):
			p.set("mode", "OFF")
			p.set("saloon_temp", 12.5)
			p.call("_refresh")
			panels.append(p)
	if panels.is_empty():
		return
	_board.add("heating", "Heating on in both coaches", clock_of(heating_due), func() -> bool:
		return panels.all(func(p): return is_instance_valid(p) and str(p.get("mode")) == "HEAT" and bool(p.get("states")["HEATING"])),
		"routine", "staff cabinets")

func _night_lights() -> void:
	var panels := _panels(_car("SleeperCar1"))
	if panels.is_empty():
		return
	_board.add("night", "Night lights in the sleeping car", clock_of(night_due), func() -> bool:
		return panels.all(func(p): return is_instance_valid(p) and not bool(p.get("states")["MAIN"]) and bool(p.get("states")["NIGHT"])),
		"routine", "sleeping car cabinet")

# ————— tickets —————

# As the train leaves the first station: whoever sits in each coach now is on the list.
func _on_departing(_station: String) -> void:
	if _tickets_set or _pax == null or _board == null:
		return
	_tickets_set = true
	for cn: String in ticket_due:
		var pids: Array = []
		for r in _pax.riders():
			if r.car and String(r.car.name) == cn and r.state in [Passengers.State.SEATED, Passengers.State.BOARDING]:
				pids.append(r.pid)
		if pids.is_empty():
			continue
		_board.add("tickets_" + cn, "Check every ticket (%d)" % pids.size(), clock_of(ticket_due[cn]),
				_tickets_checked.bind(pids), "routine", CAR_WORD[cn])

# Done when everyone on the list still aboard has shown a ticket - and at least half the list has
# (a coach emptied at a stop doesn't check itself).
func _tickets_checked(pids: Array) -> bool:
	var shown := 0
	for pid in pids:
		var r = _pax.rider_by_pid(pid)
		var t := PassengerTalk.of(r.body) if r else null
		if t and t.seen.has("ticket"):
			shown += 1
		elif r and not (r.state in [Passengers.State.LEFT, Passengers.State.ALIGHTING, Passengers.State.VANISHING]):
			return false
	return shown * 2 >= pids.size()

# ————— wake-up calls —————

func _wake_calls() -> void:
	if _pax == null:
		return
	var stops := RouteData.stops()
	var names: Array = stops.map(func(s): return str(s.name))
	var can: Array = _pax.riders().filter(func(r): return r.state == Passengers.State.SLEEPING \
			and names.find(r.dest) >= 2 and not r.body.has_meta("wake_scare"))
	can.shuffle()
	# One call a stop where it can be, in the order of call_stops; the wrong sleeper's among them.
	var picked: Array = []
	var ws := WakeScare.of(self)
	if ws and ws.rider and names.find(ws.rider.dest) >= 2:
		picked.append(ws.rider)
	for i: int in call_stops:
		for r in can:
			if picked.size() < wake_calls and names.find(r.dest) == i and not picked.any(func(o): return o.dest == r.dest):
				picked.append(r)
	for r in can:
		if picked.size() < wake_calls and not picked.has(r):
			picked.append(r)
	for r in picked:
		var st: Dictionary = stops[names.find(r.dest)]
		var id := "wake_%d" % r.pid
		r.body.set_meta("wake_call", true)
		_wake[r.pid] = [id, r.dest]
		_board.add(id, "Wake-up call, berth %s, for %s" % [str(r.bed.get_meta("berth", "?")), PassengerTalk.nice(r.dest)],
				clock_of(str(st.time)), func() -> bool: return is_instance_valid(r.body) and r.body.has_meta("woken"),
				"routine", "sleeping car")

func _on_arrived(station: String) -> void:
	if _pax == null or _board == null:
		return
	# A wake-up call not made by the time the train stands at the stop: missed (Passengers lets
	# the sleeper oversleep it).
	for pid in _wake:
		var r = _pax.rider_by_pid(pid)
		var t := _board.get_task(_wake[pid][0])
		if r and t and t.state == "open" and _wake[pid][1] == station and not r.body.has_meta("woken"):
			t.due = _board.clock() - 0.001

# ————— berths, and the service room —————

func _berths() -> void:
	var car := _car("SleeperCar1")
	if car == null:
		return
	var taken := {}
	if _pax:
		for r in _pax.riders():
			if r.bed:
				taken[r.bed] = true
	var free: Array = car.find_children("Bed_*", "Marker3D", true, false).filter(func(b): return not b.has_meta("reserved") and not taken.has(b))
	free.shuffle()
	for i in mini(berths_to_make, free.size()):
		var job := BerthJob.make(free[i], i == 0)
		berths.append(job)
		_board.add("berth_" + job.berth, "Make up berth %s" % job.berth, clock_of(berths_due), job.done, "routine", "sleeping car")

func _service_room() -> void:
	var room := _car("SleeperCar1").find_child("ServiceRoom", true, false) as Node3D if _car("SleeperCar1") else null
	if room == null:
		return
	var drawers := room.get_node_or_null("Drawers") as Node3D
	if drawers:
		var brush := ChoreItem.make_chore("brush", "the scrubbing brush")
		add_child(brush)
		brush.global_transform = drawers.global_transform * Transform3D(Basis(Vector3.UP, 0.4), Vector3(0.22, 0.76, -0.22))
	var shelves := room.get_node_or_null("LinenShelves") as Node3D
	if shelves:
		var s := HauntSpot.make("LinenSpot", Vector3(1.1, 1.7, 0.4), func() -> String:
			return "" if Inventory.carries(self, "linen") else "E — Take a set of clean linen",
			_take_linen)
		add_child(s)
		s.global_transform = shelves.global_transform * Transform3D(Basis.IDENTITY, Vector3(0, 1.0, -0.2))
	var hamper := room.get_node_or_null("Hamper") as Node3D
	if hamper:
		var h := HauntSpot.make("HamperSpot", Vector3(0.6, 0.8, 0.6), func() -> String: return "E — Into the hamper with the dirty bedding",
			func() -> String:
				Inventory.of(self).consume("dirty_linen")
				return "")
		add_child(h)
		h.global_transform = hamper.global_transform * Transform3D(Basis.IDENTITY, Vector3(0, 0.4, -0.3))
		_spots.append([h, "dirty_linen"])

func _take_linen() -> String:
	var inv := Inventory.of(self)
	if inv == null or inv.has_item("linen"):
		return ""
	var it := ChoreItem.make_chore("linen", "the clean linen")
	add_child(it)
	it.global_position = _player_pos()
	var msg := inv.take(it)
	if msg != "":
		it.queue_free()
	return msg

# Every W.C. bowl takes the waste found on a berth.
func _waste_bowls() -> void:
	for bowl: Node in _train.find_children("ToiletBowl*", "Node3D", true, false):
		var s := HauntSpot.make("WasteSpot", Vector3(0.5, 0.5, 0.5), func() -> String: return "E — Flush it away",
			func() -> String:
				Inventory.of(self).consume("waste")
				return "Gone. Wash your hands, Kevin.")
		add_child(s)
		s.global_position = (bowl as Node3D).global_position + Vector3(0, 0.35, 0)
		_spots.append([s, "waste"])

func _player_pos() -> Vector3:
	var p := get_tree().root.find_child("Player", true, false) as Node3D
	return p.global_position if p else Vector3.ZERO

# ————— special requests —————

func _process(delta: float) -> void:
	# The spots that take something only answer while it is carried.
	for e: Array in _spots:
		var s: HauntSpot = e[0]
		if is_instance_valid(s):
			(s.get_node("Pick") as Area3D).collision_layer = 2 if Inventory.carries(self, e[1]) else 0
	if _ts == null or _pax == null or _board == null or str(_ts.get("phase")) != "running":
		return
	_run_t += delta
	_special_t -= delta
	var hd := HorrorDirector.of(self)
	if _special_t <= 0.0 and hd and hd.big != "":
		_special_t = 10.0                              # (not over a big scare: right after it)
	if _special_t <= 0.0 and RouteData.end_s() - float(_ts.get("distance")) < special_last:
		_special_t = INF                               # (the end of the line: no time for it)
	if _special_t <= 0.0:
		_special_t = _rng.randf_range(special_gap.x, special_gap.y)
		var h := HauntDirector.of(self)
		var roll := _rng.randf()
		if roll < 0.3 and h and h.start_fault():
			pass                                       # (a fault with no ghost behind it)
		elif roll < 0.6 and _drink_request():
			pass
		else:
			_coffee_request()

func _coffee_request() -> void:
	var can: Array = _pax.riders().filter(func(r): return r.state == Passengers.State.SEATED and not r.ghost \
			and not _coffee.has(r.pid) and String(r.car.name) in ["PassengerCar", "PassengerCar3"])
	if can.is_empty():
		return
	var r = can[_rng.randi_range(0, can.size() - 1)]
	var rec := ShiftRecord.of(self)
	var place: String = str(rec.entry_for(r).place).to_lower() if rec else "a seat"
	var word: String = CAR_WORD.get(String(r.car.name), "the train")
	var id := "coffee_%d" % r.pid
	_coffee[r.pid] = id
	_board.add(id, "Coffee for the passenger at %s" % place, _board.due_in(coffee_window), func() -> bool:
		return not _pax.riders().has(r) and _board.get_task(id).state == "open" and _cancel(id), "special", word)
	TerminalData.add_message("Passengers, %s" % word, "A coffee, please", "The passenger at %s in %s would like a cup of coffee. There's a pot in the inspector's room." % [place, word])
	var p := get_tree().root.find_child("Player", true, false)
	if p and p.has_method("show_message"):
		p.call("show_message", "A coffee wanted in %s - see Dispatch Messages" % word, 4.0)

# Someone in the cage (an hour's worth of the guard's patience) wants a drink.
func _drink_request() -> bool:
	var det := Detention.of(self)
	if det == null:
		return false
	for pid in det.held:
		var r = _pax.rider_by_pid(pid)
		if r == null or _coffee.has(pid) or r.state != Passengers.State.DETAINED:
			continue
		var id := "drink_%d" % pid
		_coffee[pid] = id
		_board.add(id, "Something to drink for the one in the cage", _board.due_in(coffee_window), func() -> bool:
			return not _pax.riders().has(r) and _board.get_task(id).state == "open" and _cancel(id), "special", "mail van")
		TerminalData.add_message("Mike", "The one in the cage", "Our guest in the cage has been on at me for a drink. I'm busy - take them a cup, will you? My key's on the safe in my room. Lock up after you.")
		var p := get_tree().root.find_child("Player", true, false)
		if p and p.has_method("show_message"):
			p.call("show_message", "Message from Mike - see Dispatch Messages", 4.0)
		return true
	return false

func _cancel(id: String) -> bool:
	_board.cancel(id)
	return false

## The wrong sleeper has sprung (WakeScare): its wake-up call is called off - it was never a passenger.
func sprung_call(r) -> void:
	if r == null or not _wake.has(r.pid) or _board == null:
		return
	_board.cancel(_wake[r.pid][0])
	_wake.erase(r.pid)

## Extra lines in a conversation (PassengerTalk): [[key, the player's line], ...]
func talk_options(t: PassengerTalk) -> Array:
	var r = _pax.rider_of(t.body) if _pax else null
	if r and _coffee.has(r.pid) and Inventory.carries(self, "coffee"):
		var task := _board.get_task(_coffee[r.pid])
		if task and task.state in ["open", "missed"]:
			return [["chore_coffee", "Here, something to drink." if r.state == Passengers.State.DETAINED else "Your coffee."]]
	return []

## One of those lines picked: what the passenger answers.
func talk_pick(t: PassengerTalk, key: String) -> String:
	var r = _pax.rider_of(t.body) if _pax else null
	if key == "chore_coffee" and r and _coffee.has(r.pid):
		Inventory.of(self).use("coffee")
		var late := _board.get_task(_coffee[r.pid]).state == "missed"
		_board.complete(_coffee[r.pid])
		return "Finally. It's gone cold, I expect." if late else "Ah, thank you. Just what I needed on a night like this."
	return ""
