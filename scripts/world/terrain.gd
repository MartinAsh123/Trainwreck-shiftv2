class_name Terrain
extends RefCounted
## Ground height along the line, in route coordinates: s = metres along the route, z = metres
## across it (world Z; the track runs along z = 0). Deterministic, so every chunk and every
## building agrees on it, and thread-safe as long as each thread uses its own Terrain.
##   - the track bed is level (FORMATION_Y) for a few metres either side,
##   - gentle snowy fields and wooded hills rise away from it, cut or banked near the line,
##   - mountain ranges stand a kilometre and more off to both sides,
##   - stations and villages sit on flattened ground.

const FORMATION_Y := -0.42       # ground level under the ballast
const BED_HALF := 4.5            # level strip either side of the track
const STATION_FLAT_Z := 70.0     # station yards are levelled this far from the line

var _hills := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _ridge := FastNoiseLite.new()
var _forest := FastNoiseLite.new()
var _villages: Array = []        # [s, z, radius, plateau height]

func _init(seed_value: int = 1930) -> void:
	_hills.seed = seed_value
	_hills.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_hills.frequency = 1.0 / 520.0
	_hills.fractal_type = FastNoiseLite.FRACTAL_FBM
	_hills.fractal_octaves = 4
	_detail.seed = seed_value + 7
	_detail.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_detail.frequency = 1.0 / 60.0
	_detail.fractal_octaves = 2
	_ridge.seed = seed_value + 13
	_ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_ridge.frequency = 1.0 / 1700.0
	_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ridge.fractal_octaves = 5
	_forest.seed = seed_value + 29
	_forest.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_forest.frequency = 1.0 / 340.0
	_forest.fractal_octaves = 3
	for v in RouteData.VILLAGES:
		var z: float = v.side * v.off
		var r: float = 30.0 + v.size * 7.0
		_villages.append([v.s, z, r, natural(v.s, z)])
	for st in RouteData.STATIONS:
		if st.town > 0:
			# The town behind the station building.
			var z2: float = st.side * (STATION_FLAT_Z + 30.0 + st.town * 25.0)
			var r2: float = 40.0 + st.town * 45.0
			_villages.append([st.s, z2, r2, 0.0])

## Unflattened landscape.
func natural(s: float, z: float) -> float:
	var az := absf(z)
	var h := _hills.get_noise_2d(s, z) * lerpf(4.0, 70.0, smoothstep(20.0, 700.0, az))
	h += _detail.get_noise_2d(s, z) * lerpf(0.3, 3.0, smoothstep(10.0, 200.0, az))
	# Mountains: ridged ranges rising from about 900 m out, highest 2–3 km away.
	var m := smoothstep(700.0, 2400.0, az)
	if m > 0.0:
		var r := _ridge.get_noise_2d(s * 0.8, z)
		h += m * (180.0 + 520.0 * maxf(r, 0.0) + 160.0 * r)
	# Valley floor: the line follows a valley, so the ground falls gently toward it.
	h += smoothstep(0.0, 400.0, az) * 6.0
	return h

func height(s: float, z: float) -> float:
	var az := absf(z)
	var h := natural(s, z)
	# Flattened yards and village plateaus.
	var st := RouteData.station_at(s)
	if not st.is_empty():
		var half: float = (RouteData.PLATFORM_LEN if st.stop else RouteData.HALT_PLATFORM_LEN) * 0.5 + 40.0
		var ks := 1.0 - smoothstep(half, half + 60.0, absf(s - st.s))
		var kz := 1.0 - smoothstep(STATION_FLAT_Z, STATION_FLAT_Z + 50.0, az)
		h = lerpf(h, FORMATION_Y, ks * kz)
	for v: Array in _villages:
		var dist := Vector2(s - v[0], z - v[1]).length()
		var r: float = v[2]
		if dist < r * 1.6:
			var plateau: float = v[3]
			h = lerpf(h, plateau, 1.0 - smoothstep(r, r * 1.6, dist))
	# Track bed: level next to the line, banked or cut into the land beyond it.
	var bed := smoothstep(BED_HALF, BED_HALF + 18.0, az)
	return lerpf(FORMATION_Y, h, bed)

func normal(s: float, z: float, e: float = 1.0) -> Vector3:
	var hx := height(s + e, z) - height(s - e, z)
	var hz := height(s, z + e) - height(s, z - e)
	# World X runs opposite to s.
	return Vector3(hx, 2.0 * e, -hz).normalized()

## Inside a village, a town or a station yard (no stray rocks or trees there).
func in_settlement(s: float, z: float) -> bool:
	var st := RouteData.station_at(s)
	if not st.is_empty() and absf(z) < STATION_FLAT_Z + 40.0:
		return true
	for v: Array in _villages:
		if Vector2(s - v[0], z - v[1]).length() < v[2] * 1.3:
			return true
	return false

## 0..1: how wooded the land is here (none on the bed, in yards and villages).
func forest(s: float, z: float) -> float:
	var az := absf(z)
	if az < 12.0:
		return 0.0
	var f := smoothstep(-0.05, 0.35, _forest.get_noise_2d(s, z))
	f *= smoothstep(12.0, 30.0, az)
	var st := RouteData.station_at(s)
	if not st.is_empty() and az < STATION_FLAT_Z + 40.0:
		f *= 0.0
	for v: Array in _villages:
		var dist := Vector2(s - v[0], z - v[1]).length()
		if dist < v[2] * 1.3:
			f *= smoothstep(v[2] * 0.9, v[2] * 1.3, dist)
	# Tree line: thinner and gone high on the mountains.
	var h := natural(s, z)
	f *= 1.0 - smoothstep(260.0, 420.0, h)
	return f
