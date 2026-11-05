class_name GhostStory
extends Node3D
## PROVISIONAL PILOT - one ghost, one existing model, three beats. (No ghost canon existed in the
## project; this is a first pass to review, not settled lore.)
##   1. introduction  The manifest lists a passenger in car 1, berth 6 (compartment 3) - a berth
##                    that is kept empty tonight - with a ticket dated 14.01.1931, and a telegram
##                    from dispatch asks about it. Soon after, somewhere in the train, a little
##                    girl giggles.
##   2. escalation    Once Kevin has read the telegram (or later in the evening anyway): the next
##                    time he looks down the sleeping car's corridor, a pale woman stands at its far
##                    end. She is gone when he comes within a few steps, looks away, or after a few
##                    seconds - with the corridor lamps faltering as she goes.
##   3. follow-up     Mike acknowledges a report of her without explaining much; a later telegram
##                    gives one more piece of the 1931 night.
## The apparition is a separate figure (the model is kept off the passengers for the night) with its
## own copies of its materials, faded and cold - nobody else's materials are touched. It has no
## collision and no pick volume, and is freed when it vanishes.

const SLUG := "vintage_woman"
const BERTH := "Bed_3_B"
const GHOST_NAME := "Alžběta Kovářová"

@export var intro_at := 19.0 + 32.0 / 60.0       # game clock
@export var escalate_latest := 20.0 + 10.0 / 60.0
@export var follow_up_after := 8.0               # game minutes after the sighting (or Mike's word)
@export var visible_max := 6.0                   # real seconds she stays at most
@export var vanish_near := 4.0                   # metres

var stage := "dormant"            # dormant -> intro -> waiting -> shown -> seen -> told -> done
var _ts: Node
var _ghost: TalkingCharacter
var _shown_t := 0.0
var _away_t := 0.0
var _fade := 1.0
var _mats: Array = []             # the ghost's own material copies
var _seen_at := 0.0
var _reported := false
var _msg_index := -1

func _ready() -> void:
	add_to_group("ghost_story")
	_ts = get_node_or_null("/root/TrainState")
	var pax := get_tree().root.find_child("Passengers", true, false) as Passengers
	if pax:
		pax.reserve_slug(SLUG)                        # her face is nobody else's tonight
	var bed := get_tree().root.find_child(BERTH, true, false)
	if bed:
		bed.set_meta("reserved", true)                # and her berth stays empty

func _process(delta: float) -> void:
	if _ts == null:
		return
	var clock := float(_ts.get("clock"))
	match stage:
		"dormant":
			if clock >= intro_at and str(_ts.get("phase")) == "running":
				_intro()
		"intro", "waiting":
			var read := _msg_index >= 0 and _msg_index < TerminalData.messages.size() and bool(TerminalData.messages[_msg_index].read)
			if (read or clock >= escalate_latest) and _corridor_view():
				_show()
		"shown":
			_update_shown(delta)
		"seen", "told":
			if clock >= _seen_at + follow_up_after / 60.0:
				_follow_up()

# ————— 1. introduction —————

func _intro() -> void:
	stage = "waiting"
	TerminalData.ensure()
	TerminalData.passengers.append({"name": GHOST_NAME, "car": "CAR 1", "place": "Berth 6", "class": "1st / sleeper",
			"ticket": "GCR-1931-K", "from": "KRÁLOVEC", "to": "KAMENNÝ MOST", "note": "Ticket issued 14.01.1931. With child (no ticket).",
			"checked": false})
	TerminalData.add_message("Dispatch Královec", "Car 1, berth 6",
			"Your manifest shows a passenger in car 1, berth 6. Our booking sheet has berth 6 empty and sealed, as on every run. Please check and confirm. Do not unseal the berth.")
	_msg_index = TerminalData.messages.size() - 1
	TerminalData.log_line("Manifest lists %s in berth 6 (car 1). Booking sheet says empty." % GHOST_NAME)
	var hd := HorrorDirector.of(self)
	if hd:
		hd.trigger("giggle")

# ————— 2. the apparition —————

# Kevin in the sleeping car's corridor, looking along it toward its far end (and nothing between).
func _corridor_view() -> bool:
	var p := _player()
	var cam := get_viewport().get_camera_3d()
	if p == null or cam == null:
		return false
	var pp := p.global_position
	if pp.x < 11.8 or pp.x > 18.6 or pp.z > -0.55:
		return false
	var spot := _spot()
	var to := spot + Vector3(0, 1.5, 0) - cam.global_position
	if to.length() < 5.0 or (-cam.global_basis.z).dot(to.normalized()) < 0.8:
		return false
	# Nobody else standing there.
	for m: NpcMover in NpcMover.all:
		if m.body and is_instance_valid(m.body) and m.pos().distance_to(spot) < 1.2:
			return false
	var q := PhysicsRayQueryParameters3D.create(cam.global_position, spot + Vector3(0, 1.5, 0))
	q.exclude = [(p as CollisionObject3D).get_rid()] if p is CollisionObject3D else []
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty() or (hit.position as Vector3).distance_to(spot + Vector3(0, 1.5, 0)) < 0.4

# The corridor's far end, by the W.C. partition - not a doorway, nobody's way through.
func _spot() -> Vector3:
	return Vector3(22.55, 1.4, -1.0)

func _show() -> void:
	stage = "shown"
	_ghost = TalkingCharacter.new()
	_ghost.name = "Apparition"
	_ghost.model = load("res://assets/characters/%s/%s.glb" % [SLUG, SLUG])
	_ghost.solid = false
	_ghost.look_range = 12.0
	add_child(_ghost)
	_ghost.global_position = _spot()
	var p := _player()
	var f := p.global_position - _spot()
	_ghost.rotation.y = atan2(f.x, f.z)
	_make_pale()
	_shown_t = 0.0
	_away_t = 0.0
	_fade = 0.0
	var hd := HorrorDirector.of(self)
	if hd:
		hd.trigger("flicker", _spot() + Vector3(0, 2.0, 0))
	TerminalData.log_line("[story] apparition shown in the sleeping car corridor.")

func _make_pale() -> void:
	_mats.clear()
	for mi: MeshInstance3D in _ghost.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var src := mi.get_active_material(s) as StandardMaterial3D
			if src == null:
				continue
			var m := src.duplicate() as StandardMaterial3D      # her own copy; the original stays as it is
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
			m.albedo_color = Color(0.72, 0.78, 0.86, 0.0)
			m.emission_enabled = true
			m.emission = Color(0.32, 0.38, 0.48)
			m.emission_energy_multiplier = 0.35
			m.roughness = 1.0
			m.rim_enabled = true
			m.rim = 0.6
			m.rim_tint = 0.2
			mi.set_surface_override_material(s, m)
			if GhostFade.is_mouth_inside(src):
				m.albedo_color.a = 0.0                     # (behind a see-through face: hidden)
				continue
			_mats.append(m)

func _set_alpha(a: float) -> void:
	for m: StandardMaterial3D in _mats:
		m.albedo_color.a = a

func _update_shown(delta: float) -> void:
	if _ghost == null:
		stage = "seen"
		return
	_shown_t += delta
	var p := _player()
	var cam := get_viewport().get_camera_3d()
	var looking := cam != null and cam.is_position_in_frustum(_ghost.global_position + Vector3(0, 1.4, 0))
	_away_t = 0.0 if looking else _away_t + delta
	var go := _shown_t > visible_max or _away_t > 0.6 or (p and p.global_position.distance_to(_ghost.global_position) < vanish_near)
	if go:
		_fade = maxf(_fade - delta / 0.45, 0.0)
	else:
		_fade = minf(_fade + delta / 0.8, 1.0)
	# Not quite steady.
	_set_alpha(_fade * (0.62 + 0.08 * sin(_shown_t * 9.0)))
	if go and _fade <= 0.0:
		_vanish()

func _vanish() -> void:
	if _ghost:
		_ghost.queue_free()                            # (no collider, no pick volume to leave behind)
	_ghost = null
	_mats.clear()
	stage = "seen"
	_seen_at = float(_ts.get("clock"))
	TerminalData.log_line("[story] apparition gone.")

# ————— 3. Mike, and one more telegram —————

## Mike's dialogue offers the sighting once she has been seen and before he has heard of it.
func can_report() -> bool:
	return stage == "seen" and not _reported

func mike_answer() -> String:
	_reported = true
	stage = "told"
	_seen_at = float(_ts.get("clock"))
	TerminalData.log_line("Reported a figure in the sleeping car corridor to the guard.")
	return "Far end, by berth six? ...Write it in the log if you want. And don't go knocking on that door, Kevin. Not tonight."

func _follow_up() -> void:
	stage = "done"
	TerminalData.add_message("Dispatch Sněžná", "Re: car 1, berth 6",
			"Berth 6 has been sealed since the night of 14 January 1931, when a passenger, %s, and her small daughter were reported missing between Sněžná and Vysoké Pole. Neither was found. The child was heard by the crew long after. There is nothing to confirm. Carry on." % GHOST_NAME)
	TerminalData.log_line("[story] dispatch answered about berth 6.")

func _player() -> Node3D:
	var p := get_tree().get_first_node_in_group("player") as Node3D
	return p if p else get_tree().root.find_child("Player", true, false) as Node3D

func _exit_tree() -> void:
	if _ghost and is_instance_valid(_ghost):
		_ghost.queue_free()
