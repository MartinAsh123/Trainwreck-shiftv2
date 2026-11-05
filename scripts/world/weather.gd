class_name Weather
extends Node3D
## Sky, light, fog, wind and falling snow for the journey, from TrainState.clock and a weather
## state that wanders between clear frost and blizzard:
##   clear       — stars and moon, sharp moonlight, a few drifting flakes
##   light_snow  — thin cloud, gentle snowfall
##   snow        — overcast, steady snow, visibility a few hundred metres
##   heavy_snow  — dense snow, low visibility, gusty wind
##   blizzard    — driven snow, strong wind, visibility under a hundred metres
## Volumetric fog (outside only: a negative fog volume fills the train) gives the lamps their halo
## in the falling snow; spindrift skims the ground when the wind gets up.
## Changes ease over `blend_time` seconds. `wind` (world, m/s) and `wind_strength` (0..1) are
## read by the smoke, the snow and the sound.

signal state_changed(state: String)

const STATES := {
	"clear":      {"cloud": 0.05, "flake": 0.025, "snow": 0.04, "fall": 0.9, "wind": 2.0, "gust": 1.0, "fog": 0.00035, "moon": 1.0, "vfog": 0.0012, "drift": 0.05},
	"light_snow": {"cloud": 0.55, "flake": 0.03, "snow": 0.3, "fall": 1.0, "wind": 3.5, "gust": 2.0, "fog": 0.0009, "moon": 0.55, "vfog": 0.004, "drift": 0.2},
	"snow":       {"cloud": 0.85, "flake": 0.036, "snow": 0.6, "fall": 1.2, "wind": 5.0, "gust": 3.0, "fog": 0.002, "moon": 0.3, "vfog": 0.009, "drift": 0.4},
	"heavy_snow": {"cloud": 0.97, "flake": 0.045, "snow": 0.85, "fall": 1.4, "wind": 8.0, "gust": 5.0, "fog": 0.0048, "moon": 0.18, "vfog": 0.016, "drift": 0.7},
	"blizzard":   {"cloud": 1.0, "flake": 0.055, "snow": 1.0, "fall": 1.6, "wind": 15.0, "gust": 8.0, "fog": 0.013, "moon": 0.1, "vfog": 0.035, "drift": 1.0},
}
const NEXT := {
	"clear": ["clear", "light_snow", "light_snow"],
	"light_snow": ["clear", "snow", "snow", "light_snow"],
	"snow": ["light_snow", "snow", "heavy_snow", "heavy_snow"],
	"heavy_snow": ["snow", "snow", "blizzard"],
	"blizzard": ["heavy_snow", "heavy_snow", "snow"],
}

@export_enum("clear", "light_snow", "snow", "heavy_snow", "blizzard") var start_state: String = "light_snow"
@export var auto_change: bool = true
@export var min_hold: float = 150.0
@export var max_hold: float = 420.0
@export var blend_time: float = 60.0
@export var max_flakes: int = 26000
@export var max_drift: int = 9000
@export var volumetric: bool = true

var state: String = ""
var wind: Vector3 = Vector3.ZERO
var wind_strength: float = 0.0
var params := {}                  # current (blended) parameters

var _from := {}
var _to := {}
var _blend := 1.0
var _hold := 0.0
var _env: Environment
var _sky_mat: ShaderMaterial
var _moon: DirectionalLight3D
var _snow: GPUParticles3D
var _snow_mat: ShaderMaterial
var _flake_mat: ShaderMaterial
var _drift: GPUParticles3D
var _drift_mat: ShaderMaterial
var _drift_flake: ShaderMaterial
var _shelter: FogVolume
var _wind_t := 0.0
var _gust_t := 0.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	add_to_group("weather")
	_rng.randomize()
	_build_environment()
	_build_snow()
	set_state(start_state, true)

func set_state(s: String, instant := false) -> void:
	if not STATES.has(s):
		return
	state = s
	_from = params.duplicate() if not params.is_empty() else STATES[s].duplicate()
	_to = STATES[s].duplicate()
	_blend = 1.0 if instant else 0.0
	if instant:
		params = _to.duplicate()
	_hold = _rng.randf_range(min_hold, max_hold)
	state_changed.emit(s)

func _build_environment() -> void:
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	_env = Environment.new()
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = preload("res://shaders/world/night_sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.ambient_light_sky_contribution = 0.6
	_env.ambient_light_color = Color(0.25, 0.3, 0.42)
	_env.ambient_light_energy = 1.0
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.tonemap_exposure = 1.8
	_env.tonemap_white = 6.0
	_env.fog_enabled = true
	_env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	_env.fog_light_color = Color(0.11, 0.13, 0.19)
	_env.fog_sun_scatter = 0.05
	_env.fog_sky_affect = 0.35
	_env.fog_aerial_perspective = 0.4
	_env.glow_enabled = true
	_env.glow_intensity = 0.7
	_env.glow_bloom = 0.04
	_env.glow_hdr_threshold = 1.1
	_env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	# Contact shading: corners, the undersides of things and where they meet the ground darken
	# noticeably (also under direct light), so nothing looks pasted on.
	_env.ssao_enabled = true
	_env.ssao_radius = 1.4
	_env.ssao_intensity = 3.2
	_env.ssao_power = 1.8
	_env.ssao_detail = 0.7
	_env.ssao_horizon = 0.06
	_env.ssao_sharpness = 0.98
	_env.ssao_light_affect = 0.3
	_env.ssao_ao_channel_affect = 0.4
	_env.adjustment_enabled = true
	_env.adjustment_saturation = 0.9
	if volumetric:
		_env.volumetric_fog_enabled = true
		_env.volumetric_fog_density = 0.008
		_env.volumetric_fog_albedo = Color(0.8, 0.85, 0.95)
		_env.volumetric_fog_emission = Color(0.0, 0.0, 0.0)
		_env.volumetric_fog_anisotropy = 0.3
		_env.volumetric_fog_length = 90.0
		_env.volumetric_fog_detail_spread = 2.0
		_env.volumetric_fog_ambient_inject = 0.15
		_env.volumetric_fog_sky_affect = 0.0
		_env.volumetric_fog_temporal_reprojection_enabled = true
	we.environment = _env
	add_child(we)
	_moon = DirectionalLight3D.new()
	_moon.name = "Moonlight"
	_moon.light_color = Color(0.62, 0.72, 1.0)
	_moon.shadow_enabled = true
	_moon.directional_shadow_max_distance = 120.0
	# Two cascades: the moon's shadows are soft, and the far ones fade into the snow and fog anyway.
	_moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	_moon.directional_shadow_split_1 = 0.25
	_moon.shadow_blur = 1.5
	add_child(_moon)

func _build_snow() -> void:
	_snow = GPUParticles3D.new()
	_snow.name = "Snowfall"
	_snow.amount = max_flakes
	_snow.lifetime = 600.0
	_snow.explosiveness = 1.0          # the whole field exists at once (positions wrap forever)
	_snow.local_coords = false
	_snow.fixed_fps = 0
	_snow.visibility_aabb = AABB(Vector3(-40, -25, -40), Vector3(80, 50, 80))
	_snow_mat = ShaderMaterial.new()
	_snow_mat.shader = preload("res://shaders/world/snowfall.gdshader")
	_snow.process_material = _snow_mat
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	_flake_mat = ShaderMaterial.new()
	_flake_mat.shader = preload("res://shaders/world/snowflake.gdshader")
	quad.material = _flake_mat
	_snow.draw_pass_1 = quad
	_snow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_snow)
	_snow.emitting = true
	# Spindrift: faint streaks of snow blown along the ground.
	_drift = GPUParticles3D.new()
	_drift.name = "Spindrift"
	_drift.amount = max_drift
	_drift.lifetime = 600.0
	_drift.explosiveness = 1.0
	_drift.local_coords = false
	_drift.visibility_aabb = AABB(Vector3(-35, -4, -35), Vector3(70, 8, 70))
	_drift_mat = ShaderMaterial.new()
	_drift_mat.shader = preload("res://shaders/world/spindrift.gdshader")
	_drift.process_material = _drift_mat
	var dq := QuadMesh.new()
	dq.size = Vector2(1, 1)
	_drift_flake = ShaderMaterial.new()
	_drift_flake.shader = preload("res://shaders/world/snowflake.gdshader")
	_drift_flake.set_shader_parameter("opacity", 0.16)
	_drift_flake.set_shader_parameter("shutter", 0.05)
	dq.material = _drift_flake
	_drift.draw_pass_1 = dq
	_drift.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_drift)
	_drift.emitting = true

## The volume where no snow may fall (the train), in world space.
func set_shelter(aabb: AABB) -> void:
	_snow_mat.set_shader_parameter("hide_min", aabb.position)
	_snow_mat.set_shader_parameter("hide_max", aabb.end)
	if _drift_mat:
		_drift_mat.set_shader_parameter("hide_min", aabb.position)
		_drift_mat.set_shader_parameter("hide_max", aabb.end)
	# No volumetric fog inside the train.
	if volumetric:
		if _shelter == null:
			_shelter = FogVolume.new()
			_shelter.name = "TrainFogShelter"
			_shelter.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
			var fm := FogMaterial.new()
			fm.density = -1.0
			fm.edge_fade = 0.05
			_shelter.material = fm
			add_child(_shelter)
		_shelter.size = aabb.size + Vector3(0.2, 0.2, 0.1)
		_shelter.global_position = aabb.get_center()

## A second volume without falling snow (the walk-in station hall nearby; AABB() for none).
func set_shelter_2(aabb: AABB) -> void:
	var lo := aabb.position if aabb.has_volume() else Vector3(1e6, 1e6, 1e6)
	var hi := aabb.end if aabb.has_volume() else Vector3(1e6, 1e6, 1e6)
	_snow_mat.set_shader_parameter("hide2_min", lo)
	_snow_mat.set_shader_parameter("hide2_max", hi)
	if _drift_mat:
		_drift_mat.set_shader_parameter("hide2_min", lo)
		_drift_mat.set_shader_parameter("hide2_max", hi)

func _process(delta: float) -> void:
	# Weather wanders.
	if auto_change:
		_hold -= delta
		if _hold <= 0.0:
			var opts: Array = NEXT[state]
			set_state(opts[_rng.randi() % opts.size()])
	if _blend < 1.0:
		_blend = minf(_blend + delta / blend_time, 1.0)
		var e := _blend * _blend * (3.0 - 2.0 * _blend)
		for k in _to:
			params[k] = lerpf(float(_from.get(k, _to[k])), float(_to[k]), e)
	var ts := get_node_or_null("/root/TrainState")
	var clock := 19.0
	var v := 0.0
	if ts:
		clock = float(ts.get("clock"))
		v = float(ts.get("speed"))
	# Wind: a steady flow across the line (from -Z) with gusts.
	_gust_t += delta
	var gust := (sin(_gust_t * 0.37) * 0.6 + sin(_gust_t * 1.13 + 1.7) * 0.4) * float(params.gust)
	var wspeed := maxf(float(params.wind) + gust, 0.0)
	wind = Vector3(-0.35, 0.0, 1.0).normalized() * wspeed
	wind_strength = clampf(wspeed / 18.0, 0.0, 1.0)
	_wind_t += delta * (1.0 + wspeed * 0.3)
	_update_sky(clock)
	_update_snow(v)

# Sun and moon over a winter evening in central Europe: sunset about 16:20, astronomical night by
# 18:15; the moon (waxing gibbous) rides in the south-east and climbs through the evening.
func _update_sky(clock: float) -> void:
	var sun_alt := deg_to_rad(-(clock - 16.3) * 9.0)          # degrees below the horizon after sunset
	sun_alt = clampf(sun_alt, deg_to_rad(-40.0), deg_to_rad(5.0))
	var sun_az := deg_to_rad(240.0 + (clock - 16.3) * 8.0)
	var sun_dir := Vector3(sin(sun_az) * cos(sun_alt), sin(sun_alt), cos(sun_az) * cos(sun_alt))
	var moon_alt := deg_to_rad(clampf(18.0 + (clock - 18.0) * 7.0, 5.0, 55.0))
	var moon_az := deg_to_rad(120.0 + (clock - 18.0) * 12.0)
	var moon_dir := Vector3(sin(moon_az) * cos(moon_alt), sin(moon_alt), cos(moon_az) * cos(moon_alt))
	var cloud: float = params.cloud
	_sky_mat.set_shader_parameter("sun_dir", sun_dir)
	_sky_mat.set_shader_parameter("moon_dir", moon_dir)
	_sky_mat.set_shader_parameter("cloud", cloud)
	_sky_mat.set_shader_parameter("wind_t", _wind_t)
	# Moonlight: blue-white, through the clouds less and softer.
	_moon.look_at_from_position(Vector3.ZERO, -moon_dir, Vector3.UP if absf(moon_dir.y) < 0.99 else Vector3.FORWARD)
	var dusk := clampf(smoothstep(-0.3, 0.05, sun_dir.y), 0.0, 1.0)
	_moon.light_energy = (0.32 * float(params.moon) + 0.05) * (1.0 - dusk * 0.5)
	_moon.shadow_opacity = lerpf(0.9, 0.35, cloud)
	_env.ambient_light_energy = lerpf(0.55, 0.85, cloud) + dusk * 1.2
	# Fog: thicker in snow; tinted by the sky.
	var fog_col := Color(0.075, 0.09, 0.13).lerp(Color(0.13, 0.14, 0.17), cloud)
	fog_col = fog_col.lerp(Color(0.2, 0.25, 0.38), dusk * 0.6)
	_env.fog_light_color = fog_col
	_env.fog_density = float(params.fog)
	# In thick weather the sky itself is lost in the falling snow.
	_env.fog_sky_affect = lerpf(0.35, 1.0, smoothstep(0.5, 1.0, cloud))
	if volumetric:
		_env.volumetric_fog_density = float(params.get("vfog", 0.01))
		_env.volumetric_fog_sky_affect = smoothstep(0.6, 1.0, cloud) * 0.6

func _update_snow(train_speed: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam:
		_snow.global_position = cam.global_position
	_snow.amount_ratio = float(params.snow)
	_snow_mat.set_shader_parameter("air", Vector3(train_speed, 0, 0) + wind)
	_snow_mat.set_shader_parameter("fall", float(params.fall))
	_snow_mat.set_shader_parameter("size_max", float(params.flake))
	_snow_mat.set_shader_parameter("size_min", float(params.flake) * 0.4)
	_snow_mat.set_shader_parameter("flutter", 0.35 + wind_strength * 0.8)
	var bright := 0.5 + 0.25 * float(params.moon)
	_flake_mat.set_shader_parameter("tint", Color(0.55, 0.6, 0.7) * bright)
	if _drift:
		var cam2 := get_viewport().get_camera_3d()
		if cam2:
			_drift.global_position = cam2.global_position
			# The slab sits on the ground by the line (formation level), whatever the camera height.
			_drift_mat.set_shader_parameter("ground_y", -0.1)
		_drift_mat.set_shader_parameter("air", Vector3(train_speed, 0, 0) + wind * 1.4)
		_drift.amount_ratio = clampf(float(params.get("drift", 0.2)) * (0.3 + wind_strength * 1.2), 0.0, 1.0)
		_drift_flake.set_shader_parameter("tint", Color(0.6, 0.66, 0.78) * bright)
		# Only moving air lifts the snow: in a calm, standing still, there is no drift to see.
		var air_v := (Vector3(train_speed, 0, 0) + wind * 1.4).length()
		_drift_flake.set_shader_parameter("opacity", 0.16 * smoothstep(4.0, 12.0, air_v))
