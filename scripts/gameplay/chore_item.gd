class_name ChoreItem
extends HauntItem
## A thing for the ordinary work that goes in Kevin's toolbar (Inventory): clean linen, the dirty
## bundle stripped off a berth, the waste found on one, the scrubbing brush, the cage key. Built in
## code like the haunting's things, and picked up the same way.

static func make_chore(id: String, text: String) -> ChoreItem:
	var it := ChoreItem.new()
	it.item = id
	it.label = text
	it.name = "Item_" + id
	return it

func _ready() -> void:
	super()
	match item:
		"linen":
			_linen(Color(0.93, 0.92, 0.88))
		"dirty_linen":
			_bundle()
		"waste":
			_waste()
		"brush":
			_brush()
		"key":
			_key()

func interact(_by: Node = null) -> String:
	var inv := Inventory.of(self)
	return inv.take(self) if inv else ""

# Clean sheets and a pillowcase, folded square, a blue stripe at the edge.
func _linen(c: Color) -> void:
	for i in 3:
		var b := BoxMesh.new()
		b.size = Vector3(0.3, 0.035, 0.22)
		_mesh(b, _mat(c.darkened(i * 0.03), 0.95), Vector3(0, 0.018 + i * 0.036, 0), Vector3(0, i * 0.04, 0))
	var s := BoxMesh.new()
	s.size = Vector3(0.302, 0.006, 0.012)
	_mesh(s, _mat(Color(0.3, 0.38, 0.6), 0.9), Vector3(0, 0.09, 0.1))

# The stripped bedding rolled into a bundle: greyish, stained.
func _bundle() -> void:
	var m := _mat(Color(0.68, 0.64, 0.55), 1.0)
	for p in [[Vector3(0, 0.09, 0), 0.13], [Vector3(0.09, 0.07, 0.05), 0.09], [Vector3(-0.08, 0.06, -0.04), 0.1]]:
		var sp := SphereMesh.new()
		sp.radius = p[1]
		sp.height = p[1] * 1.3
		_mesh(sp, m, p[0])

# Dried, cracked, and quite unmistakable.
func _waste() -> void:
	var m := _mat(Color(0.24, 0.15, 0.07), 0.85)
	var parts := [[Vector3(0, 0.018, 0), Vector3(0, 0.3, PI * 0.5), 0.022, 0.09],
			[Vector3(0.045, 0.02, 0.02), Vector3(0.4, -0.5, PI * 0.5), 0.018, 0.07],
			[Vector3(-0.04, 0.016, 0.025), Vector3(0, 0.9, PI * 0.5), 0.016, 0.06]]
	for p in parts:
		var c := CapsuleMesh.new()
		c.radius = p[2]
		c.height = p[3]
		_mesh(c, m, p[0], p[1])

# A scrubbing brush: a wooden back with a grip, stiff fibres under it.
func _brush() -> void:
	var back := BoxMesh.new()
	back.size = Vector3(0.18, 0.025, 0.07)
	_mesh(back, _mat(Color(0.55, 0.36, 0.18), 0.6), Vector3(0, 0.04, 0))
	var grip := BoxMesh.new()
	grip.size = Vector3(0.12, 0.03, 0.035)
	_mesh(grip, _mat(Color(0.5, 0.32, 0.16), 0.6), Vector3(0, 0.067, 0))
	var bristle := BoxMesh.new()
	bristle.size = Vector3(0.17, 0.028, 0.062)
	_mesh(bristle, _mat(Color(0.82, 0.74, 0.55), 1.0), Vector3(0, 0.014, 0))

# The cage key: a long brass key on a ring with a tag.
func _key() -> void:
	var brass := _mat(Color(0.78, 0.6, 0.28), 0.35, 1.0)
	var shaft := CylinderMesh.new()
	shaft.top_radius = 0.004
	shaft.bottom_radius = 0.004
	shaft.height = 0.09
	_mesh(shaft, brass, Vector3(0.0, 0.005, 0), Vector3(0, 0, PI * 0.5))
	var bow := TorusMesh.new()
	bow.inner_radius = 0.012
	bow.outer_radius = 0.02
	_mesh(bow, brass, Vector3(-0.06, 0.005, 0))
	var bit := BoxMesh.new()
	bit.size = Vector3(0.016, 0.006, 0.02)
	_mesh(bit, brass, Vector3(0.038, 0.005, 0.012))
	var tag := BoxMesh.new()
	tag.size = Vector3(0.05, 0.003, 0.03)
	_mesh(tag, _mat(Color(0.75, 0.2, 0.15), 0.8), Vector3(-0.1, 0.003, 0.01))
