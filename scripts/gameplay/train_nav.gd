class_name TrainNav
extends Node
## Where people can walk inside the train: a 10 cm grid over the cars' floor (train space: the Train
## stands at the origin, the floor at y = 1.4), built once from the real collision - every cell a
## 0.2 m-radius body can stand in without touching a wall, seat or berth. Door leaves are not walls:
## the cells a closed leaf covers remember the door, and a path through them is a path that must
## open it first (TrainNav.doors_on). Exterior doors and doors that are always locked are walls.
## Two grids: the staff's (the whole train but the locomotive) and the passengers' (the sleeping car
## corridor, the two saloons and their gangways, never the crew car, the mail van or a sleeper
## compartment).
##   TrainNav.of(node).path(from, to, public) -> PackedVector3Array (empty when there is no way)
##   TrainNav.of(node).doors_on(path) -> [[index, TrainDoor], ...]

signal built

const CELL := 0.1
const X0 := -61.6                 # mail van's boarding end ...
const X1 := 26.4                  # ... sleeper's tail
const Z0 := -1.5
const Z1 := 1.5
const FLOOR_Y := 1.4
const RADIUS := 0.2
## Passengers keep to x > PUBLIC_X0 (the third saloon's gangway end; beyond is the crew car).
const PUBLIC_X0 := -26.3
## Sleeper compartments (beyond their doors, z > -0.6) are the passengers' only on the way out.
const SLEEPER_X := Vector2(12.2, 22.9)

var ready_ := false
var _staff := AStarGrid2D.new()
var _public := AStarGrid2D.new()
var _door_cells := {}             # Vector2i -> TrainDoor
var _blocked_extra := {}          # Vector2i -> true: cells closed for now (a door that would not open)
var _w := 0
var _h := 0

static func of(n: Node) -> TrainNav:
	return n.get_tree().get_first_node_in_group("train_nav") as TrainNav

func _ready() -> void:
	add_to_group("train_nav")
	_build.call_deferred()

func _build() -> void:
	# Let the cars finish building their collision.
	for i in 60:
		await get_tree().physics_frame
	_w = int(round((X1 - X0) / CELL)) + 1
	_h = int(round((Z1 - Z0) / CELL)) + 1
	for g: AStarGrid2D in [_staff, _public]:
		g.region = Rect2i(0, 0, _w, _h)
		g.cell_size = Vector2(CELL, CELL)
		g.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
		g.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
		g.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
		g.update()
	var t0 := Time.get_ticks_msec()
	if not _load_cache():
		# Every leaf shut while scanning (a door standing open would leave its doorway unmarked).
		var was := {}
		for d in get_tree().get_nodes_in_group("train_door"):
			was[d] = d.is_open()
			d.set_open_immediate(false)
		for i in 2:
			await get_tree().physics_frame
		_scan()
		for d in was:
			if is_instance_valid(d) and was[d]:
				d.set_open_immediate(true)
		_save_cache()
	print("TrainNav: grid ready in %d ms" % (Time.get_ticks_msec() - t0))
	ready_ = true
	built.emit()

# Every cell against the real collision (about 27 000 queries: a few seconds, hence the cache).
func _scan() -> void:
	var space := get_viewport().world_3d.direct_space_state
	var cap := CapsuleShape3D.new()
	cap.radius = RADIUS
	cap.height = 1.3
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.collide_with_areas = false
	# The doorway itself: a cell whose very middle a closed leaf covers (a leaf merely near a cell,
	# like the compartment doors beside the corridor, does not make it a door cell).
	var dot := SphereShape3D.new()
	dot.radius = 0.04
	var qd := PhysicsShapeQueryParameters3D.new()
	qd.shape = dot
	qd.collide_with_areas = false
	var ex: Array[RID] = []
	for p in get_tree().get_nodes_in_group("player"):
		if p is CollisionObject3D:
			ex.append((p as CollisionObject3D).get_rid())
	for b in get_tree().get_nodes_in_group("npc_solid"):
		ex.append((b as CollisionObject3D).get_rid())
	q.exclude = ex
	qd.exclude = ex
	for ix in _w:
		for iz in _h:
			var c := Vector2i(ix, iz)
			var at := Vector3(X0 + ix * CELL, FLOOR_Y + 0.25 + 0.65, Z0 + iz * CELL)
			q.transform = Transform3D(Basis.IDENTITY, at)
			var solid := false
			var near_door := false
			for hit in space.intersect_shape(q, 6):
				var col: Object = hit.collider
				if col is TrainDoor:
					var d := col as TrainDoor
					if (d.lock_while_moving or d.always_locked) and not d.is_in_group("nav_door_always"):
						solid = true
						break
					near_door = true
				elif col is CollisionObject3D and not (col as Node).is_in_group("npc_solid"):
					solid = true
					break
			# Thin CSG walls (the corridor and room walls) do not always register with a shape
			# query from the side: rays out to the body's radius at two heights catch them.
			if not solid:
				solid = _rays_hit(space, at, ex)
			if not solid and near_door:
				qd.transform = Transform3D(Basis.IDENTITY, at)
				for hit in space.intersect_shape(qd, 4):
					if hit.collider is TrainDoor:
						_door_cells[c] = hit.collider
						break
			_set_cell(c, solid)

func _rays_hit(space: PhysicsDirectSpaceState3D, at: Vector3, ex: Array[RID]) -> bool:
	for y in [-0.45, 0.45]:
		var o := at + Vector3(0, y, 0)
		for k in 8:
			var dir := Vector3(cos(k * TAU / 8.0), 0, sin(k * TAU / 8.0))
			var rq := PhysicsRayQueryParameters3D.create(o, o + dir * RADIUS, 0xFFFFFFFF, ex)
			rq.hit_back_faces = true
			var h := space.intersect_ray(rq)
			if not h.is_empty() and not (h.collider is TrainDoor) and not (h.collider as Node).is_in_group("npc_solid"):
				return true
	return false

func _set_cell(c: Vector2i, solid: bool) -> void:
	_staff.set_point_solid(c, solid)
	_public.set_point_solid(c, solid or not _public_cell(c))

# The grid baked to a file beside this script: the cars do not change between runs. A cache from
# another layout (a different number of doors, or doors elsewhere) is ignored and rebuilt.
const CACHE := "res://scripts/gameplay/train_nav_cache.res"

func _door_key() -> Array:
	var train := get_tree().root.find_child("Train", true, false) as Node3D
	var out: Array = []
	if train == null:
		return out
	for d in train.find_children("*", "TrainDoor", true, false):
		out.append([str(train.get_path_to(d)), (d.get_parent() as Node3D).global_position.snapped(Vector3.ONE * 0.01)])
	return out

func _load_cache() -> bool:
	if not ResourceLoader.exists(CACHE):
		return false
	var r := load(CACHE) as Resource
	if r == null or not r.has_meta("cells") or r.get_meta("w") != _w or r.get_meta("h") != _h:
		return false
	var key := _door_key()
	if str(r.get_meta("doors")) != str(key):
		return false
	var train := get_tree().root.find_child("Train", true, false) as Node3D
	var cells: PackedByteArray = r.get_meta("cells")
	var door_idx: PackedInt32Array = r.get_meta("door_idx")
	for ix in _w:
		for iz in _h:
			var i := ix * _h + iz
			var c := Vector2i(ix, iz)
			_set_cell(c, cells[i] == 1)
			if door_idx[i] >= 0:
				_door_cells[c] = train.get_node(NodePath(key[door_idx[i]][0]))
	return true

func _save_cache() -> void:
	var key := _door_key()
	var idx := {}
	var train := get_tree().root.find_child("Train", true, false) as Node3D
	for k in key.size():
		idx[train.get_node(NodePath(key[k][0]))] = k
	var cells := PackedByteArray()
	cells.resize(_w * _h)
	var door_idx := PackedInt32Array()
	door_idx.resize(_w * _h)
	for ix in _w:
		for iz in _h:
			var i := ix * _h + iz
			var c := Vector2i(ix, iz)
			cells[i] = 1 if _staff.is_point_solid(c) else 0
			door_idx[i] = idx.get(_door_cells.get(c), -1)
	var r := Resource.new()
	r.set_meta("w", _w)
	r.set_meta("h", _h)
	r.set_meta("doors", str(key))
	r.set_meta("cells", cells)
	r.set_meta("door_idx", door_idx)
	ResourceSaver.save(r, CACHE)

func _public_cell(c: Vector2i) -> bool:
	var p := cell_pos(c)
	if p.x < PUBLIC_X0:
		return false
	if p.x > SLEEPER_X.x and p.x < SLEEPER_X.y and p.z > -0.6:
		return false
	return true

func cell_of(p: Vector3) -> Vector2i:
	return Vector2i(clampi(int(round((p.x - X0) / CELL)), 0, _w - 1), clampi(int(round((p.z - Z0) / CELL)), 0, _h - 1))

func cell_pos(c: Vector2i) -> Vector3:
	return Vector3(X0 + c.x * CELL, FLOOR_Y, Z0 + c.y * CELL)

func is_free(p: Vector3, public := false) -> bool:
	var g := _public if public else _staff
	var c := cell_of(p)
	return g.is_in_boundsv(c) and not g.is_point_solid(c)

## The free cell nearest to `p` (within `reach` metres), or (-1, -1).
func nearest_free(p: Vector3, public := false, reach := 0.8) -> Vector2i:
	var g := _public if public else _staff
	var c := cell_of(p)
	if not g.is_point_solid(c):
		return c
	var best := Vector2i(-1, -1)
	var bd := INF
	var r := int(ceil(reach / CELL))
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			var n := c + Vector2i(dx, dz)
			if not g.is_in_boundsv(n) or g.is_point_solid(n):
				continue
			var d := Vector2(dx, dz).length_squared()
			if d < bd:
				bd = d
				best = n
	return best

## A walkable way from `from` to `to` (train space, on the floor), straightened where the grid
## allows; empty when there is none. `avoid`: extra cells to keep off this time (a door that
## would not open...).
func path(from: Vector3, to: Vector3, public := false, avoid: Array = []) -> PackedVector3Array:
	if not ready_:
		return PackedVector3Array()
	var g := _public if public else _staff
	var a := nearest_free(from, public)
	var b := nearest_free(to, public)
	if a.x < 0 or b.x < 0:
		return PackedVector3Array()
	for c: Vector2i in avoid:
		if g.is_in_boundsv(c) and c != a and c != b:
			g.set_point_solid(c, true)
	var ids := g.get_id_path(a, b)
	for c: Vector2i in avoid:
		if g.is_in_boundsv(c):
			g.set_point_solid(c, _staff.is_point_solid(c) if g == _staff else (_staff.is_point_solid(c) or not _public_cell(c)))
	if ids.is_empty():
		return PackedVector3Array()
	# String-pulling: keep a point only where the straight line from the last kept one is blocked.
	var out := PackedVector3Array()
	var keep: Array[Vector2i] = [ids[0]]
	var i := 0
	while i < ids.size() - 1:
		var j := ids.size() - 1
		while j > i + 1 and not _line_free(g, ids[i], ids[j]):
			j -= 1
		keep.append(ids[j])
		i = j
	for c in keep:
		out.append(cell_pos(c))
	out[0] = Vector3(from.x, FLOOR_Y, from.z) if is_free(from, public) else out[0]
	out[out.size() - 1] = Vector3(to.x, FLOOR_Y, to.z) if is_free(to, public) else out[out.size() - 1]
	return out

# A straight line between two cells over free cells only (and not across a door's cells unless
# both ends are of the same door, so a door is always a corner of the path).
func _line_free(g: AStarGrid2D, a: Vector2i, b: Vector2i) -> bool:
	var n := maxi(absi(b.x - a.x), absi(b.y - a.y))
	if n == 0:
		return true
	var door: TrainDoor = null
	for k in n + 1:
		var t := float(k) / n
		var c := Vector2i(roundi(lerpf(a.x, b.x, t)), roundi(lerpf(a.y, b.y, t)))
		if g.is_point_solid(c):
			return false
		var d: TrainDoor = _door_cells.get(c)
		if d != null:
			if door != null and door != d:
				return false
			door = d
	return true

## The doors a path goes through: [[index of the path point just before the door, TrainDoor], ...]
## in walking order.
func doors_on(p: PackedVector3Array) -> Array:
	var out: Array = []
	var seen := {}
	for i in p.size() - 1:
		var a := cell_of(p[i])
		var b := cell_of(p[i + 1])
		var n := maxi(maxi(absi(b.x - a.x), absi(b.y - a.y)), 1)
		for k in n + 1:
			var t := float(k) / n
			var c := Vector2i(roundi(lerpf(a.x, b.x, t)), roundi(lerpf(a.y, b.y, t)))
			var d: TrainDoor = _door_cells.get(c)
			if d != null and not seen.has(d):
				seen[d] = true
				out.append([i, d])
	return out

## The cells a door's leaf covers (to keep off when it will not open).
func door_cells(d: TrainDoor) -> Array:
	var out: Array = []
	for c: Vector2i in _door_cells:
		if _door_cells[c] == d:
			out.append(c)
	return out

## Debug: the grid as an image (white free, black solid, red door, grey staff-only).
func debug_image() -> Image:
	var img := Image.create(_w, _h, false, Image.FORMAT_RGB8)
	for ix in _w:
		for iz in _h:
			var c := Vector2i(ix, iz)
			var col := Color.BLACK
			if not _staff.is_point_solid(c):
				col = Color.WHITE if not _public.is_point_solid(c) else Color(0.6, 0.6, 0.6)
				if _door_cells.has(c):
					col = Color.RED
			img.set_pixel(ix, _h - 1 - iz, col)
	return img
