class_name TerminalData
extends RefCounted
## Everything the staff terminals share (every terminal on the train shows the same records):
## the passenger manifest, which tickets have been checked, the shift log and dispatch messages.
## Generated once per run from a fixed seed, so a given run always has the same passengers.

static var passengers: Array[Dictionary] = []
static var log_text: String = ""
static var messages: Array[Dictionary] = []       # {time, from, subject, body, read}

const FIRST := ["Jan", "Marie", "Josef", "Anna", "František", "Ludmila", "Karel", "Božena", "Václav", "Helena",
		"Otto", "Greta", "Friedrich", "Johanna", "László", "Ilona", "Sándor", "Zofia", "Tadeusz", "Krystyna",
		"Emil", "Vlasta", "Rudolf", "Hedvika", "Miroslav", "Irena", "Viktor", "Klára", "Ernst", "Magda"]
const LAST := ["Novák", "Svoboda", "Dvořák", "Černý", "Procházka", "Kučera", "Veselý", "Horák", "Němec", "Marek",
		"Pokorný", "Hájek", "Brandt", "Weiss", "Hoffmann", "Krause", "Kovács", "Szabó", "Tóth", "Nowak",
		"Kowalski", "Wiśniewski", "Bauer", "Fischer", "Říha", "Beneš", "Fiala", "Sedláček", "Zeman", "Kolář"]
const NOTES := ["", "", "", "", "", "Wake-up call requested", "Travelling with a small dog",
		"Luggage in van: 2 trunks", "Connecting service at terminus", "Requested extra blanket",
		"Concession ticket - check ID", "Unaccompanied minor - escort at terminus", "Diplomatic pouch, van cage",
		"Complained of draught at window", "Medical: diabetic", "Late booking - paid on board"]

static func ensure() -> void:
	if not passengers.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 19301120
	var stops := RouteData.stops()
	var n := 0
	# Sleeper berths 1-8, saloon seats 1-40 (car 2) and 41-80 (car 3), not every seat taken.
	var places: Array = []
	for b in range(1, 9):
		places.append(["CAR 1", "Berth %d" % b, "1st / sleeper"])
	for s in range(1, 81):
		if rng.randf() < 0.55:
			places.append(["CAR 2" if s <= 40 else "CAR 3", "Seat %d" % s, "2nd"])
	for pl: Array in places:
		n += 1
		var from_i := 0 if rng.randf() < 0.6 else rng.randi_range(0, stops.size() - 3)
		var to_i := rng.randi_range(from_i + 1, stops.size() - 1)
		if rng.randf() < 0.45:
			to_i = stops.size() - 1
		passengers.append({
			"name": "%s %s" % [FIRST[rng.randi() % FIRST.size()], LAST[rng.randi() % LAST.size()]],
			"car": pl[0], "place": pl[1], "class": pl[2],
			"ticket": "GCR-%04d-%s" % [rng.randi_range(1000, 9999), "ABCDEFH"[rng.randi() % 7]],
			"from": stops[from_i].name, "to": stops[to_i].name,
			"note": NOTES[rng.randi() % NOTES.size()],
			"checked": rng.randf() < 0.15,
		})
	log_text = "SHIFT LOG - THE CONTINENTAL EXPRESS\nTrain no. 1930, Královec - Kamenný Most\n\n19.02  Took over from day crew. Heating on, all cars.\n19.05  Sleeper made up, berths 1-8.\n"
	messages = [
		{"time": "18.47", "from": "Dispatch Královec", "subject": "Line conditions",
				"body": "Snow forecast for the whole line tonight. Drifting reported between Vrchovina and Sněžná. Keep to timetable where possible; report delays at each stop.", "read": false},
		{"time": "18.55", "from": "Chief Conductor", "subject": "Staff terminal",
				"body": "Manifest is up to date as of departure. Mark tickets as checked here, not on paper. Log anything unusual in the shift log.", "read": false},
	]

static func add_message(from: String, subject: String, body: String) -> void:
	ensure()
	messages.append({"time": clock_text(), "from": from, "subject": subject, "body": body, "read": false})

static func clock_text() -> String:
	var ts: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("TrainState") if Engine.get_main_loop() is SceneTree else null
	var c := 19.0 if ts == null else float(ts.get("clock"))
	var h := int(floor(c))
	var m := int(floor((c - h) * 60.0))
	return "%02d.%02d" % [h, m]

## A passenger's standing in the manifest after a report (found by name, or added as a line of its
## own for a passenger who is not on the printed manifest): the status shows in the Checked column
## and the note.
## `status` is short (the column: "HELD?", "HELD", "FREED"), `note` the longer word.
static func set_status(name: String, car: String, place: String, ticket: String, from: String, to: String, status: String, note: String) -> void:
	ensure()
	for p: Dictionary in passengers:
		if p.name == name:
			p.status = status
			p.note = note
			return
	passengers.append({"name": name, "car": car, "place": place, "class": "2nd", "ticket": ticket,
			"from": from, "to": to, "note": note, "checked": true, "status": status})

## A line in the shift log, timed by the train's clock.
static func log_line(text: String) -> void:
	ensure()
	if not log_text.ends_with("
"):
		log_text += "
"
	log_text += "%s  %s
" % [clock_text(), text]

