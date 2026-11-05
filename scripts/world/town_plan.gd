class_name TownPlan
extends RefCounted
## The street plan of a village or town, shared by the houses (Scenery) and the streets drawn over
## the ground (WorldLife / RoadNetwork). Deterministic from the place's feature data and safe to call
## from any thread. Route space throughout: a point is Vector2(s, z).
##
##   plan(v) -> {
##     "center": Vector2, "lane": Vector2 (unit, along the main street),
##     "ends": [a_neg, a_pos]      how far the main street runs from the centre each way, already
##                                  stopped short of the line (and of a station yard),
##     "town": bool                 a town with a square (stopping station, town >= 2),
##     "street_w": float            carriageway + pavements between the house fronts,
##     "streets": [[Vector2 a, Vector2 b, float width], ...]   main street first, then the cross street,
##     "square": [Vector2 centre, Vector2 size (along, across), float angle]   or [] for a village,
##     "sq": Vector2(half along, half across), "cross": float (cross street length from the centre,
##     toward -lane_n, 0 if none), "rows_half": float (terraced rows reach this far along the main street)
##   }
## v = Scenery's village feature data: {s, z, size, church, seed, town (station towns only)}.

const STREET_MIN_Z := 60.0       # village streets stop this far from the line
const TOWN_MIN_Z := 70.0         # town streets stop at the station yard

## The lane: the same draw Scenery has always made first from the place's seed.
static func lane_of(seed_v: int) -> Vector2:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	return Vector2.from_angle(rng.randf_range(-0.6, 0.6) + (PI * 0.5 if rng.randf() < 0.4 else 0.0))

## Town layout only where the train stops (halts keep their village look).
static func is_town(v: Dictionary) -> bool:
	if int(v.get("town", 0)) < 2:
		return false
	for st in RouteData.STATIONS:
		if absf(float(st.s) - float(v.s)) < 1.0:
			return bool(st.stop)
	return false

# How far a street from c along dir can run (up to `want`) before it comes within lim of the line.
static func _reach(c: Vector2, dir: Vector2, want: float, lim: float, least: float) -> float:
	var e := c + dir * want
	if absf(e.y) < lim and absf(dir.y) > 0.05 and signf(dir.y) != signf(c.y):
		return maxf(least, (absf(c.y) - lim) / absf(dir.y))
	return want

static func plan(v: Dictionary) -> Dictionary:
	var c := Vector2(float(v.s), float(v.z))
	var lane := lane_of(int(v.seed))
	var lane_n := Vector2(-lane.y, lane.x)
	var size := int(v.size)
	var station_town := int(v.get("town", 0)) > 0
	var lim := TOWN_MIN_Z if station_town else STREET_MIN_Z
	var half := size * 0.25 * 19.0 + 18.0
	var a_neg := _reach(c, -lane, half, lim, 10.0)
	var a_pos := _reach(c, lane, half, lim, 10.0)
	var town := is_town(v)
	var out := {"center": c, "lane": lane, "ends": [a_neg, a_pos], "town": town}
	var w := 10.0 if town else 6.0
	out["street_w"] = w
	var streets: Array = [[c - lane * a_neg, c + lane * a_pos, w]]
	if town:
		var big := int(v.get("town", 2)) >= 3
		var sq := Vector2(22.0, 18.0) if big else Vector2(17.0, 14.0)
		var cross := _reach(c, -lane_n, 62.0 if big else 46.0, lim, 0.0)
		if cross < sq.y + 22.0:
			cross = 0.0
		else:
			streets.append([c - lane_n * sq.y, c - lane_n * cross, w])
		out["sq"] = sq
		out["cross"] = cross
		out["square"] = [c, sq * 2.0, atan2(lane.y, lane.x)]
		out["rows_half"] = minf(92.0 if big else 70.0, minf(a_neg, a_pos) - 18.0)
	else:
		out["sq"] = Vector2.ZERO
		out["cross"] = 0.0
		out["square"] = []
		out["rows_half"] = 0.0
	out["streets"] = streets
	return out
