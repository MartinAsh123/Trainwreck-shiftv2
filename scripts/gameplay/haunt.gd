class_name HauntDirector
extends Node3D
## The hauntings: now and then one of the seated passengers turns out not to be a living one, and
## Kevin has to lay it to rest.
##   1. signs     in its car: a child's giggle, the lamps faltering, then the heating cuts out and
##                the passengers round about start complaining (the cold, the heat, a strange smell).
##                The ghost itself shows for an instant now and again (it pales and comes back), and
##                it gives itself away where it sits: frost spreads over its seat, its table and the
##                floor round it, its breath smokes when nobody else's does, its eyes follow Kevin
##                down the car, and up close it giggles under its breath.
##   2. the name  he finds it (its ticket is dated 14.01.1931, it answers oddly) and asks its name.
##   3. Jim    on any staff terminal he sends the name to Jim, his old friend on the private
##                line, who answers after a minute or two with what this one needs: a cup of
##                coffee, the evening paper, a certain thing said to it, or the answer to its riddle.
##   4. at rest   he does it, in conversation with the ghost: it turns the apparition's colour,
##                wavers and is gone (GhostFade), and its car goes back to normal.
##   5. breakdown not done within 7-8 minutes, something goes wrong in that car and Kevin has to
##                put it right, in addition: it pulls the emergency brake and the train stands until
##                he resets the handle; the heating unit fails (a screwdriver from the sleeping car's
##                service room, open the ceiling hatch, reconnect its cables); the W.C. blocks (the
##                plunger from the same service room); or the car's terminal dies (reinstall it from
##                the USB stick in Kevin's compartment). The deadline then starts again.
## Pacing (HorrorDirector): a haunting never starts in a rest after a big scare or over a peak; its signs
## are the build's minor signs and keep out of the rest; a breakdown due is a big event and waits (up
## to `break_wait`) for the curve to let it through, and always for a goods train due soon to go by first.
## Provisional: Jim and the instructions are a first pass for review.
## The things Kevin picks up go into his toolbar (Inventory). Once he knows of a haunting (the
## complaints are in, or he has been in its car), ShiftHUD shows its time left (ghost_timer()). A
## breakdown is also a work order (TaskBoard): put right in `repair_window` or it is missed. The same
## faults come now and then without a ghost, as special orders (start_fault(), from Chores).

signal stage_changed(stage: String)

const SALOONS := ["PassengerCar", "PassengerCar3"]
const CAR_WORD := {"PassengerCar": "coach two", "PassengerCar3": "coach three"}
const FRIEND := "Jim (private line)"

@export var enabled := true
@export var first_start := 100.0       # real seconds into the running journey
@export var deadline := 420.0          # real seconds (7 minutes) before something breaks...
@export var deadline_max := 480.0      # ... up to this (8 minutes)
@export var reply_min := 60.0          # Jim's answer takes this long, real seconds...
@export var reply_max := 120.0         # ... up to this
@export var gap_min := 120.0           # real seconds of peace between hauntings
@export var gap_max := 200.0
@export var break_wait := 150.0        # real seconds a breakdown due may wait for the curve, at most
@export var max_hauntings := 3
@export var points_incident := -10     # each breakdown a ghost causes (ShiftRecord takes Economy's)
@export var repair_window := 180.0     # real seconds to put a breakdown right (a work order)
@export var sign_gap := Vector2(55.0, 95.0)       # real seconds between its giggles and flickers
@export var moan_gap := Vector2(8.0, 15.0)        # real seconds between passengers' complaints
@export var flash_gap := Vector2(14.0, 26.0)      # real seconds between the ghost showing itself

const COMPLAINTS := [
	"What is that smell? Like wet earth.",
	"Something's rotting in here, I swear it.",
	"Do you smell that? Lilies, like a funeral.",
	"It's freezing all of a sudden.",
	"The heating's gone off again!",
	"I can see my own breath. Conductor!",
	"It's stifling in here. Can't somebody open something?",
	"Hot, then cold... what's wrong with this carriage?",
	"Did you hear a child just now?",
	"Someone should fetch the inspector.",
	"There's frost on the seats over there. Frost, indoors!",
	"The window's iced over by that seat. Only that one.",
	"That one by the window hasn't blinked once.",
]
const TELL_WORDS := "The line is clear. You may get off now."
const RIDDLES := [
	{"q": "What runs all night and never leaves its bed?", "a": ["A river.", "The train.", "The wind."], "ok": 0},
	{"q": "What has one eye and goes through the dark, and no one can stop it?", "a": ["A needle.", "An owl.", "The locomotive."], "ok": 2},
	{"q": "The more of it there is, the less you see. What is it?", "a": ["Snow.", "Darkness.", "Smoke."], "ok": 1},
]

var stage := "waiting"                 # waiting | signs | done
var ghost                              # the Rider it is
var car: Node3D
var kind := ""                         # what it needs: coffee | newspaper | say | riddle
var told := false                      # Jim has answered
var incident := ""                     # a breakdown under way: "" | ebrake | ac | toilet | computer
var known := false                     # Kevin knows of the haunting (the HUD's ghost timer)
var count := 0                         # hauntings so far
var history: Array = []                # what happened, for tests and the log

var _ts: Node
var _pax: Passengers
var _hd: HorrorDirector
var _rng := RandomNumberGenerator.new()
var _t := 0.0                          # seconds of journey
var _next_start := 0.0
var _left := 0.0                       # seconds left before something breaks
var _sign_t := 0.0
var _moan_t := 0.0
var _flash_t := 0.0
var _step := 0                         # opening beats of the signs
var _step_t := 0.0
var _kinds_used: Array = []
var _breaks_used: Array = []
var _asked := {}                       # name -> true: already put to Jim
var _replies: Array = []               # [{at, subject, body, then}]
var _items := {}                       # id -> HauntItem
var _repair_id := ""                  # the breakdown's work order
var _fault_only := false               # a fault with no ghost behind it (a special order)
var _panel_mode := {}                  # car -> its heating mode before the ghost
var _riddle := {}
var _riddle_open := false
# a breakdown's parts, freed when it is put right
var _spots: Array = []
var _job_state := 0
var _hatch: Node3D
var _hatch_rest: Transform3D
var _term: ComputerTerminal
var _installing := 0.0
var _brake: Node3D                     # the emergency brake it pulled
var _brake_lamp: OmniLight3D
var _blink_t := 0.0
# Its marks where it sits (see _marks_on).
var _frost: Decal
var _frost_k := 0.0
var _puff_t := 0.0
var _whisper_t := 0.0
var _ghost_look := 0.0
var _ghost_layers := {}                # people's meshes -> their render layers (the frost leaves people out)
var _spare_t := 0.0
static var _frost_tex: Texture2D
static var _puff_tex: Texture2D

static func of(n: Node) -> HauntDirector:
	return n.get_tree().get_first_node_in_group("haunt") as HauntDirector

func _ready() -> void:
	add_to_group("haunt")
	_rng.randomize()
	_ts = get_node_or_null("/root/TrainState")
	_next_start = first_start
	_setup.call_deferred()

func _setup() -> void:
	await get_tree().process_frame
	_pax = get_tree().root.find_child("Passengers", true, false) as Passengers
	_hd = HorrorDirector.of(self)
	_place_items()
	TerminalData.add_message(FRIEND, "If it starts again",
			"Kevin - you know what I told you about that line. If a carriage goes cold and people start smelling things, one of your passengers is not a passenger. Find out which, get the name, and send it to me from any terminal (Private Line on the desktop). I'll look it up and tell you what it wants. Don't leave it long: they get restless, and then things break. - J.")

# ————— the things to carry —————

func _place_items() -> void:
	var train := get_tree().root.find_child("Train", true, false) as Node3D
	if train == null:
		return
	var crew := train.get_node_or_null("CrewCar4") as Node3D
	if crew == null:
		return
	var guard := crew.find_child("GuardRoom", true, false) as Node3D
	var mine := crew.find_child("InspectorRoom", true, false) as Node3D
	var h := CrewCar.DESK_H
	if mine and mine.get_node_or_null("Desk"):
		_add_item("coffee", "the cup of coffee", (mine.get_node("Desk") as Node3D).global_transform * Vector3(0.12, h, -0.3))
	# (Mike's desk is full: the paper lies on his chair)
	if guard and guard.get_node_or_null("Chair"):
		_add_item("newspaper", "the evening paper", (guard.get_node("Chair") as Node3D).global_position + Vector3(0, 0.525, 0))
	# The USB stick with the terminal's system on it, on Kevin's own nightstand.
	if mine and mine.get_node_or_null("Nightstand"):
		_add_item("usb", "the USB stick", (mine.get_node("Nightstand") as Node3D).global_transform * Vector3(0.12, 0.58, -0.33))   # (in front of the mug)
	# The tools are in the sleeping car's service room: the plunger by the broom (in place of the
	# one modelled there), the screwdriver on the chest of drawers in front of the toolbox.
	var svc := train.find_child("ServiceRoom", true, false) as Node3D
	if svc:
		var pl := svc.get_node_or_null("Plunger") as Node3D
		if pl:
			# (a little out from the corner, clear of the linen shelves' pick box)
			var at := pl.global_transform * Vector3(0, 0, -0.25)
			var ls := svc.get_node_or_null("LinenShelves") as Node3D
			if ls:
				at.z += signf(at.z - ls.global_position.z) * 0.12
			_add_item("plunger", "the plunger", at)
			pl.visible = false
		var dr := svc.get_node_or_null("Drawers") as Node3D
		if dr:
			_add_item("screwdriver", "the screwdriver", dr.global_transform * Vector3(0.12, 0.762, -0.4))
			(_items["screwdriver"] as Node3D).global_basis = dr.global_basis

func _add_item(id: String, text: String, at: Vector3) -> void:
	var it := HauntItem.make(id, text, self)
	add_child(it)
	it.global_position = at
	_items[id] = it

## Kevin picks up `it`: into his toolbar.
func take(it: HauntItem) -> String:
	var inv := Inventory.of(self)
	return inv.take(it) if inv else ""

## He has `id` with him.
func _has(id: String) -> bool:
	return Inventory.carries(self, id)

## `id` has done its job: out of the toolbar and back where it came from.
func _used(id: String) -> void:
	var inv := Inventory.of(self)
	if inv:
		inv.use(id)

# ————— the course of a haunting —————

func _process(delta: float) -> void:
	if not enabled or _ts == null or _pax == null:
		return
	_t += delta
	_update_replies()
	_update_install(delta)
	_update_ebrake(delta)
	match stage:
		"waiting":
			if _t >= _next_start and count < max_hauntings and _can_start():
				_begin()
		"signs":
			_update_signs(delta)

func _can_start() -> bool:
	if str(_ts.get("phase")) != "running" or incident != "":
		return false
	# Not with the end of the line in sight: there would be no time to do anything about it.
	if str(_ts.get("next_stop")) == str(RouteData.stops().back().name) and float(_ts.get("to_next_stop")) < 9000.0:
		return false
	# Never in the night's rest after a big scare, nor over its peak.
	if _hd and _hd.enabled and (_hd.resting() or _hd.phase == "peak"):
		return false
	return not _pick_ghost().is_empty()

func _pick_ghost() -> Array:
	return _pax.riders().filter(func(r): return r.state == Passengers.State.SEATED and r.anomaly == "" \
			and not r.ghost and not r.body.has_meta("in_talk") and String(r.car.name) in SALOONS)

func _begin() -> void:
	var can := _pick_ghost()
	ghost = can[_rng.randi_range(0, can.size() - 1)]
	car = ghost.car
	_pax.make_ghost(ghost)
	count += 1
	stage = "signs"
	told = false
	_riddle_open = false
	_left = _deadline()
	known = false
	_step = 0
	_step_t = 0.0
	_sign_t = 0.0
	_moan_t = 0.0
	_flash_t = _rng.randf_range(6.0, 12.0)
	var left: Array = ["coffee", "newspaper", "say", "riddle"].filter(func(k): return not k in _kinds_used)
	if left.is_empty():
		_kinds_used.clear()
		left = ["coffee", "newspaper", "say", "riddle"]
	kind = left[_rng.randi_range(0, left.size() - 1)]
	_kinds_used.append(kind)
	_riddle = RIDDLES[_rng.randi_range(0, RIDDLES.size() - 1)]
	_marks_on()
	if _hd:
		_hd.mark("haunting %d (%s)" % [count, car.name], "work")
	_note("haunting %d: %s in %s wants %s" % [count, ghost.body.name, car.name, kind])
	stage_changed.emit(stage)

## For the HUD: once Kevin knows of the haunting, the time before it breaks something; while a
## breakdown is on, the time left to put it right. {text, left (real seconds)}, or {} for nothing.
func ghost_timer() -> Dictionary:
	if car == null:
		return {}
	var word: String = CAR_WORD.get(String(car.name), "the train")
	if incident != "":
		var b := TaskBoard.of(self)
		var task := b.get_task(_repair_id) if b else null
		if task and task.state == "open":
			return {"text": "Fault · %s" % word, "left": b.time_left(task)}
		return {}
	if stage == "signs" and known:
		return {"text": "Ghost · %s" % word, "left": _left}
	return {}

func _ghost_at() -> Vector3:
	return ghost.body.global_position + Vector3(0, 1.4, 0)

func _player() -> Node3D:
	var p := get_tree().get_first_node_in_group("player") as Node3D
	return p if p else get_tree().root.find_child("Player", true, false) as Node3D

func _player_in_car() -> bool:
	var p := _player()
	return p != null and car != null and absf(p.global_position.x - car.global_position.x) < 8.9 and p.global_position.y > 1.0

func _update_signs(delta: float) -> void:
	if ghost == null or not _pax.riders().has(ghost) or ghost.state != Passengers.State.SEATED:
		_end_haunting(false)
		return
	# Left too long: something breaks (counted from its first sign).
	if incident == "":
		_left -= delta
		if _left <= 0.0 and (_hd == null or (not _hd.fixed_soon() and not _hd.hold and not _hd.resting()
				and (_hd.big_ready("breakdown", false) or _left < -break_wait))):
			_start_incident()
	_update_marks(delta)
	if not known and (_step >= 3 or _player_in_car()):
		known = true
	# The opening: a giggle, the lamps, then the heating goes and the complaining starts.
	_step_t += delta
	if _step == 0 and _step_t > 0.5:
		_step = 1
		_hd_event("giggle", ghost.body.global_position + Vector3(_rng.randf_range(-3.0, 3.0), 1.2, 0))
	elif _step == 1 and _step_t > 20.0:
		_step = 2
		_hd_event("flicker", _ghost_at() + Vector3(0, 0.8, 0))
	elif _step == 2 and _step_t > 42.0:
		_step = 3
		_heating_off()
		_moan_t = 0.0
		_sign_t = _rng.randf_range(sign_gap.x, sign_gap.y)
		var word: String = CAR_WORD.get(String(car.name), "the train")
		TerminalData.add_message("Passengers, %s" % word, "Complaint", "The heating has stopped in %s. It smells strange in there too. Could the inspector come?" % word)
		var p := _player()
		if p and p.has_method("show_message") and not _player_in_car():
			p.call("show_message", "Complaints from %s: the heating has failed" % word, 4.0)
	if _step < 3:
		return
	# After that: more of the same, and the people round about.
	_sign_t -= delta
	if _sign_t <= 0.0 and _hd and _hd.resting():
		_sign_t = 8.0                                  # (not in the night's rest, nor over a big scare)
	if _sign_t <= 0.0:
		_sign_t = _rng.randf_range(sign_gap.x, sign_gap.y)
		_heating_off()                                 # (turned back on at the panel, it fails again)
		if _rng.randf() < 0.5:
			_hd_event("giggle", ghost.body.global_position + Vector3(_rng.randf_range(-4.0, 4.0), 1.2, 0))
		else:
			_hd_event("flicker", _ghost_at() + Vector3(0, 0.8, 0))
	_moan_t -= delta
	if _moan_t <= 0.0:
		_moan_t = _rng.randf_range(moan_gap.x, moan_gap.y)
		if _player_in_car():
			_pax.complain(car, COMPLAINTS[_rng.randi_range(0, COMPLAINTS.size() - 1)])
	# It shows itself for an instant, to anyone looking its way in its car.
	_flash_t -= delta
	if _flash_t <= 0.0:
		_flash_t = _rng.randf_range(flash_gap.x, flash_gap.y)
		var cam := get_viewport().get_camera_3d()
		if _player_in_car() and cam and cam.is_position_in_frustum(_ghost_at()) and not ghost.body.has_meta("in_talk"):
			GhostFade.flash(ghost.body)

func _hd_event(what: String, at: Vector3) -> void:
	if _hd:
		_hd.trigger(what, at)
	history.append([TerminalData.clock_text(), what])

func _heating_off() -> void:
	for pn: Node in car.find_children("*", "StaffPanel", true, false):
		if not _panel_mode.has(car):
			_panel_mode[car] = pn.get("mode")
		if str(pn.get("mode")) != "OFF":
			pn.set("mode", "OFF")
			pn.call("_refresh")

func _heating_back(c: Node3D) -> void:
	for pn: Node in c.find_children("*", "StaffPanel", true, false):
		pn.set("mode", _panel_mode.get(c, "HEAT"))
		pn.call("_refresh")
	_panel_mode.erase(c)

func _end_haunting(rested: bool) -> void:
	_note("haunting %d over (%s)" % [count, "laid to rest" if rested else "it left"])
	if incident == "" and car:
		_heating_back(car)
	_marks_off()
	ghost = null
	stage = "waiting"
	told = false
	_next_start = _t + _rng.randf_range(gap_min, gap_max)
	stage_changed.emit(stage)

func _note(s: String) -> void:
	history.append([TerminalData.clock_text(), s])

# ————— Jim —————

## The names Kevin has got out of the passengers (Private Line's list): [[name, PassengerTalk], ...]
func known_names() -> Array:
	var out: Array = []
	if _pax == null:
		return out
	for r in _pax.riders():
		var t := PassengerTalk.of(r.body)
		if t and t.known:
			out.append([t.full_name, t])
	return out

func already_asked(n: String) -> bool:
	return _asked.has(n)

## Kevin sends a name down the line; the answer comes in a minute or two.
func send_name(n: String) -> void:
	if _asked.has(n):
		return
	_asked[n] = true
	var eco := Economy.of(self)
	if eco:
		eco.medium_used()                          # (his fee, once a day he is asked)
	var at := _t + _rng.randf_range(reply_min, reply_max)
	var hit: bool = ghost != null and PassengerTalk.of(ghost.body) != null and PassengerTalk.of(ghost.body).full_name == n
	if hit:
		_replies.append({"at": at, "subject": "About %s" % n, "body": _instructions(n), "ghost": ghost})
	else:
		_replies.append({"at": at, "subject": "About %s" % n, "body": "Nothing, Kevin. %s is in no register of mine - alive and well, as far as I can tell. Look again: who is cold when everyone else is warm? Whose ticket is older than it should be? - J." % n, "ghost": null})
	_note("name sent to Jim: %s (%s)" % [n, "the ghost" if hit else "wrong"])

func _instructions(n: String) -> String:
	var head := "Found it. %s died on the night of 14 January 1931, on this very line. It doesn't know. " % n
	match kind:
		"coffee":
			return head + "The attendant had promised a cup of coffee that never came, and it is waiting still. Bring it a cup of coffee and set it down in front of it. There's always a pot going in your own room - take a cup from your desk. - J."
		"newspaper":
			return head + "It wanted the evening paper, to see the news of the line. Bring it one. Mike leaves the evening paper on his chair. - J."
		"say":
			return head + "It was never told it could get off. Go to it and say these words, exactly: \"%s\" - J." % TELL_WORDS
		_:
			return head + "It has a riddle it has been asking for ninety years. Ask what it wants of you, and answer it truly. Think before you answer: a wrong one upsets it. - J."

func _update_replies() -> void:
	for r: Dictionary in _replies.duplicate():
		if _t < float(r.at):
			continue
		_replies.erase(r)
		TerminalData.add_message(FRIEND, r.subject, r.body)
		if r.ghost != null and r.ghost == ghost:
			told = true
			_note("Jim answered: %s" % kind)
		var p := _player()
		if p and p.has_method("show_message"):
			p.call("show_message", "A message on the private line", 3.0)

# ————— in conversation with the ghost —————

## Extra lines for PassengerTalk: [[key, the player's line], ...]
func talk_options(t: PassengerTalk) -> Array:
	if ghost == null or PassengerTalk.of(ghost.body) != t or not told:
		return []
	if _riddle_open:
		var out: Array = []
		for i in _riddle.a.size():
			out.append(["haunt_ans_%d" % i, _riddle.a[i]])
		return out
	match kind:
		"coffee":
			if _has("coffee"):
				return [["haunt_give", "I've brought your coffee."]]
		"newspaper":
			if _has("newspaper"):
				return [["haunt_give", "Here's the evening paper."]]
		"say":
			return [["haunt_say", TELL_WORDS]]
		"riddle":
			return [["haunt_riddle", "You wanted to ask me something?"]]
	return []

## A line of talk_options picked. Returns what the ghost answers ("" when the conversation ends).
func talk_pick(t: PassengerTalk, key: String) -> String:
	match key:
		"haunt_give":
			_put_back_used()
			_rest(t, "...Thank you. I'd been waiting so long.")
		"haunt_say":
			_rest(t, "...May I? ...At last.")
		"haunt_riddle":
			_riddle_open = true
			return str(_riddle.q)
		_:
			if key.begins_with("haunt_ans_"):
				_riddle_open = false
				if int(key.trim_prefix("haunt_ans_")) == int(_riddle.ok):
					_rest(t, "...Yes. That is it. Nobody ever knew.")
				else:
					_left = maxf(_left - 45.0, 20.0)
					_hd_event("flicker", _ghost_at() + Vector3(0, 0.8, 0))
					return "No. No, that isn't it."
	return ""

func _put_back_used() -> void:
	_used(kind)                                    # (the coffee cup back on the desk, the paper on the chair)

func _rest(t: PassengerTalk, last: String) -> void:
	var r = ghost
	t.body.say(last, 2.6)
	_end_haunting(true)
	get_tree().create_timer(2.4).timeout.connect(func() -> void:
		_pax.reveal_ghost(r, "calmed"))

# ————— breakdowns —————

func _deadline() -> float:
	return _rng.randf_range(deadline, maxf(deadline, deadline_max))

const BREAKS := ["ebrake", "ac", "toilet", "computer"]
const REPAIR_WORD := {"ebrake": "the emergency brake", "ac": "the heating unit", "toilet": "the blocked W.C.", "computer": "the terminal"}

## A fault with no ghost behind it (Chores' special orders): one of the same breakdowns, in a coach,
## paid as an ordinary work order. False while a haunting or another breakdown is on.
func start_fault() -> bool:
	if stage != "waiting" or incident != "" or _pax == null or _ts == null or str(_ts.get("phase")) != "running":
		return false
	var train := get_tree().root.find_child("Train", true, false) as Node3D
	var c := train.get_node_or_null(SALOONS[_rng.randi_range(0, SALOONS.size() - 1)]) as Node3D if train else null
	if c == null:
		return false
	car = c
	_fault_only = true
	_start_incident()
	return true

func _start_incident() -> void:
	var left: Array = BREAKS.filter(func(k): return not k in _breaks_used)
	if left.is_empty():
		_breaks_used.clear()
		left = BREAKS.duplicate()
	left.shuffle()
	# (the brake only out on the line at speed; the W.C. only if nobody is in it)
	var k := ""
	for c: String in left + BREAKS.filter(func(x): return not x in left):
		if c == "ebrake" and not _can_brake():
			continue
		if c == "toilet" and not _pax.block_wc(car, true):
			continue
		k = c
		break
	if k == "":
		k = "computer"
	_breaks_used.append(k)
	incident = k
	_job_state = 0
	var word: String = CAR_WORD.get(String(car.name), "the train")
	if _hd:
		if _fault_only:
			_hd.mark("fault: %s (%s)" % [k, car.name], "work")
		elif _hd.big == "":
			var bk := "breakdown: %s (%s)" % [k, car.name]
			_hd.begin_big(bk)
			get_tree().create_timer(25.0).timeout.connect(_hd.end_big.bind(bk))
	var rec := ShiftRecord.of(self)
	if rec and not _fault_only:
		rec.apply_incident(count, _breaks_used.size(), points_incident, "Breakdown in %s: %s." % [word, k])
	var board := TaskBoard.of(self)
	if board:
		_repair_id = "repair_%d_%d_%s" % [count, _breaks_used.size(), String(car.name)]
		board.add(_repair_id, "Put right: %s" % REPAIR_WORD.get(k, k), board.due_in(repair_window), Callable(),
				"special" if _fault_only else "repair", word, _fault_only)
	var text := ""
	match k:
		"ebrake":
			_ebrake_begin()
			text = "The emergency brake has been pulled in %s and the train is standing. Reset the handle there to recharge the brake line." % word
		"toilet":
			_toilet_begin()
			text = "The W.C. in %s has blocked and is flooding. There's a plunger in the service room of the sleeping car." % word
		"ac":
			_ac_begin()
			text = "The heating unit in %s has failed. The ceiling hatch at the W.C. end gives on to it; it is screwed shut, and there's a screwdriver in the sleeping car's service room." % word
		"computer":
			_computer_begin()
			text = "The terminal in %s has stopped working. Reinstall it: the USB stick is on the nightstand in your compartment." % word
	TerminalData.add_message("Maintenance", "Fault in %s" % word, text)
	var p := _player()
	if p and p.has_method("show_message"):
		p.call("show_message", ("Emergency brake pulled in %s!" if k == "ebrake" else "Fault in %s - see Dispatch Messages") % word, 5.0)
	_note("breakdown: %s in %s" % [k, car.name])

func _incident_done() -> void:
	var was := incident
	for s: Node in _spots:
		if is_instance_valid(s):
			s.queue_free()
	_spots.clear()
	incident = ""
	_left = _deadline()
	if ghost == null and car:
		_heating_back(car)
	var board := TaskBoard.of(self)
	if board and _repair_id != "":
		board.complete(_repair_id)
	_repair_id = ""
	_fault_only = false
	TerminalData.log_line("Fault in %s put right (%s)." % [CAR_WORD.get(String(car.name), "the train"), was])
	_note("fixed: %s" % was)

func _spot(spot_name: String, at: Vector3, size: Vector3, p: Callable, a: Callable) -> HauntSpot:
	var s := HauntSpot.make(spot_name, size, p, a)
	add_child(s)
	s.global_position = at
	_spots.append(s)
	return s

func _glossy(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.08
	m.metallic = 0.0
	return m

# ——— the W.C.: the plunger (the water drains away with the blockage) ———

func _toilet_begin() -> void:
	var bowl := car.find_child("ToiletBowl", true, false) as Node3D
	var at := bowl.global_position
	var pool := MeshInstance3D.new()
	var q := CylinderMesh.new()
	q.top_radius = 0.55
	q.bottom_radius = 0.55
	q.height = 0.004
	pool.mesh = q
	var water := _glossy(Color(0.3, 0.27, 0.19, 0.62))
	water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pool.material_override = water
	pool.scale = Vector3(1.0, 1.0, 0.7)
	var pool_holder := _spot("Puddle", at + Vector3(-0.55, 0.012, -0.1), Vector3(1.0, 0.5, 0.8), _puddle_prompt, _puddle_use)
	pool_holder.add_child(pool)
	_spot("BlockedBowl", at + Vector3(0, 0.45, 0), Vector3(0.6, 0.7, 0.6), _bowl_prompt, _bowl_use)

func _bowl_prompt() -> String:
	if _job_state >= 3:
		return "The W.C. runs clear"
	if _has("plunger"):
		return "E — Plunge (%d/3)" % _job_state
	return "Blocked. It needs a plunger"

func _bowl_use() -> String:
	if _job_state >= 3 or not _has("plunger"):
		return ""
	_job_state += 1
	_sound("door_locked", -8.0, 0.6)
	if _job_state >= 3:
		_pax.block_wc(car, false)
		_used("plunger")
		_incident_done()
		return "It clears with a gurgle, and the water drains away."
	return ""

func _puddle_prompt() -> String:
	return "Water all over the floor"

func _puddle_use() -> String:
	return ""

# ——— the heating unit: the ceiling hatch and its cables ———

const CABLES := [["red", Color(0.65, 0.1, 0.08)], ["yellow", Color(0.75, 0.6, 0.12)], ["black", Color(0.05, 0.05, 0.05)]]

func _ac_begin() -> void:
	_heating_off()
	var g := car.find_child("ACHatch", true, false)
	_hatch = g.get_node("Hatch") as Node3D if g else null
	if _hatch == null:
		_incident_done()
		return
	_hatch_rest = _hatch.transform
	_spot("HatchLatch", _hatch.global_position + Vector3(0, -0.05, 0), Vector3(1.0, 0.16, 0.66), _hatch_prompt, _hatch_use)

func _hatch_prompt() -> String:
	match _job_state:
		0:
			return "E — Unscrew the service hatch" if _has("screwdriver") else "The hatch is screwed shut. It needs a screwdriver"
		4:
			return "E — Close the hatch"
	return "Loose cables: reconnect them"

func _hatch_use() -> String:
	if _job_state == 0:
		if not _has("screwdriver"):
			return ""
		_used("screwdriver")
		_job_state = 1
		_sound("lock_turn", -6.0, 1.0)
		_swing_hatch(true)
		var at := _hatch.global_position
		var dark := MeshInstance3D.new()
		var p := BoxMesh.new()
		p.size = Vector3(0.92, 0.004, 0.56)
		dark.mesh = p
		dark.material_override = _glossy(Color(0.015, 0.015, 0.015))
		var holder := HauntSpot.new()
		add_child(holder)
		holder.global_position = at + Vector3(0, -0.012, 0)
		holder.add_child(dark)
		_spots.append(holder)
		for i in CABLES.size():
			_cable(i, at + Vector3(-0.26 + i * 0.26, -0.02, 0.05))
	elif _job_state == 4:
		_swing_hatch(false)
		_sound("lock_turn", -6.0, 0.9)
		_heating_back(car)
		_incident_done()
		return "The fans spin up again."
	return ""

func _swing_hatch(open: bool) -> void:
	# (hinged along its corridor edge: local +Y of the hatch, +Z down into the car)
	var hinge := Transform3D(Basis.IDENTITY, Vector3(0, 0.3, 0))
	var tw := create_tween()
	var from := _hatch.transform
	var to := _hatch_rest * hinge * Transform3D(Basis(Vector3(1, 0, 0), -1.25), Vector3.ZERO) * hinge.affine_inverse() if open else _hatch_rest
	tw.tween_method(func(k: float) -> void: _hatch.transform = from.interpolate_with(to, k), 0.0, 1.0, 0.8)

func _cable(i: int, at: Vector3) -> void:
	var c: Array = CABLES[i]
	var m := StandardMaterial3D.new()
	m.albedo_color = c[1]
	m.roughness = 0.6
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.012
	mesh.bottom_radius = 0.012
	mesh.height = 0.34
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.rotation.z = 0.5                               # hanging loose
	mi.position.y = -0.17
	var st := {"fixed": false}
	var sp := _spot("Cable_" + str(c[0]), at, Vector3(0.2, 0.42, 0.2),
			func() -> String: return "Connected" if st.fixed else "E — Reconnect the %s cable" % c[0],
			func() -> String:
				if st.fixed:
					return ""
				st.fixed = true
				mi.rotation.z = 0.0
				mi.position.y = 0.05
				mi.scale.y = 0.45
				_sound("pc_click", -4.0, 0.7)
				_job_state += 1
				return "")
	sp.add_child(mi)

# ——— the terminal: reinstall from the USB stick ———

func _computer_begin() -> void:
	var list := car.find_children("*", "ComputerTerminal", true, false)
	if list.is_empty():
		_incident_done()
		return
	_term = list[0] as ComputerTerminal
	_term.set_broken(true)
	_term.fault = self

## ComputerTerminal asks, broken: what the prompt says, and what E does there.
func terminal_prompt() -> String:
	if _installing > 0.0:
		return "Installing... %d%%" % int((1.0 - _installing / 8.0) * 100.0)
	return "E — Plug in the USB stick" if _has("usb") else "Terminal dead. It needs reinstalling from the USB stick"

func terminal_use() -> String:
	if not _has("usb") or _installing > 0.0:
		return ""
	_used("usb")
	_installing = 8.0
	return ""

func _update_install(delta: float) -> void:
	if _installing <= 0.0:
		return
	_installing -= delta
	if _term:
		_term.set_progress(1.0 - maxf(_installing, 0.0) / 8.0)
	if _installing <= 0.0:
		_installing = 0.0
		_term.set_broken(false)
		_term.fault = null
		_term = null
		_incident_done()

# ——— the emergency brake: the train stands till the handle is reset ———

func _journey() -> Node:
	return get_tree().root.find_child("Journey", true, false)

func _can_brake() -> bool:
	return str(_ts.get("phase")) == "running" and float(_ts.get("speed")) > 8.0 and _journey() != null \
			and not car.find_children("EmergencyBrake_*", "", true, false).is_empty()

func _ebrake_begin() -> void:
	var best: Node3D = null
	var near: Vector3 = _ghost_at() if ghost else car.global_position      # (a fault with no ghost: any)
	for n: Node3D in car.find_children("EmergencyBrake_*", "", true, false):
		if best == null or n.global_position.distance_to(near) < best.global_position.distance_to(near):
			best = n
	_brake = best
	_journey().set("emergency", true)
	_play_2d("ebrake_stop", -1.0)
	if _hd:
		_hd.trauma(0.4)                                # (the jolt of the brakes going on)
	var sp := _spot("EmergencyBrake", best.global_position, Vector3(0.5, 0.8, 0.5), _brake_prompt, _brake_use)
	# The lever on the wall is thrown: the brake model itself turns down about the wall's normal.
	_throw_brake(true)
	_brake_lamp = OmniLight3D.new()
	_brake_lamp.light_color = Color(1.0, 0.12, 0.05)
	_brake_lamp.omni_range = 2.2
	_brake_lamp.light_energy = 0.0
	_brake_lamp.shadow_enabled = false
	sp.add_child(_brake_lamp)
	_brake_lamp.position = Vector3(0, 0.35, 0)
	get_tree().create_timer(5.0).timeout.connect(func() -> void:
		if incident == "ebrake" and _player_in_car():
			_pax.complain(car, "Who pulled the emergency brake? Why are we standing?"))

# Throws the brake's own lever (EBrakeLever on the wall) out, or back down.
func _throw_brake(pulled: bool) -> void:
	var lever := _brake.get_child(0) as EBrakeLever if _brake and _brake.get_child_count() > 0 else null
	if lever:
		lever.throw(pulled)

func _brake_prompt() -> String:
	if _job_state > 0:
		return "The brake line is recharging..."
	if float(_ts.get("speed")) > 0.3:
		return "The train is still stopping"
	return "E — Reset the emergency brake"

func _brake_use() -> String:
	if _job_state > 0 or float(_ts.get("speed")) > 0.3:
		return ""
	_job_state = 1
	_play_2d("ebrake_reset", -2.0)
	_throw_brake(false)
	get_tree().create_timer(4.0).timeout.connect(func() -> void:
		if incident != "ebrake":
			return
		var j := _journey()
		if j:
			j.set("emergency", false)
		_brake = null
		_incident_done()
		TerminalData.log_line("Emergency brake reset in %s; the train moved off again." % CAR_WORD.get(String(car.name), "the train")))
	return "You throw the handle back. The brake line hisses as it fills."

func _update_ebrake(delta: float) -> void:
	if incident != "ebrake" or _brake_lamp == null or not is_instance_valid(_brake_lamp):
		return
	_blink_t += delta
	_brake_lamp.light_energy = (1.6 if fmod(_blink_t, 0.8) < 0.4 else 0.0) if _job_state == 0 else 0.0

func _play_2d(key: String, db: float) -> void:
	var path := "res://assets/audio/%s.mp3" % key
	if not ResourceLoader.exists(path):
		return
	var p := AudioStreamPlayer.new()
	p.stream = load(path)
	p.volume_db = db
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)

# ——— its marks where it sits ———

func _marks_on() -> void:
	var b: TalkingCharacter = ghost.body
	_ghost_look = b.look_range
	b.look_range = 9.0                                 # (its eyes follow him all down the car)
	# Frost over its seat, its table and the floor round it (not over itself, nor anyone by it).
	_ghost_layers.clear()
	_spare(b)
	_spare_t = 0.0
	_frost = Decal.new()
	_frost.size = Vector3(1.25, 2.4, 1.25)             # (its own seat and table; not the people opposite)
	_frost.texture_albedo = _frost_texture()
	_frost.texture_emission = _frost_texture()           # (a faint glint, even in a dim car)
	_frost.emission_energy = 0.12
	_frost.modulate = Color(1, 1, 1, 0)
	_frost.normal_fade = 0.25
	_frost.upper_fade = 0.15
	_frost.lower_fade = 0.15
	_frost.cull_mask = 0xFFFFF & ~(1 << 19)
	add_child(_frost)
	_frost.global_position = b.global_position + Vector3(0, 1.0, 0)
	_frost_k = 0.0
	_puff_t = 2.0
	_whisper_t = 0.0

# Takes a body's meshes off the layer the frost lands on (put back in _marks_off).
func _spare(body: Node3D) -> void:
	for vi: VisualInstance3D in body.find_children("*", "VisualInstance3D", true, false):
		if not _ghost_layers.has(vi):
			_ghost_layers[vi] = vi.layers
			vi.layers = 1 << 19

func _marks_off() -> void:
	if ghost and is_instance_valid(ghost.body):
		(ghost.body as TalkingCharacter).look_range = _ghost_look
	for vi in _ghost_layers:                     # (untyped: some may be freed with their passenger by now)
		if is_instance_valid(vi):
			(vi as VisualInstance3D).layers = _ghost_layers[vi]
	_ghost_layers.clear()
	if _frost and is_instance_valid(_frost):
		var f := _frost
		var tw := create_tween()
		tw.tween_property(f, "modulate:a", 0.0, 3.0)
		tw.tween_callback(f.queue_free)
	_frost = null

func _update_marks(delta: float) -> void:
	var b: TalkingCharacter = ghost.body
	# The frost creeps in over the first minute and a half.
	if _frost:
		_frost_k = minf(_frost_k + delta / 90.0, 1.0)
		_frost.modulate.a = smoothstep(0.0, 1.0, _frost_k)
		# Whoever sits down or stops beside it stays unfrosted.
		_spare_t -= delta
		if _spare_t <= 0.0:
			_spare_t = 0.5
			var near: Array = _pax.riders().map(func(r): return r.body)
			var duty := get_tree().get_first_node_in_group("mike_duty")
			if duty and duty.get("mike"):
				near.append(duty.get("mike"))
			for body: Node3D in near:
				if is_instance_valid(body) and body.global_position.distance_to(b.global_position) < 2.2:
					_spare(body)
	if not _player_in_car():
		return
	# Its breath smokes, as nobody else's does.
	_puff_t -= delta
	if _puff_t <= 0.0:
		_puff_t = _rng.randf_range(2.6, 4.2)
		_puff(b)
	# Close by, it giggles under its breath.
	_whisper_t -= delta
	var p := _player()
	if p and _whisper_t <= 0.0 and not b.has_meta("in_talk") \
			and Vector2(p.global_position.x - b.global_position.x, p.global_position.z - b.global_position.z).length() < 1.7:
		_whisper_t = 30.0
		var w := AudioStreamPlayer3D.new()
		w.stream = load("res://assets/audio/horror_giggle.mp3")
		w.unit_size = 1.2
		w.max_distance = 8.0
		w.volume_db = -6.0
		w.pitch_scale = 0.86
		add_child(w)
		w.global_position = _face_of(b)
		w.play()
		w.finished.connect(w.queue_free)

func _face_of(b: TalkingCharacter) -> Vector3:
	var i: int = b._bones.get("Head", -1)
	if b._skel and i >= 0:
		return (b._skel.global_transform * b._skel.get_bone_global_pose(i)).origin + Vector3(0, 0.07, 0)
	return b.global_position + Vector3(0, 1.2, 0)

# One breath: a thin, ragged mist of many faint wisps (no single round puff), out and up a little,
# gone in under two seconds; it thins away too when Kevin's face is right in it.
func _puff(b: TalkingCharacter) -> void:
	var e := CPUParticles3D.new()
	e.one_shot = true
	e.emitting = false
	e.amount = 26
	e.lifetime = 1.7
	e.explosiveness = 0.35
	e.randomness = 0.6
	e.local_coords = false
	e.direction = Vector3(0, 0.25, 1)
	e.spread = 16.0
	e.initial_velocity_min = 0.16
	e.initial_velocity_max = 0.34
	e.damping_min = 0.15
	e.damping_max = 0.3
	e.gravity = Vector3(0, 0.05, 0)
	e.angle_min = -180.0
	e.angle_max = 180.0
	e.angular_velocity_min = -25.0
	e.angular_velocity_max = 25.0
	e.scale_amount_min = 0.7
	e.scale_amount_max = 1.3
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.35))
	grow.add_point(Vector2(1, 1.0))
	e.scale_amount_curve = grow
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.85, 0.9, 0.96, 0.0))
	ramp.set_color(1, Color(0.85, 0.9, 0.96, 0.0))
	ramp.add_point(0.12, Color(0.85, 0.9, 0.96, 0.07))
	ramp.add_point(0.5, Color(0.85, 0.9, 0.96, 0.035))
	e.color_ramp = ramp
	var q := QuadMesh.new()
	q.size = Vector2(0.09, 0.09)
	q.material = _breath_material()
	e.mesh = q
	add_child(e)
	e.global_transform = Transform3D(b.global_basis.orthonormalized(), _face_of(b) + b.global_basis.z.normalized() * 0.1 - Vector3(0, 0.06, 0))
	e.emitting = true
	e.finished.connect(e.queue_free)

static var _breath_mat: StandardMaterial3D

static func _breath_material() -> StandardMaterial3D:
	if _breath_mat:
		return _breath_mat
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_texture = _wisp_texture()
	m.proximity_fade_enabled = true
	m.proximity_fade_distance = 0.15
	m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	m.distance_fade_min_distance = 0.15
	m.distance_fade_max_distance = 0.6
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_breath_mat = m
	return m

# A ragged wisp: noise thinned towards the edge, never a clean disc.
static func _wisp_texture() -> Texture2D:
	if _puff_tex:
		return _puff_tex
	var n := FastNoiseLite.new()
	n.frequency = 0.09
	n.fractal_octaves = 3
	var sz := 64
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	for y in sz:
		for x in sz:
			var r := Vector2(x - sz * 0.5, y - sz * 0.5).length() / (sz * 0.5)
			var a := clampf(1.0 - r, 0.0, 1.0)
			a = a * a * clampf(0.5 + n.get_noise_2d(x, y) * 1.2, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_puff_tex = ImageTexture.create_from_image(img)
	return _puff_tex

# Hoar frost: feathery crystals, thick in the middle, thinning to nothing at the edge.
static func _frost_texture() -> Texture2D:
	if _frost_tex:
		return _frost_tex
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_CELLULAR
	n.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	n.frequency = 0.028
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = 3
	var lump := FastNoiseLite.new()
	lump.frequency = 0.012
	var sz := 256
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	for y in sz:
		for x in sz:
			var r := Vector2(x - sz * 0.5, y - sz * 0.5).length() / (sz * 0.5)
			var edge := clampf(1.0 - r + lump.get_noise_2d(x, y) * 0.35, 0.0, 1.0)
			var vein := clampf(1.0 - absf(n.get_noise_2d(x, y)) * 3.0, 0.0, 1.0)
			var a := smoothstep(0.0, 0.35, edge) * (0.3 + 0.6 * vein)
			img.set_pixel(x, y, Color(0.9, 0.95, 1.0, a))
	_frost_tex = ImageTexture.create_from_image(img)
	return _frost_tex

func _sound(key: String, db: float, pitch: float) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = load("res://assets/audio/%s.wav" % key)
	p.volume_db = db
	p.pitch_scale = pitch
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)
