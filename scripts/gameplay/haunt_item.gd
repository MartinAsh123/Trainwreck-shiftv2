class_name HauntItem
extends Node3D
## Something Kevin can pick up for a haunting (a cup of coffee, the evening paper, the plunger...):
## a small model with a pick area (layer 2). E takes it; HauntDirector keeps what he carries, one
## thing at a time, and puts it back where it came from when it has been used or swapped.

const HD := "res://assets/models/hd_props/%s.gltf"

var item := ""                     # "coffee", "newspaper", "plunger", "screwdriver", "usb"
var label := ""
var director: HauntDirector

static func make(id: String, text: String, d: HauntDirector) -> HauntItem:
	var it := HauntItem.new()
	it.item = id
	it.label = text
	it.director = d
	it.name = "Item_" + id
	return it

func _ready() -> void:
	match item:
		"coffee":
			_model("enamel_mug")
			_steam()
		"newspaper":
			_newspaper()
		"plunger":
			_plunger()
		"mop":
			_model("mop_bucket")
		"disk":
			_disk()
		"screwdriver":
			_screwdriver()
		"usb":
			_usb()
	var a := Area3D.new()
	a.name = "Pick"
	a.collision_layer = 2
	a.collision_mask = 0
	a.monitoring = false
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(0.3, 0.75, 0.3) if item in ["plunger", "mop"] else Vector3(0.32, 0.2, 0.32)
	cs.shape = bx
	cs.position.y = bx.size.y * 0.5
	a.add_child(cs)
	add_child(a)

func get_prompt() -> String:
	return "E — Take %s" % label

func interact(_by: Node = null) -> String:
	var inv := Inventory.of(self)                  # (into Kevin's toolbar)
	return inv.take(self) if inv else (director.take(self) if director else "")

func _model(n: String) -> void:
	var path := HD % n
	if ResourceLoader.exists(path):
		add_child((load(path) as PackedScene).instantiate())

func _mesh(m: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	add_child(mi)
	return mi

func _mat(c: Color, rough := 0.7, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m

# A wisp over the cup, so it reads as hot coffee from across the room.
func _steam() -> void:
	var p := CPUParticles3D.new()
	p.amount = 8
	p.lifetime = 1.6
	p.direction = Vector3.UP
	p.spread = 8.0
	p.gravity = Vector3(0, 0.03, 0)
	p.initial_velocity_min = 0.03
	p.initial_velocity_max = 0.06
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.0
	var q := QuadMesh.new()
	q.size = Vector2(0.06, 0.06)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_color = Color(1, 1, 1, 0.22)
	var soft := GradientTexture2D.new()
	soft.fill = GradientTexture2D.FILL_RADIAL
	soft.fill_from = Vector2(0.5, 0.5)
	soft.fill_to = Vector2(1.0, 0.5)
	soft.width = 32
	soft.height = 32
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	soft.gradient = g
	m.albedo_texture = soft
	q.material = m
	p.mesh = q
	p.position.y = 0.1
	add_child(p)

# A folded broadsheet with a masthead.
func _newspaper() -> void:
	var b := BoxMesh.new()
	b.size = Vector3(0.3, 0.012, 0.21)
	_mesh(b, _mat(Color(0.82, 0.8, 0.72), 0.95), Vector3(0, 0.006, 0))
	var head := Label3D.new()
	head.text = "NÁRODNÍ LISTY"
	head.font_size = 34
	head.pixel_size = 0.0006
	head.modulate = Color(0.12, 0.1, 0.09)
	head.outline_size = 0
	head.rotation = Vector3(-PI * 0.5, PI, 0)        # (read from the -Z side)
	head.position = Vector3(0, 0.0135, 0.07)
	head.shaded = true
	add_child(head)
	for i in 5:
		var line := BoxMesh.new()
		line.size = Vector3(0.26, 0.0004, 0.008)
		_mesh(line, _mat(Color(0.3, 0.28, 0.26), 0.95), Vector3(0, 0.0125, 0.04 - i * 0.024))

# Wooden handle on a black rubber cup.
func _plunger() -> void:
	var h := CylinderMesh.new()
	h.top_radius = 0.013
	h.bottom_radius = 0.013
	h.height = 0.55
	_mesh(h, _mat(Color(0.5, 0.33, 0.18), 0.6), Vector3(0, 0.33, 0))
	var c := CylinderMesh.new()
	c.top_radius = 0.035
	c.bottom_radius = 0.075
	c.height = 0.07
	_mesh(c, _mat(Color(0.05, 0.05, 0.05), 0.5), Vector3(0, 0.035, 0))

# A reinstall disk in its paper sleeve.
func _disk() -> void:
	var b := BoxMesh.new()
	b.size = Vector3(0.09, 0.004, 0.094)
	_mesh(b, _mat(Color(0.12, 0.13, 0.17), 0.45), Vector3(0, 0.002, 0))
	var l := BoxMesh.new()
	l.size = Vector3(0.07, 0.0006, 0.042)
	_mesh(l, _mat(Color(0.92, 0.9, 0.82), 0.8), Vector3(0, 0.0043, 0.014))
	var s := BoxMesh.new()
	s.size = Vector3(0.05, 0.0006, 0.024)
	_mesh(s, _mat(Color(0.65, 0.66, 0.68), 0.35, 0.8), Vector3(0, 0.0043, -0.03))

# A screwdriver lying on its side: red wooden handle, steel shank.
func _screwdriver() -> void:
	var h := CylinderMesh.new()
	h.top_radius = 0.014
	h.bottom_radius = 0.016
	h.height = 0.1
	_mesh(h, _mat(Color(0.6, 0.1, 0.06), 0.45), Vector3(-0.05, 0.016, 0), Vector3(0, 0, PI * 0.5))
	var sh := CylinderMesh.new()
	sh.top_radius = 0.0035
	sh.bottom_radius = 0.0035
	sh.height = 0.11
	_mesh(sh, _mat(Color(0.72, 0.73, 0.75), 0.3, 0.9), Vector3(0.055, 0.016, 0), Vector3(0, 0, PI * 0.5))

# A USB stick with a paper label.
func _usb() -> void:
	var b := BoxMesh.new()
	b.size = Vector3(0.055, 0.009, 0.019)
	_mesh(b, _mat(Color(0.1, 0.11, 0.14), 0.5), Vector3(0, 0.0045, 0))
	var c := BoxMesh.new()
	c.size = Vector3(0.013, 0.0045, 0.012)
	_mesh(c, _mat(Color(0.75, 0.76, 0.78), 0.3, 0.9), Vector3(0.034, 0.0045, 0))
	var l := BoxMesh.new()
	l.size = Vector3(0.03, 0.0006, 0.014)
	_mesh(l, _mat(Color(0.93, 0.9, 0.8), 0.8), Vector3(-0.004, 0.0093, 0))
