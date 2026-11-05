class_name GroundProbe
extends RefCounted
## Height of the ground *as it is drawn*: the near terrain is a mesh sampled every 4 m along the
## line and on Scenery.NEAR_ROWS across it, so between the samples it is flat triangles, not the
## smooth Terrain.height(). Roads, fields and anything laid on the snow use this, so they neither
## float above the drawn ground nor sink into it. Beyond the near rows it falls back to height().

const STEP := 4.0           # matches Scenery's near ground (s resolution)

var terrain: Terrain
var _rows: PackedFloat32Array
var _cache := {}

func _init(t: Terrain = null) -> void:
	terrain = t if t != null else Terrain.new()
	var lim: Array = Scenery.NEAR_ROWS
	_rows = PackedFloat32Array()
	for i in range(lim.size() - 1, -1, -1):
		_rows.append(-float(lim[i]))
	_rows.append(0.0)
	for v in lim:
		_rows.append(float(v))

func _h(s: float, z: float) -> float:
	var key := Vector2(s, z)
	var v = _cache.get(key)
	if v == null:
		v = terrain.height(s, z)
		if _cache.size() > 200000:
			_cache.clear()
		_cache[key] = v
	return v

func height(s: float, z: float) -> float:
	if z <= _rows[0] or z >= _rows[_rows.size() - 1]:
		return terrain.height(s, z)
	var s0 := floorf(s / STEP) * STEP
	var fs := (s - s0) / STEP
	# Row bracket (binary search).
	var lo := 0
	var hi := _rows.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if _rows[mid] <= z:
			lo = mid
		else:
			hi = mid
	var z0 := _rows[lo]
	var z1 := _rows[hi]
	var fz := (z - z0) / maxf(z1 - z0, 1e-4)
	# Same split as the ground mesh: triangles (a, b, c) and (b, d, c) with
	# a = (s0, z0), b = (s0, z1), c = (s0 + STEP, z0), d = (s0 + STEP, z1).
	var ha := _h(s0, z0)
	var hb := _h(s0, z1)
	var hc := _h(s0 + STEP, z0)
	var hd := _h(s0 + STEP, z1)
	if fs + fz <= 1.0:
		return ha + (hc - ha) * fs + (hb - ha) * fz
	return hd + (hb - hd) * (1.0 - fs) + (hc - hd) * (1.0 - fz)

var _ncache := {}

## Ground normal at a grid vertex, exactly as the ground mesh has it (Scenery._ground_mesh).
func grid_normal(s: float, z: float) -> Vector3:
	var key := Vector2(s, z)
	var v = _ncache.get(key)
	if v == null:
		v = terrain.normal(s, z, clampf(absf(z) * 0.02, 0.5, 20.0))
		if _ncache.size() > 100000:
			_ncache.clear()
		_ncache[key] = v
	return v

## The drawn ground's triangles over the route-space box [s_min, s_max] × [z_min, z_max]:
## [[Vector3(s, h, z) a, b, c], ...] (grid vertices, in the ground mesh's own split).
func triangles(s_min: float, s_max: float, z_min: float, z_max: float) -> Array:
	var out: Array = []
	var i0 := int(floor(s_min / STEP))
	var i1 := int(floor(s_max / STEP))
	var j0 := _rows.bsearch(z_min, true) - 1
	var j1 := _rows.bsearch(z_max, true)
	j0 = clampi(j0, 0, _rows.size() - 2)
	j1 = clampi(j1, 1, _rows.size() - 1)
	for i in range(i0, i1 + 1):
		var sa := i * STEP
		var sb := sa + STEP
		for j in range(j0, j1):
			var za := _rows[j]
			var zb := _rows[j + 1]
			var a := Vector3(sa, _h(sa, za), za)
			var b := Vector3(sa, _h(sa, zb), zb)
			var c := Vector3(sb, _h(sb, za), za)
			var d := Vector3(sb, _h(sb, zb), zb)
			out.append([a, b, c])
			out.append([b, d, c])
	return out

## Rows of the drawn ground between z0 and z1 (for laying meshes exactly on its grid).
func rows_between(z0: float, z1: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.append(z0)
	for r in _rows:
		if r > z0 + 0.05 and r < z1 - 0.05:
			out.append(r)
	out.append(z1)
	return out
