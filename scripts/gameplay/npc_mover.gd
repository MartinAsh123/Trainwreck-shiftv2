class_name NpcMover
extends RefCounted
## Walks one TalkingCharacter about inside the train along TrainNav paths, the way a person would:
## stands up first if seated, opens the doors on the way (waits for a leaf to finish opening, shuts
## the ones it opened once through, unless someone else is about to use them), keeps a step behind
## whoever walks ahead the same way, gives way in narrow places (the one of lower `priority` steps
## aside into a free spot off the other's path and waits for it to pass) and waits for the player
## standing in the way ("Excuse me") - it never walks through anyone or anything. A door that will
## not open is kept off and the way planned again; with no way left, update() answers "failed".
##   var m := NpcMover.new(body, nav, true)     # true: the passengers' grid
##   m.go(target)                                # train space, on the floor
##   status := m.update(delta)                   # "moving" | "waiting" | "arrived" | "failed"
## An escort: follower.follow(leader) - it walks the leader's own trail a step behind.

const REACH := 0.06            # a path point counts as reached this near
const DOOR_NEAR := 1.0         # starts opening a door this far from it
const GAP := 0.75              # keeps this far behind someone walking ahead
const PASS := 0.62             # two people closer than this, face to face, must sort it out
const PLAYER_GAP := 0.6

static var all: Array = []
static var debug := false     # every mover alive (for giving way)
static var _serial := 0

var body: TalkingCharacter
var nav: TrainNav
var public := true
var speed := 0.85              # m/s (real time; the game clock's 3x does not hurry people)
var priority := 0              # higher keeps the way
var id := 0
var state := "idle"            # idle | moving | door | yield | blocked | arrived | failed
var reason := ""               # why it failed / is blocked
var path := PackedVector3Array()
var idx := 0
var goal := Vector3.ZERO
var heading := Vector3.ZERO
var trail := PackedVector3Array()   # where it walked (an escort's follower uses it)
var leader: NpcMover = null
var follow_dist := 1.1

var _doors: Array = []         # [[path index, TrainDoor], ...] still ahead
var _opened: Array = []        # doors it opened, to shut behind it
var _avoid: Array = []         # cells kept off (doors that would not open)
var _wait := 0.0               # seconds waiting on the current obstacle
var _blocked_total := 0.0
var _excused := false
var _yield_from: NpcMover = null
var _yield_t := 0.0
var _resume_goal := Vector3.ZERO

func _init(b: TalkingCharacter, n: TrainNav, public_ := true) -> void:
	body = b
	nav = n
	public = public_
	_serial += 1
	id = _serial
	all.append(self)

## Done with it (the body is gone or another system takes over): shuts what it opened.
func release() -> void:
	_close_doors(true)
	all.erase(self)
	if body and is_instance_valid(body):
		body.walk_speed = 0.0

func pos() -> Vector3:
	return body.global_position

func is_walking() -> bool:
	return state in ["moving", "door", "yield", "blocked"]

## Plans a way to `to`; false (state "failed") when there is none.
func go(to: Vector3) -> bool:
	leader = null
	goal = to
	_avoid.clear()
	_blocked_total = 0.0
	return _plan()

func follow(l: NpcMover, dist := 1.1) -> void:
	leader = l
	follow_dist = dist
	state = "moving"
	path = PackedVector3Array()

func stop() -> void:
	path = PackedVector3Array()
	leader = null
	state = "idle"
	body.walk_speed = 0.0

func _plan() -> bool:
	path = nav.path(pos(), goal, public, _avoid)
	idx = 1
	_wait = 0.0
	if path.size() < 2:
		if pos().distance_to(goal) < 0.12:
			state = "arrived"
			return true
		state = "failed"
		reason = "no way to %s" % str(goal.snapped(Vector3.ONE * 0.1))
		body.walk_speed = 0.0
		return false
	_doors = nav.doors_on(path)
	state = "moving"
	return true

func update(delta: float) -> String:
	if body == null or not is_instance_valid(body):
		return "failed"
	_close_doors(false)
	if leader != null:
		return _update_follow(delta)
	match state:
		"idle", "arrived":
			body.walk_speed = 0.0
			return state
		"failed":
			body.walk_speed = 0.0
			return "failed"
		"yield":
			return _update_yield(delta)
	# Seated: up on the feet first.
	if body._sit > 0.02:
		body.sit_target = 0.0
		body.walk_speed = 0.0
		return "waiting"
	if idx >= path.size():
		state = "arrived"
		body.walk_speed = 0.0
		return "arrived"
	var to := path[idx]
	# A door ahead: open it and wait for the leaf.
	var d := _door_ahead()
	# A hinged leaf sweeps the floor in front of it: wait clear of its swing (its hinge is the
	# body's origin) until it stands open.
	var hinged := d != null and d.kind == TrainDoor.Kind.HINGE
	var hold := _swing_radius(d) + 0.3 if hinged else 0.55
	var near := (_hinge_dist(d) if hinged else _door_dist(d)) if d != null else INF
	if d != _tries_door:
		_tries_door = d
		_door_tries = 0
	if d != null and near < maxf(DOOR_NEAR, hold + 0.1) and not _door_passable(d):
		if not d.is_open():
			if d.lock_reason() != "":
				_door_tries = 99
			else:
				d.request(true)
				_door_tries += 1
				if debug:
					print("MOVER %s door %s/%s tries %d target %s t %.2f open %s near %.2f" % [body.name, d.get_parent().get_parent().get_parent().get_parent().name, d.get_parent().name, _door_tries, d.get("_target"), float(d.get("_t")), d.is_open(), near])
			if _door_tries > 6 or d.lock_reason() != "":
				# Locked, or it keeps swinging shut on someone: keep off it, find another way.
				_door_tries = 0
				_avoid.append_array(nav.door_cells(d))
				if not _plan():
					state = "failed"
					reason = "the %s would not open (%s, lock '%s', t %.2f)" % [d.door_name, d.get_parent().name, d.lock_reason(), float(d.get("_t"))]
					return "failed"
				body.walk_speed = 0.0
				return "waiting"
			if d.is_open() and not _opened.has(d):
				_opened.append(d)
		if near < hold:
			body.walk_speed = 0.0
			return "waiting"

	# Someone in the way?
	var w := _obstacle(to)
	if w != "":
		body.walk_speed = 0.0
		_wait += delta
		_blocked_total += delta
		if w == "player" and _wait > 2.5 and not _excused:
			_excused = true
			if not body.is_speaking():
				body.say(["Excuse me.", "Pardon me.", "May I get by?"][id % 3], 1.4)
		return "waiting"
	_wait = 0.0
	_excused = false
	_step(to, delta)
	if pos().distance_to(to) < REACH:
		idx += 1
		while not _doors.is_empty() and int(_doors[0][0]) < idx - 1:
			_doors.pop_front()
	return "moving"

func _step(to: Vector3, delta: float) -> void:
	var at := pos()
	var v := to - at
	var left := v.length()
	if left < 0.0001:
		return
	var mv := minf(speed * delta, left)
	body.global_position = at + v / left * mv
	body.walk_speed = speed
	var flat := Vector3(v.x, 0, v.z)
	if flat.length() > 0.02:
		heading = flat.normalized()
		body.rotation.y = lerp_angle(body.rotation.y, atan2(heading.x, heading.z), clampf(delta * 8.0, 0.0, 1.0))
	if trail.is_empty() or trail[trail.size() - 1].distance_to(body.global_position) > 0.12:
		trail.append(body.global_position)
		if trail.size() > 80:
			trail.remove_at(0)

# The next door still to get through (one standing wide open, or already behind, does not count).
func _door_ahead() -> TrainDoor:
	for e: Array in _doors:
		if int(e[0]) >= idx - 1:
			var d: TrainDoor = e[1]
			if is_instance_valid(d) and not _door_passable(d):
				return d
	return null

func _door_dist(d: TrainDoor) -> float:
	var p := (d.get_parent() as Node3D).global_position
	return Vector2(p.x - pos().x, p.z - pos().z).length()

var _door_tries := 0              # times in a row the door ahead would not stay open
var _tries_door: TrainDoor = null

func _hinge_dist(d: TrainDoor) -> float:
	var p := d.global_position
	return Vector2(p.x - pos().x, p.z - pos().z).length()

# How far the leaf reaches from its hinge (its collision box's far edge).
func _swing_radius(d: TrainDoor) -> float:
	var r := 0.7
	for c in d.get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape is BoxShape3D:
			var cs := c as CollisionShape3D
			var half := ((cs.shape as BoxShape3D).size * 0.5)
			r = Vector2(absf(cs.position.x) + half.x, absf(cs.position.z) + half.z).length()
	return r

func _door_passable(d: TrainDoor) -> bool:
	return d.is_open() and float(d.get("_t")) > 0.92

# Shuts the doors it opened once it (and a follower) are through, unless someone is about to use
# them or stands in them.
func _close_doors(all_now: bool) -> void:
	for d: TrainDoor in _opened.duplicate():
		if not is_instance_valid(d):
			_opened.erase(d)
			continue
		var dp := (d.get_parent() as Node3D).global_position
		if not all_now and Vector2(dp.x - pos().x, dp.z - pos().z).length() < 1.3:
			continue
		var busy := false
		for m: NpcMover in all:
			if m != self and m.body and is_instance_valid(m.body) and m.body.global_position.distance_to(dp) < 1.6:
				busy = true
		var p := body._find_player() if body else null
		if p and p.global_position.distance_to(dp) < 1.4:
			busy = true
		if busy and not all_now:
			continue
		_opened.erase(d)
		if not busy:
			d.request(false)

# "player" / "mover" / "" - what stands in the way of the next step.
func _obstacle(to: Vector3) -> String:
	var at := pos()
	var dir := Vector3(to.x - at.x, 0, to.z - at.z)
	if dir.length() < 0.001:
		return ""
	dir = dir.normalized()
	var p := body._find_player()
	if p:
		var rel := Vector3(p.global_position.x - at.x, 0, p.global_position.z - at.z)
		var ahead := rel.dot(dir)
		if ahead > 0.0 and ahead < PLAYER_GAP + 0.3 and (rel - dir * ahead).length() < 0.42 and absf(p.global_position.y - at.y) < 1.2:
			return "player"
	for m: NpcMover in all:
		if m == self or m.leader == self or leader == m or m.body == null or not is_instance_valid(m.body):
			continue
		if not m.body.is_visible_in_tree() or m.body._sit > 0.3 or m.body.asleep:
			continue
		var rel := Vector3(m.pos().x - at.x, 0, m.pos().z - at.z)
		var ahead := rel.dot(dir)
		if ahead <= 0.0 or (rel - dir * ahead).length() > 0.45 or absf(m.pos().y - at.y) > 1.0:
			continue
		var same_way := m.is_walking() and m.heading.dot(dir) > 0.3
		if same_way:
			if ahead < GAP:
				return "mover"
			continue
		if ahead < PASS + 0.35:
			# Face to face, or someone standing in the way: the lower priority gives way.
			if _outranks(m):
				if m.state != "yield":
					m._give_way(self)
				return "mover"
			_give_way(m)
			return "mover"
	return ""

func _outranks(m: NpcMover) -> bool:
	return priority > m.priority or (priority == m.priority and id < m.id)

# Steps aside to the nearest free spot well off the other's way, and waits there.
func _give_way(other: NpcMover) -> void:
	if state == "yield" or state in ["idle", "arrived"] and not body.is_visible_in_tree():
		return
	var spot := _side_spot(other)
	if spot == Vector3.INF:
		return                       # nowhere to go: stays put (the other waits or replans)
	_resume_goal = goal if state != "idle" and state != "arrived" else pos()
	_yield_from = other
	_yield_t = 0.0
	var p := nav.path(pos(), spot, public)
	if p.size() < 2:
		return
	path = p
	idx = 1
	_doors = nav.doors_on(path)
	state = "yield"

func _side_spot(other: NpcMover) -> Vector3:
	var their: PackedVector3Array = PackedVector3Array([other.pos()])
	if other.leader == null:
		for k in range(other.idx, mini(other.idx + 4, other.path.size())):
			their.append(other.path[k])
	var best := Vector3.INF
	var bd := INF
	var me := pos()
	for dx in range(-25, 26, 2):
		for dz in range(-12, 13, 1):
			var c := me + Vector3(dx * 0.1, 0, dz * 0.1)
			if not nav.is_free(c, public):
				continue
			var clear := INF
			for k in their.size():
				var a: Vector3 = their[k]
				var b: Vector3 = their[mini(k + 1, their.size() - 1)]
				clear = minf(clear, _seg_dist(c, a, b))
			if clear < 0.5:
				continue
			var d := me.distance_to(c)
			if d < bd:
				bd = d
				best = c
	return best

static func _seg_dist(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var ap := Vector2(p.x - a.x, p.z - a.z)
	var t := clampf(ap.dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return (ap - ab * t).length()

func _update_yield(delta: float) -> String:
	_yield_t += delta
	if idx < path.size():
		_step(path[idx], delta)
		if pos().distance_to(path[idx]) < REACH:
			idx += 1
		return "waiting"
	body.walk_speed = 0.0
	var o := _yield_from
	var gone := o == null or not all.has(o) or not o.is_walking() or o.pos().distance_to(pos()) > 1.4
	if gone or _yield_t > 12.0:
		goal = _resume_goal
		_plan()
	return "waiting"

# An escorted person: walks the leader's trail, a step behind it.
func _update_follow(delta: float) -> String:
	if body._sit > 0.02:
		body.sit_target = 0.0
		body.walk_speed = 0.0
		return "waiting"
	var tr := leader.trail
	var lp := leader.pos()
	if pos().distance_to(lp) <= follow_dist or tr.is_empty():
		body.walk_speed = 0.0
		var f := Vector3(lp.x - pos().x, 0, lp.z - pos().z)
		if f.length() > 0.05:
			body.rotation.y = lerp_angle(body.rotation.y, atan2(f.x, f.z), clampf(delta * 4.0, 0.0, 1.0))
		return "waiting"
	# The trail point nearest to us that is still ahead (closer to the leader along the trail).
	var best := tr.size() - 1
	var bd := INF
	for k in tr.size():
		var d := tr[k].distance_to(pos())
		if d < bd:
			bd = d
			best = k
	var target := tr[mini(best + 1, tr.size() - 1)]
	if target.distance_to(pos()) < 0.02:
		target = tr[mini(best + 2, tr.size() - 1)]
	var spd := speed * (1.15 if pos().distance_to(lp) > follow_dist + 0.6 else 1.0)
	var keep := speed
	speed = spd
	_step(target, delta)
	speed = keep
	return "moving"
