class_name StaffTalk
extends Area3D
## Talking to the train's guard (MIKE, in the crew car's guard room) and the station guards (the
## police officer in the booking hall, the military officer on the platform): E opens DialogueMenu
## with the role's questions; the answers come in the character's murmur under a subtitle. Mike's
## know the train - how many anomalies are aboard and which car to start with, the next stop and
## its time; the station guards' know their station.
##   StaffTalk.attach(body, "mike" | "police" | "military")
## The pick volume is a little wider than the figure's own solid capsule, so the player's ray meets
## it first.

const NAME := "Talk"
const REACH := 3.5

const POLICE_NAMES := ["Hana Malá", "Věra Šimková", "Jana Křížová", "Eva Bartošová"]
const MILITARY_NAMES := ["Marie Holubová", "Zdeňka Urbanová", "Libuše Kratochvílová", "Alena Doležalová"]
const CAR_WORDS := {"SleeperCar1": "the sleeping car", "PassengerCar": "coach two", "PassengerCar3": "coach three"}

# role -> [title prefix, [[the player's line, topic], ...]]
const ROLES := {
	"mike": ["", [["Anything strange aboard tonight?", "anomalies"], ["What exactly do you do here?", "job"],
		["Where are we? When's the next stop?", "next"], ["Carry on, Mike.", "bye"]]],
	"police": ["Officer ", [["Anything to report?", "report"], ["Who are you?", "job"],
		["When does the next train leave?", "next"], ["Thank you, officer.", "bye"]]],
	"military": ["Lieutenant ", [["Is the line quiet tonight?", "report"], ["Who are you?", "job"],
		["When does the next train leave?", "next"], ["As you were.", "bye"]]],
}

const MIKE_NONE := ["Quiet so far. Everyone I've seen looks like who they say they are.",
	"Nothing yet. Doesn't mean there won't be. Keep checking those tickets."]
const MIKE_ONE := "Something's off aboard. One of them, I'd say. I'd start with %s."
const MIKE_MANY := "More than one tonight, if you ask me. %d, maybe. I'd start with %s. Look at the eyes, count the fingers."
const MIKE_JOB := ["Train security. I keep this car locked and the passengers honest. You check the tickets, I watch the doors.",
	"Twelve years on this line. I've seen things in the snow you wouldn't write in a report."]
const MIKE_BYE := ["Shout if you need me.", "I'll be here.", "Mind how you go."]
const POLICE_REPORT := ["Quiet. A few travellers without papers, nothing more.",
	"One gentleman went through the arch twice and it never rang. Odd, that.",
	"A woman asked me for a station I've never heard of. Then she was gone."]
const MILITARY_REPORT := ["Quiet. Too quiet for a night like this.", "Nothing on the line but snow. We've had reports of people on the track who aren't there when you look.",
	"The signals have been behaving. The passengers, less so."]
const GUARD_BYE := ["Good night.", "Safe journey.", "Carry on."]

# Mike's extra lines (MikeDuty, Detention, GhostStory): reporting a passenger, a sighting.
const ASK_REPORT := "I want to report a passenger."
const ASK_GHOST := "I saw someone in the sleeping car corridor. Then they weren't there."
const REPORT_NONE := "Report who? You haven't checked anyone's papers yet. Talk to them first."
const NEVER_MIND := "Never mind."

var body: TalkingCharacter
var role := "mike"
var _opts: Array = []              # [the player's line, topic] shown now
var _mode := "main"                # main | report
var _report_list: Array = []
var title := ""
var _rng := RandomNumberGenerator.new()
var _player: Node

static func attach(b: TalkingCharacter, role_: String) -> StaffTalk:
	var t := StaffTalk.new()
	t.name = NAME
	t.body = b
	t.role = role_
	b.add_child(t)
	return t

func _ready() -> void:
	_rng.randomize()
	collision_layer = 2
	collision_mask = 0
	monitoring = false
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.36
	cap.height = 1.85
	cs.shape = cap
	cs.position = Vector3(0, 0.92, 0)
	add_child(cs)
	match role:
		"mike":
			title = "Mike"
		"police":
			title = str(ROLES.police[0]) + POLICE_NAMES[_rng.randi_range(0, POLICE_NAMES.size() - 1)]
		"military":
			title = str(ROLES.military[0]) + MILITARY_NAMES[_rng.randi_range(0, MILITARY_NAMES.size() - 1)]
	if body.speaker_name == "":
		body.speaker_name = title
	set_process(false)

func _exit_tree() -> void:
	_end()

func get_prompt() -> String:
	var duty := MikeDuty.of(self) if role == "mike" else null
	if duty and duty.is_asleep():
		return "E — Wake %s" % title
	return "E — Talk to %s" % title

func interact(by: Node = null) -> String:
	var duty := MikeDuty.of(self) if role == "mike" else null
	if duty and duty.is_asleep():
		duty.wake()
		return ""
	_player = by
	var eye := (by as Node3D).get_viewport().get_camera_3d().global_position if by else global_position
	var head := body.global_transform * Vector3(0, body._head_h, 0)
	if body._skel and body._bones.has("Head"):
		head = body._skel.global_transform * body._skel.get_bone_global_pose(body._bones["Head"]).origin
	_mode = "main"
	DialogueMenu.open(self, by, title, _main_lines(), _on_pick, Transform3D(Basis.looking_at(head - eye, Vector3.UP), eye))
	body.set_meta("in_talk", true)
	set_process(true)
	return ""

func _main_lines() -> Array:
	_opts = (ROLES[role][1] as Array).duplicate()
	if role == "mike":
		_opts.insert(1, [ASK_REPORT, "report_pick"])
		var ghost := get_tree().get_first_node_in_group("ghost_story")
		if ghost and ghost.call("can_report"):
			_opts.insert(2, [ASK_GHOST, "ghost"])
	var lines: Array = []
	for o: Array in _opts:
		lines.append(o[0])
	return lines

func _end() -> void:
	DialogueMenu.close_for(self)
	if body and body.has_meta("in_talk"):
		body.remove_meta("in_talk")
	_player = null
	_mode = "main"
	set_process(false)

func _on_pick(i: int) -> void:
	var menu := get_tree().root.get_node_or_null("DialogueMenu") as DialogueMenu
	if menu == null or not menu.is_open_for(self):
		return
	if _mode == "report":
		_on_report_pick(menu, i)
		return
	var opt: Array = _opts[i]
	Subtitles.show_line(self, "You", str(opt[0]), 3.2)
	var topic := str(opt[1])
	if topic == "report_pick":
		var det := Detention.of(self)
		_report_list = det.reportable() if det else []
		if _report_list.is_empty():
			_reply(REPORT_NONE)
			return
		# Which one: the passengers Kevin has spoken to, by name (or by place, if he never asked it).
		_mode = "report"
		var lines: Array = []
		for r in _report_list:
			lines.append(det.label(r))
		lines.append(NEVER_MIND)
		menu.set_options(lines)
		return
	menu.mark_asked(i)
	if topic == "bye":
		_end()
	var text := _answer(topic)
	get_tree().create_timer(0.9).timeout.connect(func() -> void:
		if is_instance_valid(body):
			body.say(text))

func _on_report_pick(menu: DialogueMenu, i: int) -> void:
	_mode = "main"
	if i >= _report_list.size():
		Subtitles.show_line(self, "You", NEVER_MIND, 2.0)
		menu.set_options(_main_lines())
		return
	var det := Detention.of(self)
	var r = _report_list[i]
	Subtitles.show_line(self, "You", "That one. %s. Something's not right about them." % det.label(r), 3.6)
	var res: Dictionary = det.report(r)
	_reply(str(res.line))
	if res.ok:
		_end()                         # (he's off to fetch them)
	else:
		menu.set_options(_main_lines())

func _reply(text: String) -> void:
	get_tree().create_timer(0.9).timeout.connect(func() -> void:
		if is_instance_valid(body):
			body.say(text))

func _answer(topic: String) -> String:
	match topic:
		"ghost":
			var ghost := get_tree().get_first_node_in_group("ghost_story")
			return str(ghost.call("mike_answer")) if ghost else "..."
		"anomalies":
			return _mike_anomalies()
		"job":
			match role:
				"mike":
					return _pick(MIKE_JOB)
				"police":
					return "%s, station police. I keep the hall and the check. Bags on the tray, through the arch." % title
				_:
					return "%s, military transport office. We watch the line at night. Orders." % title
		"report":
			return _pick(POLICE_REPORT if role == "police" else MILITARY_REPORT)
		"next":
			return _next_line()
		"bye":
			return _pick(MIKE_BYE if role == "mike" else GUARD_BYE)
	return ""

# How many anomalies are aboard (or waiting on the next platform) and where to begin looking.
func _mike_anomalies() -> String:
	var pax := get_tree().root.find_child("Passengers", true, false)
	var found: Array = pax.call("anomalies") if pax and pax.has_method("anomalies") else []
	if found.is_empty():
		return _pick(MIKE_NONE)
	var r = found[_rng.randi_range(0, found.size() - 1)]
	var car: Node = r.car
	var where: String = CAR_WORDS.get(String(car.name), "the platform") if car else "the platform"
	if found.size() == 1:
		return MIKE_ONE % where
	return MIKE_MANY % [found.size(), where]

func _next_line() -> String:
	var ts := get_node_or_null("/root/TrainState")
	if ts == null:
		return "Soon enough."
	var phase := str(ts.get("phase"))
	if role != "mike":
		if phase == "stopped":
			return "This one, standing here. It won't wait long."
		return "The night express. Then nothing till the morning."
	if phase == "stopped" and str(ts.get("station")) != "":
		return "We're standing at %s. We'll be off shortly." % PassengerTalk.nice(str(ts.get("station")))
	var nxt := str(ts.get("next_stop"))
	for st: Dictionary in RouteData.stops():
		if st.name == nxt:
			return "Next stop %s, due %s. If the snow lets us." % [PassengerTalk.nice(nxt), st.time]
	return "End of the line soon."

func _pick(a: Array) -> String:
	return str(a[_rng.randi_range(0, a.size() - 1)])

func _process(_delta: float) -> void:
	if _player == null:
		return
	var menu := get_tree().root.get_node_or_null("DialogueMenu") as DialogueMenu
	if not is_instance_valid(_player) or menu == null or not menu.is_open_for(self) \
			or (_player as Node3D).global_position.distance_to(body.global_position) > REACH:
		_end()
