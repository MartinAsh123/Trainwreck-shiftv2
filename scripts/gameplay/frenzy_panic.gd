class_name FrenzyPanic
extends Node
## The people up on their feet in its way while an anomaly runs through the train (AnomalyFrenzy sets
## `threat`). Nobody sees it coming: when it is on top of them they start, all at once - a jolt back
## from it (TalkingCharacter.fear), hands up, eyes on it - and whoever stands in its way leaps aside,
## to the nearest free spot well off its way, and flattens there while it goes by. A moment later they
## get on with what they were doing (a walker plans its way again from where it ended up). Seated
## passengers are left alone.
## It runs after whatever walks them (process_priority), so the spot it holds them on wins the frame.

const NOTICE := 2.5                        # m: it is on them this near (and coming their way) ...
const BRUSH := 1.3                         # ... or this near at all
const CLEAR := 0.7                         # nearer than this to its way is in its way
const AHEAD := 3.5                         # m of its way ahead looked at
const REACH := 14                          # cells (0.1 m) looked at for a spot to leap to
const SHAKEN := Vector2(0.45, 0.9)         # s it stays put once it has gone by
const CALM := 1.1                          # fear lost a second after that
const FRIGHT := [Passengers.State.ERRAND, Passengers.State.PREPARING, Passengers.State.UNDER_ESCORT,
		Passengers.State.DETAINED]

class Fright:
	var body: TalkingCharacter
	var mover: NpcMover            # its walker, when it may be moved about (else it cowers where it is)
	var public := true             # the passengers' grid
	var brave := 1.0               # how far fear takes it (the guard: not all the way)
	var fear := 0.0
	var delay := 0.0               # the startle, before anything shows
	var hold := 0.0
	var on := false                # it is on them now
	var look := Vector3.ZERO
	var face := false              # "surprised" on
	var frozen := false
	var spot := Vector3.ZERO       # where it is held while frozen
	var from := Vector3.ZERO
	var jump_t := -1.0             # s into a jump aside (-1: not jumping)
	var jump_len := 0.3
	var retry := 0.0
	var resume := false            # was walking somewhere: goes on there afterwards
	var goal := Vector3.ZERO
	var was := ""                  # the walker's state when it was stopped (not walking)

var frenzy: AnomalyFrenzy
var threat: TalkingCharacter
var dodges := 0                    # (for tests) jumps aside so far
var _people := {}                  # TalkingCharacter -> Fright
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	process_priority = 100
	_rng.randomize()

func _live() -> bool:
	return threat != null and is_instance_valid(threat) and threat.is_visible_in_tree()

## Who is frightened now (tests).
func frightened() -> Array:
	return _people.keys()

# ————— who —————

# [body, walker or null, public, brave] of everyone aboard up on their feet.
func _candidates() -> Array:
	var out: Array = []
	var pax := frenzy._pax_() if frenzy else null
	if pax:
		for r in pax.riders():
			var b: TalkingCharacter = r.body
			if r == frenzy._r or r.ghost or not (r.state in FRIGHT) or b == null or not is_instance_valid(b) \
					or b.asleep or b._sit > 0.1 or not b.is_visible_in_tree():
				continue
			var m: NpcMover = null
			if r.state == Passengers.State.ERRAND and r.mover != null and r.errand_t >= 0.0 \
					and r.errand_phase in ["out", "there", "back"] and r.mover.leader == null:
				m = r.mover
			out.append([b, m, true, 1.0])
	var duty := MikeDuty.of(self)
	if duty and duty.mike and is_instance_valid(duty.mike) and duty.mike.is_visible_in_tree() \
			and not duty.mike.asleep and duty.mike.lie < 0.1 and duty.mike._sit < 0.1:
		var m: NpcMover = duty.mover if duty.mover != null and duty.mover.leader == null else null
		out.append([duty.mike, m, false, 0.7])
	return out

# Who it is on now: near it and in its way, or brushing past.
func _notice(way: PackedVector3Array) -> void:
	var at := threat.global_position
	for c: Array in _candidates():
		var b: TalkingCharacter = c[0]
		var d := Vector2(b.global_position.x - at.x, b.global_position.z - at.z).length()
		if d > NOTICE or absf(b.global_position.y - at.y) > 1.0:
			continue
		if d > BRUSH and (way.size() < 2 or _in_way(b.global_position, way) > CLEAR * 1.4):
			continue
		var f: Fright = _people.get(b)
		if f == null:
			f = Fright.new()
			f.body = b
			f.mover = c[1]
			f.public = c[2]
			f.brave = c[3]
			f.delay = _rng.randf_range(0.0, 0.05)
			_people[b] = f
		f.on = true

# ————— what they do —————

func _process(delta: float) -> void:
	var live := _live()
	var way := frenzy.way_ahead(AHEAD) if live and frenzy else PackedVector3Array()
	for f: Fright in _people.values():
		f.on = false
	if live:
		_notice(way)
	for b: TalkingCharacter in _people.keys():
		var f: Fright = _people[b]
		if not is_instance_valid(b) or not b.is_visible_in_tree():
			if is_instance_valid(b):
				_let_go(f)
			_people.erase(b)
			continue
		if _update(f, live, way, delta):
			_let_go(f)
			_people.erase(b)

## Everyone back to themselves at once (the frenzy called off).
func clear() -> void:
	for f: Fright in _people.values():
		if is_instance_valid(f.body):
			_let_go(f)
	_people.clear()

# True once it is over for this one.
func _update(f: Fright, live: bool, way: PackedVector3Array, delta: float) -> bool:
	var b := f.body
	var sees := live and f.on
	if sees:
		f.look = frenzy._head_pos(threat)
	# How frightened, now: all at once (a jolt), and soon over.
	var want := 1.0 if sees else 0.0
	if f.delay > 0.0:
		f.delay -= delta
	elif want >= f.fear:
		f.fear = move_toward(f.fear, want, delta * 16.0)
		f.hold = _rng.randf_range(SHAKEN.x, SHAKEN.y)
	elif f.hold > 0.0:
		f.hold -= delta
	else:
		f.fear = move_toward(f.fear, want, delta * CALM)
	b.fear = f.fear * f.brave
	b.fear_at = f.look
	if f.fear > 0.3 and not f.face:
		f.face = true
		b.set_expression("surprised", 1.0)
	elif f.fear < 0.15 and f.face:
		f.face = false
		b.set_expression("", 0.0)
	# Up on its feet with a walker: stopped where it stands while it is frightened.
	if f.mover != null:
		if not NpcMover.all.has(f.mover):
			f.mover = null                     # (its errand over: whoever walked it is done with it)
			f.frozen = false
		elif f.fear > 0.2 or f.jump_t >= 0.0:
			if not f.frozen:
				f.frozen = true
				f.spot = b.global_position
				f.resume = false
				f.was = ""
			_keep(f)
		elif f.frozen:
			_unfreeze(f)
	if f.frozen:
		# In its way: out of it.
		f.retry -= delta
		if live and f.delay <= 0.0 and f.jump_t < 0.0 and f.retry <= 0.0 and way.size() > 1 \
				and _in_way(b.global_position, way) < CLEAR:
			_dodge(f, way)
		if f.jump_t >= 0.0:
			f.jump_t += delta
			var k := clampf(f.jump_t / f.jump_len, 0.0, 1.0)
			b.global_position = f.from.lerp(f.spot, 1.0 - pow(1.0 - k, 4.0)) + Vector3(0, sin(k * PI) * 0.09, 0)
			if k >= 1.0:
				f.jump_t = -1.0
		else:
			b.global_position = f.spot
		b.walk_speed = 0.0
	# It spins round to face it.
	if b._sit < 0.1 and f.fear > 0.05 and (f.frozen or f.mover == null):
		var v := f.look - b.global_position
		if Vector2(v.x, v.z).length() > 0.1:
			b.rotation.y = lerp_angle(b.rotation.y, atan2(v.x, v.z), clampf(delta * 18.0, 0.0, 1.0))
	return f.fear <= 0.0 and f.delay <= 0.0 and not sees and not f.frozen

# The walker stands still while it is held (whatever it was told meanwhile is kept for afterwards).
func _keep(f: Fright) -> void:
	var m := f.mover
	if m.state == "idle":
		return
	if m.is_walking():
		f.resume = true
		f.goal = m._resume_goal if m.state == "yield" else m.goal
	elif f.was == "":
		f.was = m.state
	m.state = "idle"
	m.body.walk_speed = 0.0

func _unfreeze(f: Fright) -> void:
	f.frozen = false
	f.jump_t = -1.0
	if f.mover == null or not NpcMover.all.has(f.mover):
		return
	if f.resume:
		f.mover.go(f.goal)
	elif f.was != "" and f.mover.state == "idle":
		f.mover.state = f.was

func _let_go(f: Fright) -> void:
	if f.frozen:
		_unfreeze(f)
	f.body.fear = 0.0
	if f.face:
		f.body.set_expression("", 0.0)

# ————— out of its way —————

# How near `p` is to the way it is going (only what is still ahead of it counts).
static func _in_way(p: Vector3, way: PackedVector3Array) -> float:
	var best := INF
	for k in way.size() - 1:
		var a := way[k]
		var b := way[k + 1]
		var ab := Vector2(b.x - a.x, b.z - a.z)
		var ap := Vector2(p.x - a.x, p.z - a.z)
		var t := ap.dot(ab) / maxf(ab.length_squared(), 0.0001)
		if k == 0 and t < 0.0 and ap.length() > 0.5:
			continue                           # (behind it: it has gone by)
		best = minf(best, (ap - ab * clampf(t, 0.0, 1.0)).length())
	return best

func _dodge(f: Fright, way: PackedVector3Array) -> void:
	f.retry = 0.4
	var s := _spot(f, way)
	if s == Vector3.INF:
		if frenzy:
			frenzy._note("%s has nowhere to go" % f.body.name)
		return                                 # nowhere to go: it flattens where it stands
	f.from = f.body.global_position
	f.spot = Vector3(s.x, f.from.y, s.z)
	f.jump_t = 0.0
	f.jump_len = clampf(f.from.distance_to(f.spot) / 5.5, 0.1, 0.22)
	dodges += 1
	if frenzy:
		frenzy._note("%s jumps aside" % f.body.name)

# The nearest free spot well off its way and nobody else's, straight there, not toward it. With
# none (a narrow place), the one farthest off its way within reach, if that is any better than
# where it stands: pressed to the wall or into a seat's leg room as it scrapes by.
func _spot(f: Fright, way: PackedVector3Array) -> Vector3:
	var nav := TrainNav.of(self)
	if nav == null:
		return Vector3.INF
	var me := Vector3(f.body.global_position.x, TrainNav.FLOOR_Y, f.body.global_position.z)
	var to_it := Vector3(threat.global_position.x - me.x, 0, threat.global_position.z - me.z).normalized()
	var others := _standing(f)
	var best := Vector3.INF
	var bs := INF
	var near := Vector3.INF
	var near_clear := _in_way(me, way) + 0.15
	for dx in range(-REACH, REACH + 1):
		for dz in range(-REACH, REACH + 1):
			if dx * dx + dz * dz > REACH * REACH or dx * dx + dz * dz < 4:
				continue
			var c := me + Vector3(dx * 0.1, 0, dz * 0.1)
			if not nav.is_free(c, f.public):
				continue
			var clear := _in_way(c, way)
			var v := c - me
			var score := v.length() - minf(clear, 1.3) * 0.4 + maxf(v.normalized().dot(to_it), 0.0) * 0.6
			var full := clear >= CLEAR + 0.05
			if (full and score >= bs) or (not full and (best != Vector3.INF or clear <= near_clear)):
				continue
			var taken := false
			for o: Vector3 in others:
				if Vector2(o.x - c.x, o.z - c.z).length() < 0.45:
					taken = true
					break
			if taken or not _straight(nav, me, c, f.public):
				continue
			if full:
				bs = score
				best = c
			else:
				near_clear = clear
				near = c
	return best if best != Vector3.INF else near

# Where everyone else stands, or will (the player too).
func _standing(f: Fright) -> Array:
	var out: Array = []
	for g: Fright in _people.values():
		if g != f and g.body._sit < 0.3:
			out.append(g.spot if g.frozen else g.body.global_position)
	for m: NpcMover in NpcMover.all:
		if m.body and is_instance_valid(m.body) and m.body != f.body and m.body._sit < 0.3:
			out.append(m.pos())
	var p := frenzy._player_() if frenzy else null
	if p:
		out.append(p.global_position)
	return out

func _straight(nav: TrainNav, a: Vector3, b: Vector3, public: bool) -> bool:
	var n := int(a.distance_to(b) / 0.08)
	for k in range(2, n + 1):
		if not nav.is_free(a.lerp(b, float(k) / n), public):
			return false
	return true
