class_name LifeBuilder
extends RefCounted
## Lays out one stretch (CHUNK m along the line) of the valley's life on a worker thread: the roads,
## village streets, fields (all laid exactly on the drawn ground's triangles), fences, haystacks,
## orchards, hectometre stones, road signs, street lamps, and the level crossings with their deck,
## ramps, St Andrew's crosses, warning signs and barriers (the arms are animated by WorldLife).
## Everything is in chunk space: x = -(s - s0), z = route z.
## The worker only computes plain data (vertex arrays, transforms, texts) into a Spec; instantiate()
## turns it into nodes and render resources on the main thread (nothing touches the rendering
## server from the worker, which can deadlock against the main thread).

const CHUNK := 200.0
const ROAD_W := 3.0 + 1.2          # half width of the road mesh (carriageway + snow fade)
const CROSS_CUT := 7.3             # the road mesh stops this far from the track; the ramp takes over
const DECK_Z := 2.4                # the plank deck covers |z| <= this
const DECK_Y := 0.13               # deck top (rail heads at 0.15)

var probe: GroundProbe
var s0: float

func _init(chunk_s0: float) -> void:
	s0 = chunk_s0
	probe = GroundProbe.new()

class Spec:
	var meshes: Array = []      # [name, arrays, material key, visibility end]
	var props: Array = []       # {key, xf, vis, shadows, margin, labels: [[text, pos, px, col, back, vis]]}
	var mms: Array = []         # [name, prop key, centre, local transforms, visibility end, shadows]
	var lamps: Array = []       # Vector3
	var bars: Array = []        # [crossing index, Transform3D]

func build() -> Spec:
	var root := Spec.new()
	var s1 := s0 + CHUNK
	# Roads.
	var roads := GroundDecal.new(self)
	for ri in RoadNetwork.roads().size():
		var r: Dictionary = RoadNetwork.roads()[ri]
		if float(r.s1) < s0 or float(r.s0) > s1:
			continue
		_road_quads(roads, r, s1)
	_commit(root, roads, "Roads", "road", 1500.0)
	# Streets.
	var town := GroundDecal.new(self)
	var village := GroundDecal.new(self)
	for st: Dictionary in RoadNetwork.streets():
		var a: Vector2 = st.a
		var b: Vector2 = st.b
		var mid := (a.x + b.x) * 0.5
		if mid < s0 or mid >= s1:
			continue
		var dir := (b - a).normalized()
		var n := Vector2(-dir.y, dir.x)
		var hw := float(st.w) * 0.5 + 1.2            # carriageway (and pavements) + the fade into the snow
		var poly := PackedVector2Array([a - n * hw - dir, b - n * hw + dir, b + n * hw + dir, a + n * hw - dir])
		(town if st.town else village).add(poly, GroundDecal.STREET, [a, n, dir], 0.035)
	# Town squares: cobbles under trodden snow (no wheel ruts: UV.x kept well clear of the lanes).
	var squares := GroundDecal.new(self)
	for sq: Dictionary in RoadNetwork.squares():
		var c: Vector2 = sq.c
		if c.x < s0 or c.x >= s1:
			continue
		var u := Vector2.from_angle(float(sq.angle))
		var v := Vector2(-u.y, u.x)
		squares.add(RoadNetwork.square_poly(sq), GroundDecal.STREET, [c - v * 40.0, v, u], 0.04)
	_commit(root, town, "StreetsTown", "street_town", 1200.0)
	_commit(root, village, "StreetsVillage", "street_village", 1200.0)
	_commit(root, squares, "Squares", "square", 1200.0)
	# Fields.
	var plough := GroundDecal.new(self)
	var stubble := GroundDecal.new(self)
	for fi in FarmLand.fields().size():
		var f: Dictionary = FarmLand.fields()[fi]
		var c: Vector2 = f.c
		if c.x < s0 or c.x >= s1:
			continue
		var u: Vector2 = f.u
		var v := Vector2(-u.y, u.x)
		var hl: float = float(f.L) * 0.5
		var hw: float = float(f.W) * 0.5
		var poly := PackedVector2Array([c - u * hl - v * hw, c + u * hl - v * hw, c + u * hl + v * hw, c - u * hl + v * hw])
		(stubble if f.stubble else plough).add(poly, GroundDecal.FIELD, [c, u, v, hl, hw], 0.02)
		_field_props(root, f, fi)
	_commit(root, plough, "FieldsPlough", "plough", 1800.0)
	_commit(root, stubble, "FieldsStubble", "stubble", 1800.0)
	for oi in FarmLand.orchards().size():
		var o: Dictionary = FarmLand.orchards()[oi]
		if (o.c as Vector2).x >= s0 and (o.c as Vector2).x < s1:
			_orchard(root, o, oi)
	# Road furniture, village signs and lamps, crossings.
	_furniture(root, s1)
	for ci in RoadNetwork.crossings().size():
		var cr: Dictionary = RoadNetwork.crossings()[ci]
		if float(cr.s) >= s0 and float(cr.s) < s1:
			_crossing(root, ci, cr)
	return root

## Main thread: the nodes for a Spec. Meta "arms" = [[crossing index, arm node], ...].
static func instantiate(spec: Spec) -> Node3D:
	var root := Node3D.new()
	for m: Array in spec.meshes:
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, m[1])
		am.surface_set_material(0, LifeProps.material(m[2]))
		var mi := MeshInstance3D.new()
		mi.name = m[0]
		mi.mesh = am
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = m[3]
		root.add_child(mi)
	for p: Dictionary in spec.props:
		var mi := MeshInstance3D.new()
		mi.name = p.key
		mi.mesh = LifeProps.mesh(p.key)
		mi.transform = p.xf
		mi.visibility_range_end = p.vis
		mi.visibility_range_end_margin = p.margin
		if not p.shadows:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		for l: Array in p.labels:
			var lb := Label3D.new()
			lb.text = l[0]
			lb.font = Buildings._font()
			lb.font_size = 64
			lb.pixel_size = l[2]
			lb.modulate = l[3]
			lb.outline_size = 0
			lb.shaded = true
			lb.double_sided = false
			lb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			lb.visibility_range_end = l[5]
			lb.position = l[1]
			if l[4]:
				lb.rotation.y = PI
			mi.add_child(lb)
	for m: Array in spec.mms:
		var xfs: Array = m[3]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = LifeProps.mesh(m[1])
		mm.instance_count = xfs.size()
		for i in xfs.size():
			mm.set_instance_transform(i, xfs[i])
		var mi := MultiMeshInstance3D.new()
		mi.name = m[0]
		mi.multimesh = mm
		mi.position = m[2]
		mi.visibility_range_end = m[4]
		if not m[5]:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	var lamp_mesh := SceneryMeshes.get_mesh("lamp_post")
	for pos: Vector3 in spec.lamps:
		if lamp_mesh:
			var mi := MeshInstance3D.new()
			mi.name = "StreetLamp"
			mi.mesh = lamp_mesh
			mi.position = pos
			mi.visibility_range_end = 420.0
			root.add_child(mi)
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.78, 0.5)
		l.light_energy = 2.2
		l.omni_range = 15.0
		l.omni_attenuation = 1.3
		l.shadow_enabled = false
		l.distance_fade_enabled = true
		l.distance_fade_begin = 110.0
		l.distance_fade_length = 30.0
		l.position = pos + Vector3(0, 3.7, 0)
		root.add_child(l)
	var arms: Array = []
	for b: Array in spec.bars:
		var bar := Node3D.new()
		bar.name = "Barrier"
		bar.transform = b[1]
		root.add_child(bar)
		var pm := MeshInstance3D.new()
		pm.mesh = LifeProps.mesh("barrier_post")
		pm.visibility_range_end = 500.0
		bar.add_child(pm)
		var arm := MeshInstance3D.new()
		arm.name = "Arm"
		arm.mesh = LifeProps.mesh("barrier_arm")
		arm.position = Vector3(0, 1.0, 0)
		arm.rotation.z = 1.45
		arm.visibility_range_end = 600.0
		bar.add_child(arm)
		arms.append([b[0], arm])
	root.set_meta("arms", arms)
	return root

# ————— decals: polygons laid on the drawn ground —————

class GroundDecal:
	var b: LifeBuilder
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()

	func _init(builder: LifeBuilder) -> void:
		b = builder

	enum { ROAD, STREET, FIELD }

	## Adds convex polygon `poly` (route space): every ground triangle under it, clipped to it.
	## UVs by `kind` from `data`: ROAD [ca, cb, na, nb, la, lb] (a quad between two centre-line
	## samples), STREET [a, n, dir], FIELD [c, u, v, hl, hw] (UV2.x = metres in from the border).
	func add(poly: PackedVector2Array, kind: int, data: Array, lift: float) -> void:
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for p in poly:
			lo = lo.min(p)
			hi = hi.max(p)
		var orient := signf(_area(poly))
		for tri: Array in b.probe.triangles(lo.x, hi.x, lo.y, hi.y):
			var ta: Vector3 = tri[0]
			var tb: Vector3 = tri[1]
			var tc: Vector3 = tri[2]
			var A := Vector2(ta.x, ta.z)
			var B := Vector2(tb.x, tb.z)
			var C := Vector2(tc.x, tc.z)
			# Quick reject on the triangle's box.
			if maxf(A.x, maxf(B.x, C.x)) < lo.x or minf(A.x, minf(B.x, C.x)) > hi.x \
					or maxf(A.y, maxf(B.y, C.y)) < lo.y or minf(A.y, minf(B.y, C.y)) > hi.y:
				continue
			var pts := LifeBuilder.clip(PackedVector2Array([A, B, C]), poly, orient)
			if pts.size() < 3:
				continue
			var na := b.probe.grid_normal(ta.x, ta.z)
			var nb := b.probe.grid_normal(tb.x, tb.z)
			var nc := b.probe.grid_normal(tc.x, tc.z)
			var vs: Array[Vector3] = []
			var ns: Array[Vector3] = []
			for p in pts:
				var w := LifeBuilder.bary(p, A, B, C)
				var h := ta.y * w.x + tb.y * w.y + tc.y * w.z
				vs.append(Vector3(-(p.x - b.s0), h + lift, p.y))
				ns.append((na * w.x + nb * w.y + nc * w.z).normalized())
			for k in range(1, pts.size() - 1):
				var ids := [0, k, k + 1]
				# Same winding as the ground mesh (its geometric normal points down).
				if (vs[k] - vs[0]).cross(vs[k + 1] - vs[0]).y > 0.0:
					ids = [0, k + 1, k]
				for id: int in ids:
					verts.append(vs[id])
					norms.append(ns[id])
					var q: Vector2 = pts[id]
					match kind:
						ROAD:
							var ca: Vector2 = data[0]
							var seg: Vector2 = data[1] - ca
							var u := clampf((q - ca).dot(seg) / maxf(seg.length_squared(), 1e-6), 0.0, 1.0)
							var nn: Vector2 = (data[2] as Vector2).lerp(data[3], u).normalized()
							uvs.append(Vector2((q - ca.lerp(data[1], u)).dot(nn), lerpf(data[4], data[5], u)))
							uv2s.append(Vector2.ZERO)
						STREET:
							var a: Vector2 = data[0]
							uvs.append(Vector2((q - a).dot(data[1]), (q - a).dot(data[2])))
							uv2s.append(Vector2.ZERO)
						FIELD:
							var du: float = (q - data[0]).dot(data[1])
							var dv: float = (q - data[0]).dot(data[2])
							uvs.append(Vector2(du, dv))
							uv2s.append(Vector2(minf(float(data[3]) - absf(du), float(data[4]) - absf(dv)), 0.0))

	static func _area(poly: PackedVector2Array) -> float:
		var a := 0.0
		for i in poly.size():
			var p := poly[i]
			var q := poly[(i + 1) % poly.size()]
			a += p.x * q.y - q.x * p.y
		return a * 0.5

static func bary(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> Vector3:
	var v0 := b - a
	var v1 := c - a
	var v2 := p - a
	var den := v0.x * v1.y - v1.x * v0.y
	if absf(den) < 1e-9:
		return Vector3(1, 0, 0)
	var v := (v2.x * v1.y - v1.x * v2.y) / den
	var w := (v0.x * v2.y - v2.x * v0.y) / den
	return Vector3(1.0 - v - w, v, w)

## Sutherland–Hodgman: `subject` clipped to the convex polygon `clip_poly` (orientation `orient`).
static func clip(subject: PackedVector2Array, clip_poly: PackedVector2Array, orient: float) -> PackedVector2Array:
	var out := subject
	for i in clip_poly.size():
		if out.size() < 3:
			return PackedVector2Array()
		var a := clip_poly[i]
		var e := clip_poly[(i + 1) % clip_poly.size()] - a
		var inp := out
		out = PackedVector2Array()
		for k in inp.size():
			var p := inp[k]
			var q := inp[(k + 1) % inp.size()]
			var dp := e.cross(p - a) * orient
			var dq := e.cross(q - a) * orient
			if dp >= 0.0:
				out.append(p)
			if (dp >= 0.0) != (dq >= 0.0):
				out.append(p + (q - p) * (dp / (dp - dq)))
	return out

## `poly` cut to the half-plane where (p - o)·n >= 0.
static func clip_half(poly: PackedVector2Array, o: Vector2, n: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in poly.size():
		var p := poly[k]
		var q := poly[(k + 1) % poly.size()]
		var dp := (p - o).dot(n)
		var dq := (q - o).dot(n)
		if dp >= 0.0:
			out.append(p)
		if (dp >= 0.0) != (dq >= 0.0):
			out.append(p + (q - p) * (dp / (dp - dq)))
	return out

func _commit(root: Spec, d: GroundDecal, nm: String, mat: String, vis_end: float) -> void:
	if d.verts.is_empty():
		return
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = d.verts
	arr[Mesh.ARRAY_NORMAL] = d.norms
	arr[Mesh.ARRAY_TEX_UV] = d.uvs
	arr[Mesh.ARRAY_TEX_UV2] = d.uv2s
	root.meshes.append([nm, arr, mat, vis_end])

# ————— roads —————

func _road_quads(d: GroundDecal, r: Dictionary, s1: float) -> void:
	var zs: PackedFloat32Array = r.zs
	var lens: PackedFloat32Array = r.len
	var rs0: float = r.s0
	var n := zs.size()
	var k0 := maxi(0, int(ceil((s0 - rs0) / RoadNetwork.SAMPLE)))
	var k1 := mini(n - 2, int(ceil((s1 - rs0) / RoadNetwork.SAMPLE)) - 1)
	var cross: float = r.cross
	for k in range(k0, k1 + 1):
		var ca := _pt(r, k)
		var cb := _pt(r, k + 1)
		var za := absf(ca.y)
		var zb := absf(cb.y)
		var poly: PackedVector2Array
		var na := _normal(r, k)
		var nb := _normal(r, k + 1)
		poly = PackedVector2Array([ca - na * ROAD_W, cb - nb * ROAD_W, cb + nb * ROAD_W, ca + na * ROAD_W])
		if cross >= 0.0 and absf(ca.x - cross) < RoadNetwork.SWING + 10.0:
			if za < CROSS_CUT and zb < CROSS_CUT:
				continue
			# Cut at |z| = CROSS_CUT on the side this quad lies (the ramp starts there).
			var sg := signf(ca.y if za > zb else cb.y)
			poly = clip_half(poly, Vector2(0, sg * CROSS_CUT), Vector2(0, sg))
			if poly.size() < 3:
				continue
		d.add(poly, GroundDecal.ROAD, [ca, cb, na, nb, lens[k], lens[k + 1]], 0.03)

func _pt(r: Dictionary, k: int) -> Vector2:
	var zs: PackedFloat32Array = r.zs
	return Vector2(minf(float(r.s0) + k * RoadNetwork.SAMPLE, r.s1), zs[k])

func _normal(r: Dictionary, k: int) -> Vector2:
	var n := (r.zs as PackedFloat32Array).size()
	var d := (_pt(r, mini(k + 1, n - 1)) - _pt(r, maxi(k - 1, 0))).normalized()
	return Vector2(-d.y, d.x)

# ————— props —————

## Route direction → world direction (world X runs opposite to s).
static func wdir(d: Vector2) -> Vector3:
	return Vector3(-d.x, 0.0, d.y)

## Left of a road user travelling along route direction `d` (traffic keeps left).
static func left_of(d: Vector2) -> Vector2:
	return Vector2(-d.y, d.x)

## Basis whose +Z faces route direction `face` (signs: their readable side), optionally scaled.
static func facing(face: Vector2, scale := 1.0) -> Basis:
	var z := wdir(face).normalized()
	var x := Vector3.UP.cross(z).normalized()
	return Basis(x * scale, Vector3.UP * scale, z * scale)

func local(p: Vector2, y_off := 0.0) -> Vector3:
	return Vector3(-(p.x - s0), probe.height(p.x, p.y) + y_off, p.y)

func _prop(root: Spec, key: String, p: Vector2, face: Vector2, vis_end: float, shadows := false, y_off := -0.05) -> Dictionary:
	if LifeProps.mesh(key) == null:
		return {}
	var d := {"key": key, "xf": Transform3D(facing(face), local(p, y_off)), "vis": vis_end, "shadows": shadows,
			"margin": 0.0, "labels": []}
	root.props.append(d)
	return d

func _label(parent: Dictionary, text: String, pos: Vector3, px: float, col: Color, back := false, vis_end := 80.0) -> void:
	parent.labels.append([text, pos, px, col, back, vis_end])

func _multimesh(root: Spec, nm: String, key: String, xfs: Array, vis_end: float, shadows: bool) -> void:
	if LifeProps.mesh(key) == null or xfs.is_empty():
		return
	# Centred on its instances (culling and visibility ranges measure from the node).
	var c := Vector3.ZERO
	for t: Transform3D in xfs:
		c += t.origin
	c /= xfs.size()
	var rel: Array = []
	for t: Transform3D in xfs:
		rel.append(Transform3D(t.basis, t.origin - c))
	root.mms.append([nm, key, c, rel, vis_end, shadows])

func _field_props(root: Spec, f: Dictionary, fi: int) -> void:
	var c: Vector2 = f.c
	var u: Vector2 = f.u
	var v := Vector2(-u.y, u.x)
	var hl: float = float(f.L) * 0.5
	var hw: float = float(f.W) * 0.5
	if f.fence != "":
		var sg := 1.0 if f.fence == "+v" else -1.0
		var a := c + v * sg * (hw + 1.0) - u * hl
		var n := int(f.L / 3.0)
		var xfs: Array = []
		var rng := RandomNumberGenerator.new()
		rng.seed = fi * 31 + 7
		for k in n:
			if rng.randf() < 0.04:
				continue           # a bay fallen down
			var p := a + u * (k * 3.0)
			var q := a + u * ((k + 1) * 3.0)
			var pa := local(p, -0.05)
			var pb := local(q, -0.05)
			var x := (pb - pa) / 3.0
			var z := x.normalized().cross(Vector3.UP).normalized()
			var y := z.cross(x.normalized())
			xfs.append(Transform3D(Basis(x, y, z), pa))
		_multimesh(root, "Fence_%d" % fi, "fence", xfs, 320.0, false)
	for st: Array in f.stacks:
		var p: Vector2 = st[0]
		var d := _prop(root, st[1], p, Vector2.from_angle(st[2]), 1100.0, true, -0.15)
		if not d.is_empty():
			d.margin = 30.0

func _orchard(root: Spec, o: Dictionary, oi: int) -> void:
	var xfs: Array = []
	for t: Array in o.trees:
		var p: Vector2 = t[0]
		xfs.append(Transform3D(Basis(Vector3.UP, t[1]).scaled(Vector3.ONE * float(t[2])), local(p, -0.1)))
	# Near: full trees with shadows only up close is too fine-grained here; a modest range instead.
	_multimesh(root, "Orchard_%d" % oi, "apple_tree", xfs, 650.0, false)

# Hectometre stones, warning signs, village name boards, finger posts, street lamps.
func _furniture(root: Spec, s1: float) -> void:
	var stones: Array = []
	for r: Dictionary in RoadNetwork.roads():
		if float(r.s1) < s0 or float(r.s0) > s1:
			continue
		var total := RoadNetwork.length_of(r)
		var t := 100.0
		while t < total - 50.0:
			var pd: Array = RoadNetwork.point_at(r, t)
			var p: Vector2 = pd[0]
			if p.x >= s0 and p.x < s1 and absf(p.y) > 12.0:
				var dir: Vector2 = pd[1]
				var q := p - left_of(dir) * (RoadNetwork.WIDTH * 0.5 + 0.7)
				stones.append(Transform3D(facing(dir), local(q, -0.05)))
			t += 100.0
		# Village name boards where the road leaves each settlement, facing traffic coming in.
		for end: int in [0, 1]:
			var te := 22.0 if end == 0 else total - 22.0
			var pd: Array = RoadNetwork.point_at(r, te)
			var p: Vector2 = pd[0]
			if p.x < s0 or p.x >= s1:
				continue
			var dir: Vector2 = pd[1]
			var incoming := -dir if end == 0 else dir         # travel direction of arriving traffic
			var q := p + left_of(incoming) * (RoadNetwork.WIDTH * 0.5 + 1.3)
			var name: String = r.a if end == 0 else r.b
			var sign := _prop(root, "village_sign", q, -incoming, 300.0, true)
			if not sign.is_empty():
				_label(sign, name.to_upper(), Vector3(0, 1.75, 0.03), 0.0045 * minf(1.0, 9.0 / name.length()), Color(0.04, 0.04, 0.05), false, 140.0)
			# Finger post at the street end: one arm toward the next place along this road.
			var pe: Array = RoadNetwork.point_at(r, 6.0 if end == 0 else total - 6.0)
			var pp: Vector2 = pe[0]
			var out_dir := dir if end == 0 else -dir
			var other: String = r.b if end == 0 else r.a
			var km := maxf(1.0, roundf(total / 100.0) / 10.0)
			var post_pos := pp + left_of(out_dir) * (RoadNetwork.WIDTH * 0.5 + 1.6)
			# The post's +X arm points along out_dir: its +Z faces left of it.
			var post := _prop(root, "signpost", post_pos, -left_of(out_dir), 200.0, true)
			if not post.is_empty():
				var txt := "%s  %s km" % [other.to_upper(), String.num(km, 1)]
				_label(post, txt, Vector3(0.66, 2.30, 0.022), 0.0016, Color(0.05, 0.05, 0.06), false, 45.0)
				_label(post, txt, Vector3(0.66, 2.30, -0.022), 0.0016, Color(0.05, 0.05, 0.06), true, 45.0)
				var home: String = r.a if end == 0 else r.b
				_label(post, home.to_upper(), Vector3(-0.66, 1.98, 0.022), 0.0016, Color(0.05, 0.05, 0.06), false, 45.0)
				_label(post, home.to_upper(), Vector3(-0.66, 1.98, -0.022), 0.0016, Color(0.05, 0.05, 0.06), true, 45.0)
			# Crossroads warning ahead of a town.
			if (r.town_a if end == 0 else r.town_b):
				var pw: Array = RoadNetwork.point_at(r, 120.0 if end == 0 else total - 120.0)
				var pwp: Vector2 = pw[0]
				if pwp.x >= s0 and pwp.x < s1:
					_prop(root, "sign_crossroads", pwp + left_of(incoming) * (RoadNetwork.WIDTH * 0.5 + 1.0), -incoming, 220.0, false)
	_multimesh(root, "KmStones", "km_stone", stones, 220.0, false)
	# Street lamps in the towns and bigger villages.
	for st: Dictionary in RoadNetwork.streets():
		var a: Vector2 = st.a
		var b: Vector2 = st.b
		var pl: Dictionary = RoadNetwork.places()[st.place]
		if not st.town and int(pl.size) < 10:
			continue
		var dir := (b - a).normalized()
		var n := Vector2(-dir.y, dir.x)
		var len := a.distance_to(b)
		var t := 12.0
		var k := 0
		var step := 26.0 if st.town else 40.0
		# Town lamps stand on the pavement by the house fronts; village ones beside the lane.
		var off := float(st.w) * 0.5 - 0.6 if st.town else float(st.w) * 0.5 + 1.1
		while t < len - 8.0:
			var p := a + dir * t + n * off * (1.0 if k % 2 == 0 else -1.0)
			if p.x >= s0 and p.x < s1:
				_lamp(root, p)
			t += step
			k += 1

func _lamp(root: Spec, p: Vector2) -> void:
	root.lamps.append(local(p, -0.05))

# ————— level crossings —————

## s on road `r` where it reaches z (|z| <= the swing's reach), on the side of sign(z).
func _s_of_z(r: Dictionary, z: float) -> float:
	var sx: float = r.cross
	var lo: float
	var hi: float
	var a_side := signf(RoadNetwork.z_at(r, sx - RoadNetwork.SWING * 0.5)) == signf(z)
	if a_side:
		lo = sx - RoadNetwork.SWING
		hi = sx
	else:
		lo = sx
		hi = sx + RoadNetwork.SWING
	for i in 30:
		var mid := (lo + hi) * 0.5
		var zm := RoadNetwork.z_at(r, mid)
		# |z| shrinks toward sx on both sides.
		var further := absf(zm) > absf(z)
		if a_side == further:
			lo = mid
		else:
			hi = mid
	return (lo + hi) * 0.5

## Height of the road surface at (s, |z| small) over a crossing: ramps up from the ground at
## CROSS_CUT to the deck.
func crossing_height(s: float, z: float) -> float:
	var az := absf(z)
	if az <= DECK_Z:
		return DECK_Y
	var g := probe.height(s, signf(z) * (CROSS_CUT + 0.2)) + 0.03
	return lerpf(DECK_Y, g, smoothstep(DECK_Z, CROSS_CUT + 0.2, az))

func _crossing(root: Spec, ci: int, cr: Dictionary) -> void:
	var r: Dictionary = RoadNetwork.roads()[cr.road]
	var ang: float = cr.angle
	var sin_a := maxf(sin(ang), 0.35)
	var half_s := (RoadNetwork.WIDTH * 0.5 + 0.4) / sin_a
	var cot_a := cos(ang) / sin_a
	# Ramps: strips across the road along lines of constant z, from the cut to the deck.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for sg: float in [-1.0, 1.0]:
		var rows: Array = []
		for k in 13:
			var z := sg * lerpf(CROSS_CUT, DECK_Z - 0.05, k / 12.0)
			var sc := _s_of_z(r, z)
			var row: Array = []
			for j in 5:
				var off := lerpf(-(ROAD_W) / sin_a, ROAD_W / sin_a, j / 4.0)
				var s := sc + off
				var y := crossing_height(s, z) + 0.01
				row.append([Vector3(-(s - s0), y, z), Vector2(off * sin_a, RoadNetwork._t_at(r, sc))])
			rows.append(row)
		for k in 12:
			for j in 4:
				var q := [rows[k][j], rows[k][j + 1], rows[k + 1][j], rows[k + 1][j + 1]]
				var tri1 := [q[0], q[1], q[2]]
				var tri2 := [q[1], q[3], q[2]]
				for tri: Array in [tri1, tri2]:
					var p0: Vector3 = tri[0][0]
					var p1: Vector3 = tri[1][0]
					var p2: Vector3 = tri[2][0]
					var order := [0, 1, 2] if (p1 - p0).cross(p2 - p0).y < 0.0 else [0, 2, 1]
					for o: int in order:
						st.set_uv(tri[o][1])
						st.set_normal(Vector3.UP)
						st.add_vertex(tri[o][0])
	root.meshes.append(["Ramps", st.commit_to_arrays(), "road", 1500.0])
	# Plank deck parallel to the rails, between them and outside, with flangeways.
	var deck := SurfaceTool.new()
	deck.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bands := [[-DECK_Z, -0.79], [-0.645, 0.645], [0.79, DECK_Z]]
	var sx: float = cr.s
	for band: Array in bands:
		var z := float(band[0])
		while z < float(band[1]) - 0.05:
			var z1 := minf(z + 0.22, float(band[1]))
			var sa := sx + (z + 0.01) * cot_a * _cross_sign(r)
			var sb := sx + (z1 - 0.01) * cot_a * _cross_sign(r)
			_plank(deck, sa, sb, z + 0.01, z1 - 0.01, half_s)
			z = z1
	deck.generate_normals()
	root.meshes.append(["Deck", deck.commit_to_arrays(), "deck", 900.0])
	# Each approach: barrier, St Andrew's cross, a warning triangle well before.
	for sg: float in [-1.0, 1.0]:
		var zb := sg * 8.0
		var sc := _s_of_z(r, zb)
		var t_here := RoadNetwork._t_at(r, sc)
		var pd: Array = RoadNetwork.point_at(r, t_here)
		var dir: Vector2 = pd[1]
		var p := Vector2(sc, RoadNetwork.z_at(r, sc))
		# Travel toward the track from this side.
		var dz := RoadNetwork.z_at(r, sc + 1.0) - RoadNetwork.z_at(r, sc - 1.0)
		var travel := dir if dz * sg < 0.0 else -dir
		var lft := left_of(travel)
		var post_p := p + lft * (RoadNetwork.WIDTH * 0.5 + 0.9)
		# Local +X across the road (toward its far side), +Z along the travel direction.
		var x := wdir(-lft).normalized()
		var zz := x.cross(Vector3.UP)
		root.bars.append([ci, Transform3D(Basis(x, Vector3.UP, zz), local(post_p, -0.05))])
		var cross_p := p + lft * (RoadNetwork.WIDTH * 0.5 + 1.0) - travel * 3.0
		_prop(root, "cross_andrew", cross_p, -travel, 400.0, true)
		var tw := t_here - (150.0 if travel.dot(dir) > 0.0 else -150.0)
		if tw > 20.0 and tw < RoadNetwork.length_of(r) - 20.0:
			var pw: Array = RoadNetwork.point_at(r, tw)
			var wp: Vector2 = pw[0]
			_prop(root, "sign_gate", wp + lft * (RoadNetwork.WIDTH * 0.5 + 1.0), -travel, 260.0, false)

# +1 when the road's z grows with s at the crossing.
func _cross_sign(r: Dictionary) -> float:
	var sx: float = r.cross
	return signf(RoadNetwork.z_at(r, sx + 1.0) - RoadNetwork.z_at(r, sx - 1.0))

func _plank(st: SurfaceTool, sa: float, sb: float, za: float, zb: float, half_s: float) -> void:
	# Parallelogram top (centre line follows the road), 8 cm thick.
	var top := DECK_Y
	var bot := DECK_Y - 0.08
	var p := [Vector3(-(sa - half_s - s0), 0, za), Vector3(-(sa + half_s - s0), 0, za),
			Vector3(-(sb + half_s - s0), 0, zb), Vector3(-(sb - half_s - s0), 0, zb)]
	var t: Array[Vector3] = []
	var b: Array[Vector3] = []
	var c := Vector3.ZERO
	for v: Vector3 in p:
		t.append(Vector3(v.x, top, v.z))
		b.append(Vector3(v.x, bot, v.z))
		c += v * 0.25
	c.y = (top + bot) * 0.5
	_quad(st, t[0], t[1], t[2], t[3], Vector3.UP)
	for i in 4:
		var j := (i + 1) % 4
		var mid := (b[i] + b[j] + t[i] + t[j]) * 0.25
		_quad(st, b[i], b[j], t[j], t[i], mid - c)

func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3) -> void:
	# Front faces wind clockwise seen from outside: geometric (right-hand) normal points inward.
	var n := (b - a).cross(c - a)
	if n.dot(outward) > 0.0:
		for v in [a, c, b, a, d, c]:
			st.add_vertex(v)
	else:
		for v in [a, b, c, a, c, d]:
			st.add_vertex(v)
