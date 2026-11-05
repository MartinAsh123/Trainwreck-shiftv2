class_name LocoSmoke
extends GPUParticles3D
## Exhaust from the locomotive's chimney. Four beats per turn of the driving wheels (two
## cylinders, double-acting): each beat throws a puff high and fast; between beats and at a stand
## the engine only simmers. Emits `beat` for the chuff sound. Placed at the chimney top by Train.

signal beat(strength: float)

const SMOKE := preload("res://shaders/world/smoke.gdshader")
const PUFF := preload("res://shaders/world/smoke_puff.gdshader")
const DRIVER_R := 0.95

var _last_quarter := -1
var _puff := 0.0
var _mat: ShaderMaterial

func _ready() -> void:
	name = "Smoke"
	amount = 420
	lifetime = 7.0
	local_coords = false
	visibility_aabb = AABB(Vector3(-60, -5, -30), Vector3(140, 60, 60))
	_mat = ShaderMaterial.new()
	_mat.shader = SMOKE
	process_material = _mat
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	var dm := ShaderMaterial.new()
	dm.shader = PUFF
	var nt := NoiseTexture2D.new()
	nt.width = 128
	nt.height = 128
	nt.seamless = true
	var fn := FastNoiseLite.new()
	fn.frequency = 0.03
	fn.fractal_octaves = 4
	nt.noise = fn
	dm.set_shader_parameter("noise_tex", nt)
	quad.material = dm
	draw_pass_1 = quad
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	emitting = true

func _process(delta: float) -> void:
	var ts := get_node_or_null("/root/TrainState")
	var v := 0.0
	var d := 0.0
	if ts:
		v = float(ts.get("speed"))
		d = float(ts.get("distance"))
	var weather := get_tree().get_first_node_in_group("weather")
	var wind := Vector3.ZERO
	if weather:
		wind = weather.get("wind")
	# Beats: a quarter turn of the drivers each.
	var quarter := int(floor(d / (TAU * DRIVER_R) * 4.0))
	if quarter != _last_quarter:
		if _last_quarter >= 0 and v > 0.1:
			var strength := clampf(0.55 + v / 30.0, 0.0, 1.0)
			_puff = strength
			beat.emit(strength)
		_last_quarter = quarter
	# Each puff decays quickly; the beat gets lost in a steady stream at speed.
	_puff = maxf(_puff - delta * (6.0 + v * 0.2), 0.0)
	var base := 0.12 if v < 0.1 else clampf(v / 40.0, 0.1, 0.45)
	_mat.set_shader_parameter("puff", maxf(_puff, base))
	_mat.set_shader_parameter("air", Vector3(v, 0, 0) + wind)
	amount_ratio = 0.35 if v < 0.1 else 1.0
