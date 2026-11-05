class_name BerthJob
extends Node3D
## A berth in the sleeping car left in a state for the next passenger (a work order of Chores): the
## dirty bedding thrown back on it, sometimes something worse on top. Under the berth's marker. The
## steps, each from the berth itself (E):
##   1. the waste (if any) picked up - it goes in the toolbar, and down a W.C. afterwards
##   2. the dirty bedding stripped - a bundle in the toolbar, for the hamper in the service room
##   3. the stain on the bare mattress scrubbed out with the brush (twice)
##   4. clean linen from the service room shelves laid on: the berth is made
## Leaving and coming back keeps the state; done() once made.

const SCRUBS := 2

var berth := ""                            # "4" (the berth's number)
var waste: ChoreItem
var _dirty: SleepBlanket
var _bare: MeshInstance3D
var _stain: MeshInstance3D
var _made: SleepBlanket
var _spot: HauntSpot
var _scrubbed := 0
var stripped := false
var made := false

static func make(marker: Node3D, with_waste: bool) -> BerthJob:
	var j := BerthJob.new()
	j.name = "BerthJob"
	j.berth = str(marker.get_meta("berth", String(marker.name).trim_prefix("Bed_")))
	marker.add_child(j)
	j._build(with_waste)
	return j

func _build(with_waste: bool) -> void:
	# The bedding slept in and thrown back, gone grey.
	_dirty = SleepBlanket.new()
	_dirty.name = "DirtyBedding"
	_dirty.disturbed = 1.0
	_dirty.fold = 0.35
	add_child(_dirty)
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.6, 0.57, 0.48)
	dm.roughness = 1.0
	dm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_dirty.material_override = dm
	# The bare mattress under it (ticking), with the stain, shown once the bedding is off.
	_bare = MeshInstance3D.new()
	_bare.name = "BareMattress"
	var bx := BoxMesh.new()
	bx.size = Vector3(SleepBlanket.BED_HALF * 2.0 + 0.02, 0.03, 1.66)
	_bare.mesh = bx
	_bare.position = Vector3(0, SleepBlanket.MATTRESS + 0.012, -0.2)
	_bare.material_override = _ticking()
	_bare.visible = false
	add_child(_bare)
	_stain = MeshInstance3D.new()
	_stain.name = "Stain"
	var q := QuadMesh.new()
	q.size = Vector2(0.42, 0.34)
	_stain.mesh = q
	_stain.rotation.x = -PI * 0.5
	_stain.position = Vector3(0.06, SleepBlanket.MATTRESS + 0.029, -0.15)
	_stain.material_override = _stain_mat()
	_stain.visible = false
	add_child(_stain)
	if with_waste:
		waste = ChoreItem.make_chore("waste", "the dried excrement")
		add_child(waste)
		waste.position = Vector3(-0.08, SleepBlanket.MATTRESS + 0.06, -0.25)
		waste.rotation.y = 0.7
	# One pick box over the whole berth: what it offers changes as the job goes on.
	_spot = HauntSpot.make("BerthSpot", Vector3(SleepBlanket.BED_HALF * 2.0, 0.5, 1.8), _prompt, _use)
	_spot.position = Vector3(0, SleepBlanket.MATTRESS + 0.1, -0.15)
	add_child(_spot)

func _waste_on() -> bool:
	return waste != null and is_instance_valid(waste) and waste.visible and not waste.has_meta("home")      # (never picked up yet)

func done() -> bool:
	return made

func _prompt() -> String:
	if made:
		return ""
	if _waste_on():
		return "Something on the sheet - pick it up first"
	if not stripped:
		return "E — Strip the dirty bedding"
	if _scrubbed < SCRUBS:
		return "E — Scrub the stain" if Inventory.carries(self, "brush") else "A stain on the mattress - the scrubbing brush is in the service room"
	return "E — Make up berth %s" % berth if Inventory.carries(self, "linen") else "Clean linen is on the service room shelves"

func _use() -> String:
	var inv := Inventory.of(self)
	if made or inv == null or _waste_on():
		return ""
	if not stripped:
		var bundle := ChoreItem.make_chore("dirty_linen", "the dirty bedding")
		add_child(bundle)
		bundle.global_position = global_position + Vector3(0, SleepBlanket.MATTRESS, 0)
		var msg := inv.take(bundle)
		if msg != "":
			bundle.queue_free()
			return msg
		stripped = true
		_dirty.visible = false
		_bare.visible = true
		_stain.visible = true
		return "Into the hamper with it (service room)"
	if _scrubbed < SCRUBS:
		if not inv.has_item("brush"):
			return ""
		_scrubbed += 1
		(_stain.material_override as StandardMaterial3D).albedo_color.a = 0.8 * (1.0 - float(_scrubbed) / SCRUBS)
		_stain.visible = _scrubbed < SCRUBS
		return "" if _scrubbed >= SCRUBS else "Scrub it again"
	if inv.has_item("linen"):
		inv.consume("linen")
		_bare.visible = false
		_made = SleepBlanket.new()
		_made.name = "CleanBedding"
		add_child(_made)
		made = true
		_spot.queue_free()
		return "Berth %s made up" % berth
	return ""

func _ticking() -> StandardMaterial3D:
	var img := Image.create(8, 64, false, Image.FORMAT_RGB8)
	for y in 64:
		var c := Color(0.78, 0.76, 0.7) if (y / 4) % 3 != 0 else Color(0.42, 0.46, 0.55)
		for x in 8:
			img.set_pixel(x, y, c)
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.uv1_scale = Vector3(1, 6, 1)
	m.roughness = 0.95
	return m

func _stain_mat() -> StandardMaterial3D:
	var g := Gradient.new()
	g.set_color(0, Color(0.42, 0.32, 0.12, 1.0))
	g.set_color(1, Color(0.5, 0.4, 0.18, 0.0))
	g.add_point(0.55, Color(0.45, 0.35, 0.14, 0.75))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	var m := StandardMaterial3D.new()
	m.albedo_texture = t
	m.albedo_color = Color(1, 1, 1, 0.8)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 1.0
	return m
