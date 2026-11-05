class_name GhostFade
extends Node
## A figure giving itself away as a ghost: over a second and a half it pales to the apparition's
## cold, see-through colour (GhostStory's), wavers there a moment, and is gone. Works on its own
## copies of the figure's materials (nobody else who wears the same model changes), then calls
## `done` - whoever started it frees the figure.
##   GhostFade.start(body, func(): ...)
## GhostFade.flash(body) is the same for an instant: it shows what it is, and it is a passenger again.
## GhostFade.appear(body) is pale from the first frame and stays so, wavering, until dismiss(done).

const TINT := Color(0.72, 0.78, 0.86)          # (as GhostStory's apparition)
const GLOW := Color(0.32, 0.38, 0.48)
const GLOW_ENERGY := 0.35
const PALE := 1.4                               # seconds to pale
const HOLD := 1.3                               # seconds wavering
const GO := 0.9                                 # seconds to vanish

var _mats: Array = []                           # [material, its own albedo colour]
var _t := 0.0
var _done: Callable
var _flash := false
var _hold := false                              # (appear) wavering until dismissed
var _worn: Array = []                           # [mesh, surface, what it wore before]

static func start(body: Node3D, done: Callable) -> GhostFade:
	var f := GhostFade.new()
	f.name = "GhostFade"
	f._done = done
	body.add_child(f)
	return f

static func flash(body: Node3D) -> void:
	if body.has_node("GhostFade"):
		return
	var f := GhostFade.new()
	f.name = "GhostFade"
	f._flash = true
	body.add_child(f)

static func appear(body: Node3D) -> GhostFade:
	var f := GhostFade.new()
	f.name = "GhostFade"
	f._hold = true
	f._t = PALE
	body.add_child(f)
	return f

## An appeared figure goes: fades out, then `done`.
func dismiss(done: Callable) -> void:
	_done = done
	_hold = false
	_t = PALE + HOLD

func _ready() -> void:
	for mi: MeshInstance3D in get_parent().find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var src := mi.get_active_material(s) as StandardMaterial3D
			if src == null:
				continue
			var m := src.duplicate() as StandardMaterial3D
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
			m.emission_enabled = true
			m.emission = GLOW
			m.emission_energy_multiplier = 0.0
			m.rim_enabled = true
			m.rim = 0.0
			m.rim_tint = 0.2
			_worn.append([mi, s, mi.get_surface_override_material(s)])
			mi.set_surface_override_material(s, m)
			_mats.append([m, src.albedo_color, is_mouth_inside(src)])

## The talking face's mouth parts (face_rig.py's materials).
static func is_mouth_inside(m: Material) -> bool:
	var n := m.resource_name if m else ""
	return n.contains("mouth_cavity") or n.contains("teeth_") or n.contains("tongue")

func _process(delta: float) -> void:
	if not _hold:
		_t += delta
	else:
		_t = PALE + fmod(_t - PALE + delta, HOLD)
	var pale := smoothstep(0.0, PALE, _t)
	var alpha := lerpf(1.0, 0.62, pale)
	if _t > PALE:
		alpha = 0.62 + 0.07 * sin((_t - PALE) * 11.0) * sin((_t - PALE) * 3.1)
	if _t > PALE + HOLD:
		alpha *= 1.0 - smoothstep(PALE + HOLD, PALE + HOLD + GO, _t)
	if _flash:
		pale = smoothstep(0.0, 0.25, _t) * (1.0 - smoothstep(0.75, 1.1, _t))
		alpha = lerpf(1.0, 0.66, pale)
		if _t >= 1.1:
			for w: Array in _worn:
				if is_instance_valid(w[0]):
					(w[0] as MeshInstance3D).set_surface_override_material(w[1], w[2])
			queue_free()
			return
	for e: Array in _mats:
		var m: StandardMaterial3D = e[0]
		var own: Color = e[1]
		var c := own.lerp(TINT, pale)
		c.a = alpha
		if e[2]:
			# The mouth's inside (teeth, tongue, cavity) would show through a see-through face:
			# it goes before the face pales.
			c.a = 1.0 - pale if _flash else 1.0 - smoothstep(0.0, 0.35, _t)
			m.albedo_color = c
			continue
		m.albedo_color = c
		m.emission_energy_multiplier = GLOW_ENERGY * pale
		m.rim = 0.6 * pale
		m.roughness = lerpf(m.roughness, 1.0, pale)
	if _t >= PALE + HOLD + GO:
		set_process(false)
		if _done.is_valid():
			_done.call()
