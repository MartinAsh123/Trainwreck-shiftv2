class_name PassengerTalk
extends Area3D
## Talking to a passenger (E): a pick volume on the body (layer 2, the player's interaction ray) and
## the conversation, through DialogueMenu, the player's lines and the passenger's answers as
## subtitles (the answers in the passenger's own murmur, TalkingCharacter.say):
##   1. the ticket - handed over and shown as a card (from, to, class, number, the name, the date)
##   2. how they are tonight - an anomaly's answer hints at what is wrong with it (its kind)
##   3. who they are, where they got on and where they are going
## Each passenger gets a made-up identity when it boards (attach()): a Czech name that fits the
## figure, the stop it got on at (where it was waiting, or the first station) and a later stop it
## rides to (a sleeper's dest). An anomaly's story usually has one thing wrong in it too - a ticket
## in someone else's name, an impossible date, a station not on the line, or got on somewhere the
## train has not reached yet - for the player to catch by comparing the answers with the ticket.
##   PassengerTalk.attach(body, slug, base, anomaly)   after the body is made (Passengers._spawn)
##   PassengerTalk.of(body).sleeper_to(stop)           a sleeper's own stop

const NAME := "Talk"
const REACH := 3.5                 # the conversation ends when the player is this far away

const FEMALE := ["Jana", "Marie", "Anna", "Věra", "Hana", "Eva", "Ludmila", "Zdeňka", "Božena", "Alžběta", "Jiřina", "Libuše"]
const MALE := ["Josef", "Jan", "František", "Karel", "Václav", "Jiří", "Antonín", "Miroslav", "Bohumil", "Emil", "Ladislav", "Oldřich"]
const SURNAMES := [["Novák", "Nováková"], ["Dvořák", "Dvořáková"], ["Svoboda", "Svobodová"], ["Černý", "Černá"],
	["Procházka", "Procházková"], ["Kučera", "Kučerová"], ["Veselý", "Veselá"], ["Horák", "Horáková"],
	["Marek", "Marková"], ["Pokorný", "Pokorná"], ["Král", "Králová"], ["Beneš", "Benešová"], ["Fiala", "Fialová"]]
const NOT_ON_LINE := ["ČERNÝ LES", "LIPOVÁ", "STARÉ BRODY", "MĚSÍČNÁ"]   # stations that do not exist

const ASK_TICKET := ["Ticket, please.", "Your ticket, please.", "Tickets, please. May I see yours?"]
const ASK_WELL := ["Are you feeling all right? You look a little pale.", "Has anything been bothering you tonight?",
	"Everything all right here?"]
const ASK_WHO := "Your name, please? And where are you travelling from and to?"
const BYE := "That's all. Thank you."

const TICKET_OK := ["Here you are.", "Of course. Here.", "Here, it's punched already, I think.", "One moment... here it is."]
const WELL_OK := ["Just tired. It's been a long day.", "Fine, thank you. A bit cold, that's all.",
	"I'm well. Is something wrong?", "Only the heating. Otherwise fine.", "A little nervous of the snow, nothing more.",
	"I'm all right. I don't like night trains much."]
const BYE_OK := ["Good night.", "Thank you.", "Mm.", "Good night to you too."]
# An anomaly's answer to "how are you" - by its kind (the folder name after the character's).
const WELL_ANOM := {
	"third_eye": ["I see well enough. Better than most, I'd say.", "Don't stare at my forehead. It's rude."],
	"grey_marks": ["These marks? They were there when I woke up. I think.", "Grey is a calm colour, don't you find?"],
	"long_neck": ["I like to keep my head up. Above the crowd, you understand.", "I'm stretched a little thin tonight."],
	"black_eyes": ["The lamps are too bright in here. My eyes don't need them.", "I'm fine. Don't look at me like that."],
	"six_fingers": ["Count my fingers if you must. Everyone does, in the end.", "My hands are cold. All of them... both of them."],
	"tail": ["Mind where you step, please. I'm sitting on something of mine.", "I can't sit comfortably on these seats. Never could."],
	"faceless": ["Look at me? Why would you want to look at me?", "I'm whatever you remember me as."],
	"cyclops": ["One good eye is all anyone needs, conductor.", "I see you. Only the once, but I see you."],
}
# A ghost among the passengers (HauntDirector makes one): its ticket is from the night of 14 January
# 1931 (GhostStory's), it answers like someone who has been riding a very long time. Talking does
# not end it: Kevin takes its name to Jim, and does what Jim says.
const GHOST_DATE := "14.01.1931"
const WELL_GHOST := ["It's so cold in here. It has been cold for such a long time.",
	"Is it still the fourteenth? I seem to have lost count of the nights.",
	"I'm only going home. I've been going home for a long while now."]
const WELL_ANOM_ANY := ["I'm exactly as I should be.", "Why do you ask? Is something wrong with me?",
	"I've been on this train a very long time."]

var body: TalkingCharacter
var slug := ""
var base := ""
var anomaly := ""                  # the anomaly's kind, "" for a normal passenger
var full_name := ""
var from := ""                     # the stop it got on at
var dest := ""                     # the stop it rides to
var ticket_name := ""
var ticket_from := ""
var ticket_to := ""
var ticket_date := ""
var ticket_no := 0
var ticket_class := "2nd class"
var known := false                 # the player has asked its name
var seen := {}                     # what the player has had from it: "ticket", "well", "who"
var ghost := false                 # not a living passenger (Passengers.reveal_ghost)
var _keys: Array = []              # the menu's lines now, by what they ask
var _rng := RandomNumberGenerator.new()
static var _names_used := {}       # no two passengers of one journey share a name
static var _serial := 0
var _player: Node
var _ask := {}                     # option -> the player's line this time

static func attach(b: TalkingCharacter, slug_: String, base_: String, anomaly_: String) -> PassengerTalk:
	var t := PassengerTalk.new()
	t.name = NAME
	t.body = b
	t.slug = slug_
	t.base = base_
	t.anomaly = anomaly_
	b.add_child(t)
	return t

static func of(b: Node) -> PassengerTalk:
	return b.get_node_or_null(NAME) as PassengerTalk

func _ready() -> void:
	_rng.randomize()
	collision_layer = 2
	collision_mask = 0
	monitoring = false
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.75
	cs.shape = cap
	cs.position = Vector3(0, 0.88, 0)
	add_child(cs)
	_make_story()
	set_process(false)                 # only while a conversation is open

func _exit_tree() -> void:
	_names_used.erase(full_name)
	_end()

# ————— who they are —————

func _make_story() -> void:
	var female := _is_female(base)
	var first: Array = FEMALE if female else MALE
	var sur: Array = []
	for k in 30:
		sur = SURNAMES[_rng.randi_range(0, SURNAMES.size() - 1)]
		full_name = "%s %s" % [first[_rng.randi_range(0, first.size() - 1)], sur[1] if female else sur[0]]
		if not _names_used.has(full_name):
			break
	_names_used[full_name] = true
	if body and body.speaker_name == "":
		# Subtitles keep one line per speaker name: each stranger's "Passenger" differs by a few
		# zero-width spaces, so one's line never replaces another's.
		_serial += 1
		body.speaker_name = "Passenger" + "​".repeat(_serial % 64)
	# Got on where it waits now (or the first station for those aboard from the start); off at a
	# later stop.
	var stops := RouteData.stops()
	var ts := get_node_or_null("/root/TrainState")
	var here := ""
	if ts:
		here = str(ts.get("next_stop")) if str(ts.get("phase")) in ["running", "braking"] else str(ts.get("station"))
	var i_from := 0
	for i in stops.size():
		if stops[i].name == here:
			i_from = i
	i_from = mini(i_from, stops.size() - 2)
	from = str(stops[i_from].name)
	dest = str(stops[_rng.randi_range(i_from + 1, stops.size() - 1)].name)
	ticket_no = _rng.randi_range(1000, 99999)
	ticket_date = "%02d.%02d." % [_rng.randi_range(1, 28), _rng.randi_range(1, 12)]
	ticket_name = full_name
	ticket_from = from
	ticket_to = dest
	if anomaly != "" and _rng.randf() < 0.75:
		match _rng.randi_range(0, 3):
			0:                         # someone else's ticket
				var other: Array = SURNAMES[(SURNAMES.find(sur) + 1 + _rng.randi_range(0, SURNAMES.size() - 2)) % SURNAMES.size()]
				ticket_name = "%s %s" % [first[_rng.randi_range(0, first.size() - 1)], other[1] if female else other[0]]
			1:                         # a date that never was
				ticket_date = ["31.02.", "30.02.", "31.04.", "32.12."][_rng.randi_range(0, 3)]
			2:                         # to a station not on the line (and it says so too)
				dest = NOT_ON_LINE[_rng.randi_range(0, NOT_ON_LINE.size() - 1)]
				ticket_to = dest
			3:                         # says it got on somewhere the train has not been yet
				if i_from + 1 < stops.size() - 1:
					from = str(stops[_rng.randi_range(i_from + 1, stops.size() - 1)].name)

func _is_female(s: String) -> bool:
	for w in ["woman", "female", "girl", "lady", "fashion_model"]:
		if s.contains(w):
			return true
	for w in ["man", "male", "boy", "detective", "military", "officer"]:
		if s.contains(w):
			return false
	return _rng.randf() < 0.5

## A sleeping-car passenger: aboard from the first station, off at `stop` (where it wakes).
func sleeper_to(stop: String) -> void:
	from = str(RouteData.stops()[0].name)
	ticket_from = from
	ticket_class = "Sleeping car"
	if ticket_to == dest:
		ticket_to = stop
	dest = stop

static func nice(station: String) -> String:
	var out := PackedStringArray()
	for w in station.split(" "):
		out.append(w.substr(0, 1) + w.substr(1).to_lower())
	return " ".join(out)

# ————— the conversation —————

func get_prompt() -> String:
	if body == null or body.has_meta("scaring"):
		return ""
	if body.asleep:
		return "E — Wake the passenger"
	return "E — Talk to %s" % (full_name if known else "passenger")

func interact(by: Node = null) -> String:
	if body == null:
		return ""
	if body.asleep:
		var pax := get_tree().root.find_child("Passengers", true, false) as Passengers
		return pax.wake_by_player(pax.rider_of(body)) if pax else "Fast asleep."
	_player = by
	_ask = {"ticket": _pick(ASK_TICKET), "well": _pick(ASK_WELL), "who": ASK_WHO, "bye": BYE}
	var eye := (by as Node3D).get_viewport().get_camera_3d().global_position if by else global_position
	var head := body.global_transform * Vector3(0, body._head_h, 0)
	if body._skel and body._bones.has("Head"):        # where the head really is (seated, lying...)
		head = body._skel.global_transform * body._skel.get_bone_global_pose(body._bones["Head"]).origin
	var view := Transform3D(Basis.looking_at(head - eye, Vector3.UP), eye)
	DialogueMenu.open(self, by, full_name if known else "Passenger", _lines(), _on_pick, view)
	body.set_meta("in_talk", true)     # (no idle chatter from it meanwhile)
	set_process(true)
	return ""

# The questions on offer, and whatever a haunted passenger's own business adds (HauntDirector).
func _lines() -> Array:
	var h := HauntDirector.of(self)
	var extra: Array = h.talk_options(self) if h and ghost else []
	var ch := Chores.of(self)
	if ch and not (h and ghost and h._riddle_open):
		extra += ch.talk_options(self)                # (a coffee asked for...)
	if h and ghost and h._riddle_open:
		_keys = []
	else:
		_keys = ["ticket", "well", "who"]
	for e: Array in extra:
		_keys.append(e[0])
		_ask[e[0]] = e[1]
	_keys.append("bye")
	return _keys.map(func(k): return _ask[k])

func _end() -> void:
	DialogueMenu.close_for(self)
	if body:
		body.remove_meta("in_talk")
	_player = null
	set_process(false)

func _on_pick(i: int) -> void:
	var menu := get_tree().root.get_node_or_null("DialogueMenu") as DialogueMenu
	if menu == null or not menu.is_open_for(self):
		return
	var key: String = _keys[i] if i < _keys.size() else "bye"
	Subtitles.show_line(self, "You", str(_ask[key]), 3.2)
	seen[key] = true
	var answer := ""
	match key:
		"ticket":
			answer = _pick(TICKET_OK)
			menu.set_card(_ticket_card())
		"well":
			if ghost:
				answer = _pick(WELL_GHOST)
			elif anomaly != "":
				answer = _pick(WELL_ANOM.get(anomaly, WELL_ANOM_ANY))
			else:
				answer = _pick(WELL_OK)
		"who":
			answer = _who_line()
			known = true
			body.speaker_name = full_name
			menu.set_title(full_name)
		"bye":
			_end()
			_reply(_pick(BYE_OK), "")
			return
		_:
			# (a haunted passenger's own business, or the work's)
			var h := HauntDirector.of(self)
			if key.begins_with("chore_"):
				var ch := Chores.of(self)
				answer = ch.talk_pick(self, key) if ch else ""
				if answer != "":
					_reply(answer, "smile")
					menu.set_options(_lines())
					return
			else:
				answer = h.talk_pick(self, key) if h else ""
			if answer == "":
				_end()
				return
			_reply(answer, "")
			menu.set_options(_lines())
			return
	menu.mark_asked(_keys.find(key))
	_reply(answer, "suspicious" if anomaly != "" and key == "well" else "")

# The answer a moment after the question (with a look to go with it).
func _reply(text: String, expression: String) -> void:
	get_tree().create_timer(0.9).timeout.connect(func() -> void:
		if not is_instance_valid(body):
			return
		body.say(text)
		if expression != "":
			body.set_expression(expression, 0.8)
			get_tree().create_timer(3.5).timeout.connect(func() -> void:
				if is_instance_valid(body):
					body.set_expression(expression, 0.0)))

func _who_line() -> String:
	var a := nice(from)
	var b := nice(dest)
	match _rng.randi_range(0, 2):
		0:
			return "%s. I got on at %s, and I'm going to %s." % [full_name, a, b]
		1:
			return "My name is %s. From %s, as far as %s." % [full_name, a, b]
		_:
			return "%s. %s to %s, if the snow lets us." % [full_name, a, b]

func _ticket_card() -> String:
	var lines := [
		"[center][b]RAILWAY TICKET[/b]  ·  %s[/center]" % ticket_class,
		"No. %05d          Issued %s" % [ticket_no, ticket_date],
		"From:  [b]%s[/b]" % ticket_from,
		"To:      [b]%s[/b]" % ticket_to,
		"Passenger:  %s" % ticket_name,
	]
	return "\n".join(lines)

func _pick(a: Array) -> String:
	return str(a[_rng.randi_range(0, a.size() - 1)])

func _process(_delta: float) -> void:
	# Walked off (or the player did), or left with Esc: the conversation ends.
	if _player == null:
		return
	var menu := get_tree().root.get_node_or_null("DialogueMenu") as DialogueMenu
	if not is_instance_valid(_player) or menu == null or not menu.is_open_for(self) \
			or (_player as Node3D).global_position.distance_to(body.global_position) > REACH:
		_end()

# ————— what the player can hold against it (Detention, ShiftRecord) —————

## Talked to at all (its ticket checked, asked how it is or who it is).
func investigated() -> bool:
	return seen.has("ticket") or seen.has("well") or seen.has("who")

## The inconsistencies the player has actually been shown (never the hidden truth itself): a ticket
## in another name, a date that never was, a station not on the line, got on where the train has not
## been, an odd answer.
func evidence() -> Array[String]:
	var out: Array[String] = []
	if seen.has("ticket") and seen.has("who") and ticket_name != full_name:
		out.append("ticket made out to %s" % ticket_name)
	if seen.has("ticket") and ticket_date in ["31.02.", "30.02.", "31.04.", "32.12."]:
		out.append("ticket dated %s" % ticket_date)
	if (seen.has("ticket") or seen.has("who")) and dest in NOT_ON_LINE:
		out.append("bound for %s, not on this line" % nice(dest))
	if seen.has("who") and from != ticket_from:
		out.append("says it boarded at %s, ticket says %s" % [nice(from), nice(ticket_from)])
	if seen.has("well") and anomaly != "":
		out.append("an odd answer when asked how it was")
	if seen.has("ticket") and ghost:
		out.append("ticket issued %s" % GHOST_DATE)
	return out

## Made a ghost (Passengers, at the start): rides from the first station to the end of the line on a
## ticket from the night of 14 January 1931.
func become_ghost() -> void:
	ghost = true
	var stops := RouteData.stops()
	from = str(stops[0].name)
	ticket_from = from
	dest = str(stops.back().name)
	ticket_to = dest
	ticket_date = GHOST_DATE
	ticket_name = full_name

