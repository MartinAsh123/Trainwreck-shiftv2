class_name RoadNetwork
extends RefCounted
## The country roads of the valley, in route space (s along the line, z across it). Every pair of
## neighbouring settlements (villages, and the towns behind the stations) is joined by a road that
## wanders along beside the railway; when the two lie on opposite sides of the line the road
## crosses it on a level crossing (never near a station). Each road is a single-valued z(s), so
## "is this point on a road?" is cheap (the scenery uses it to keep trees off the roads).
## Inside each settlement a straight street runs along its lane (the one Scenery lines the houses
## up on); the roads start and end at the street ends.
## Traffic keeps to the left, as in Czechoslovakia until 1939.

const WIDTH := 6.0          # carriageway (m)
const SAMPLE := 4.0         # polyline spacing along s (m)
const MIN_Z := 26.0         # roads keep at least this far from the track except at crossings
const STATION_Z := 90.0     # ... and this far near a station (yard, building, platform)
const SWING := 45.0         # length (along s) of the swing over the track on either side
const STREET_MIN_Z := 60.0  # village streets stop short of the line by this much

static var _roads: Array = []          # [{s0, s1, zs, a, b, cross, len, cross_t}]
static var _crossings: Array = []      # [{s, road, angle}]
static var _places: Array = []         # [{s, z, name, size, town, lane, r, ends: [Vector2, Vector2]}]
static var _streets: Array = []        # [{a: Vector2, b: Vector2, w: float, town: bool (a town with a square), place: int}]
static var _squares: Array = []        # [{c: Vector2, size: Vector2 (along, across), angle: float, place: int}]

static func ensure() -> void:
	if not _roads.is_empty():
		return
	var names := ["Bukovina", "Lipová", "Hrádek", "Javorník", "Dubí", "Mlýnice", "Rybníky", "Zahrádky",
			"Ostrov", "Bělá", "Vranov", "Kostelec", "Habry", "Lužany"]
	var places: Array = []
	for i in RouteData.VILLAGES.size():
		var v: Dictionary = RouteData.VILLAGES[i]
		places.append(_place(v.s, v.side * v.off, names[i % names.size()], v.size, 0, 9000 + i, 30.0 + v.size * 7.0))
	for st in RouteData.STATIONS:
		if st.town > 0:
			var z: float = st.side * (Terrain.STATION_FLAT_Z + 30.0 + st.town * 25.0)
			places.append(_place(st.s, z, _title(str(st.name)), st.town * 8, st.town, hash(st.name), 40.0 + st.town * 45.0))
	places.sort_custom(func(a, b): return a.s < b.s)
	_places = places
	for i in places.size():
		var p: Dictionary = places[i]
		var plan: Dictionary = p.plan
		for sd: Array in plan.streets:
			_streets.append({"a": sd[0], "b": sd[1], "w": float(sd[2]), "town": bool(plan.town), "place": i})
		var sq: Array = plan.square
		if not sq.is_empty():
			_squares.append({"c": sq[0], "size": sq[1], "angle": float(sq[2]), "place": i})
	var rng := RandomNumberGenerator.new()
	rng.seed = 1930
	for i in places.size() - 1:
		var a: Dictionary = places[i]
		var b: Dictionary = places[i + 1]
		var ea := _end_toward(a, b.s)
		var eb := _end_toward(b, a.s)
		var s0: float = ea.x
		var s1: float = eb.x
		if s1 - s0 < 400.0:
			continue
		var n := int(ceil((s1 - s0) / SAMPLE))
		var zs := PackedFloat32Array()
		zs.resize(n + 1)
		var same_side := signf(ea.y) == signf(eb.y)
		var sx := -1.0
		var phase := rng.randf() * TAU
		var amp := rng.randf_range(8.0, 22.0)
		var wl := rng.randf_range(500.0, 900.0)
		if not same_side:
			# Cross the line in the middle third, well clear of any station, halfway between two
			# telegraph poles (the pole line is at z = -6.2, a pole every 50 m).
			sx = lerpf(s0, s1, rng.randf_range(0.35, 0.65))
			sx = floorf(sx / Scenery.POLE_PITCH) * Scenery.POLE_PITCH + Scenery.POLE_PITCH * 0.5
			var tries := 0
			while _near_station(sx, 350.0) and tries < 40:
				sx += Scenery.POLE_PITCH
				tries += 1
		for k in n + 1:
			var s := minf(s0 + k * SAMPLE, s1)
			var t := (s - s0) / (s1 - s0)
			var z: float
			if same_side:
				var side := signf(ea.y)
				var base := lerpf(absf(ea.y), absf(eb.y), smoothstep(0.0, 1.0, t))
				# Sag toward the line between the villages, then a gentle meander.
				var mid := minf(base, lerpf(base, MIN_Z + 14.0, sin(PI * t)))
				var zz := mid + amp * sin(s / wl * TAU + phase) * sin(PI * t)
				z = side * maxf(_min_z(s) * minf(1.0, minf(s - s0, s1 - s) / 60.0), zz)
			else:
				# Run beside A's side, swing across at sx (steepest over the track, about 48 degrees),
				# carry on on B's side.
				var near := MIN_Z + 6.0
				var za := maxf(_min_z(s), lerpf(absf(ea.y), near, smoothstep(s0, sx - 140.0, s)))
				var zb := maxf(_min_z(s), lerpf(near, absf(eb.y), smoothstep(sx + 140.0, s1, s)))
				if s < sx:
					z = signf(ea.y) * za * sin(clampf((sx - s) / SWING, 0.0, 1.0) * PI * 0.5)
				else:
					z = signf(eb.y) * zb * sin(clampf((s - sx) / SWING, 0.0, 1.0) * PI * 0.5)
			zs[k] = z
		zs[0] = ea.y
		zs[n] = eb.y
		var r := {"s0": s0, "s1": s1, "zs": zs, "a": a.name, "b": b.name, "cross": sx, "town_a": a.town, "town_b": b.town}
		_measure(r)
		if sx >= 0.0:
			var ang := atan(absf(z_at(r, sx + 1.0) - z_at(r, sx - 1.0)) / 2.0)
			r["cross_t"] = _t_at(r, sx)
			_crossings.append({"s": sx, "road": _roads.size(), "angle": ang})
		_roads.append(r)

static func _place(s: float, z: float, name: String, size: int, town_level: int, seed_v: int, radius: float) -> Dictionary:
	# The same plan Scenery lays the village or town out by (TownPlan): the main street along its
	# lane, trimmed short of the line; the roads start from its ends.
	var v := {"s": s, "z": z, "size": size, "seed": seed_v}
	if town_level > 0:
		v["town"] = town_level
	var plan := TownPlan.plan(v)
	var c: Vector2 = plan.center
	var lane: Vector2 = plan.lane
	var ends: Array = [c - lane * float(plan.ends[0]), c + lane * float(plan.ends[1])]
	return {"s": s, "z": z, "name": name, "size": size, "town": town_level > 0, "lane": lane, "r": radius,
			"ends": ends, "plan": plan}

static func _title(n: String) -> String:
	var parts := n.to_lower().split(" ")
	for i in parts.size():
		parts[i] = parts[i].substr(0, 1).to_upper() + parts[i].substr(1)
	return " ".join(parts)

## The street end of place `p` a road toward route position `s_other` should start from.
static func _end_toward(p: Dictionary, s_other: float) -> Vector2:
	var e0: Vector2 = p.ends[0]
	var e1: Vector2 = p.ends[1]
	var first := e0 if absf(e0.x - s_other) < absf(e1.x - s_other) else e1
	var other := e1 if first == e0 else e0
	if absf(first.y) < (STATION_Z if _near_station(first.x, 250.0) else MIN_Z + 14.0):
		return other
	return first

static func _near_station(s: float, dist: float) -> bool:
	for st in RouteData.STATIONS:
		if absf(s - float(st.s)) < dist:
			return true
	return false

## Least distance from the line a road keeps at s (wider past the stations).
static func _min_z(s: float) -> float:
	var k := 0.0
	for st in RouteData.STATIONS:
		k = maxf(k, 1.0 - smoothstep(130.0, 260.0, absf(s - float(st.s))))
	return lerpf(MIN_Z, STATION_Z, k)

static func roads() -> Array:
	ensure()
	return _roads

static func crossings() -> Array:
	ensure()
	return _crossings

static func places() -> Array:
	ensure()
	return _places

static func streets() -> Array:
	ensure()
	return _streets

static func squares() -> Array:
	ensure()
	return _squares

## The square's corners (route space), or [] (for decals and the near-road test).
static func square_poly(q: Dictionary) -> PackedVector2Array:
	var u := Vector2.from_angle(float(q.angle))
	var v := Vector2(-u.y, u.x)
	var h: Vector2 = (q.size as Vector2) * 0.5
	var c: Vector2 = q.c
	return PackedVector2Array([c - u * h.x - v * h.y, c + u * h.x - v * h.y, c + u * h.x + v * h.y, c - u * h.x + v * h.y])

## z of road `r` at s (s inside its span).
static func z_at(r: Dictionary, s: float) -> float:
	var zs: PackedFloat32Array = r.zs
	var f := clampf((s - float(r.s0)) / SAMPLE, 0.0, zs.size() - 1.001)
	var i := int(f)
	return lerpf(zs[i], zs[i + 1], f - i)

## Point on road at distance `t` metres along it from its start (arc length), with the travel
## direction (unit, route space): [Vector2 pos, Vector2 dir].
static func point_at(r: Dictionary, t: float) -> Array:
	var lengths: PackedFloat32Array = r.len
	t = clampf(t, 0.0, lengths[lengths.size() - 1])
	var lo := 0
	var hi := lengths.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if lengths[mid] <= t:
			lo = mid
		else:
			hi = mid
	var seg := maxf(lengths[hi] - lengths[lo], 1e-4)
	var f := (t - lengths[lo]) / seg
	var zs: PackedFloat32Array = r.zs
	var s0: float = r.s0
	var pa := Vector2(s0 + lo * SAMPLE, zs[lo])
	var pb := Vector2(minf(s0 + hi * SAMPLE, r.s1), zs[hi])
	# Smooth the heading across the polyline corners.
	var dir := (pb - pa).normalized()
	if f > 0.5 and hi + 1 < zs.size():
		var pc := Vector2(minf(s0 + (hi + 1) * SAMPLE, r.s1), zs[hi + 1])
		dir = dir.lerp((pc - pb).normalized(), f - 0.5).normalized()
	elif f < 0.5 and lo > 0:
		var pz := Vector2(s0 + (lo - 1) * SAMPLE, zs[lo - 1])
		dir = (pa - pz).normalized().lerp(dir, f + 0.5).normalized()
	return [pa.lerp(pb, f), dir]

static func length_of(r: Dictionary) -> float:
	var lengths: PackedFloat32Array = r.len
	return lengths[lengths.size() - 1]

## Arc length of road `r` at route position s.
static func _t_at(r: Dictionary, s: float) -> float:
	var lengths: PackedFloat32Array = r.len
	var f := clampf((s - float(r.s0)) / SAMPLE, 0.0, lengths.size() - 1.001)
	var i := int(f)
	return lerpf(lengths[i], lengths[i + 1], f - i)

static func _measure(r: Dictionary) -> void:
	var zs: PackedFloat32Array = r.zs
	var out := PackedFloat32Array()
	out.resize(zs.size())
	var acc := 0.0
	out[0] = 0.0
	for i in range(1, zs.size()):
		acc += Vector2(SAMPLE, zs[i] - zs[i - 1]).length()
		out[i] = acc
	r["len"] = out

## True when (s, z) lies on a road or a village street (with `margin` metres either side).
static func near_road(s: float, z: float, margin: float = 2.0) -> bool:
	ensure()
	for r: Dictionary in _roads:
		if s < float(r.s0) or s > float(r.s1):
			continue
		var zr := z_at(r, s)
		# Steep (crossing) stretches: allow for the road's slant.
		var slope := absf(z_at(r, minf(s + 4.0, r.s1)) - z_at(r, maxf(s - 4.0, r.s0))) / 8.0
		if absf(z - zr) < (WIDTH * 0.5 + margin) * sqrt(1.0 + slope * slope):
			return true
	for st: Dictionary in _streets:
		var a: Vector2 = st.a
		var b: Vector2 = st.b
		if s < minf(a.x, b.x) - 12.0 or s > maxf(a.x, b.x) + 12.0:
			continue
		var p := Vector2(s, z)
		var q := Geometry2D.get_closest_point_to_segment(p, a, b)
		if p.distance_to(q) < float(st.w) * 0.5 + margin:
			return true
	for sq: Dictionary in _squares:
		var c: Vector2 = sq.c
		var u := Vector2.from_angle(float(sq.angle))
		var d := Vector2(s, z) - c
		var h: Vector2 = (sq.size as Vector2) * 0.5
		if absf(d.dot(u)) < h.x + margin and absf(d.dot(Vector2(-u.y, u.x))) < h.y + margin:
			return true
	return false
