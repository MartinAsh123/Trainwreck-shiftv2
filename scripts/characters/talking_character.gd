class_name TalkingCharacter
extends Node3D
## A passenger or crew member built by art_source/characters (Tripo body, Mixamo skeleton, a talking
## face of shape keys): stands naturally, breathes, sways with the train, turns the head toward the
## player, blinks, shows expressions and talks: a mumble in its own voice under a subtitle.
##
##   say(text, seconds)       mumbles for as long as the text takes to read (or `seconds`), a stretch
##                            of one of its `mumbles` clips, and shows the text as a subtitle; the
##                            lips follow the sound itself: shut in its pauses and hums, a little open
##                            on its vowels, opening clearly on the loud ones
##   set_expression(name, w)  smile, sad, angry, surprised, suspicious (fades in and out)
##   look_at_target           a Node3D to face (default: the player when near)
##   sit_target, walk_speed   the body: 0 standing .. 1 seated (eases over about a second; sit_now()
##                            snaps), and the speed it is being moved at, which drives a walk cycle -
##                            both posed in code on the Mixamo skeleton, so every character has them
## Shape keys from face_rig.py: viseme_X/A..H, lids_open_L/R (the eyelids: 1 open, 0 shut),
## smile, sad, angry, surprised, suspicious.

signal finished_speaking

const VISEMES := ["viseme_X", "viseme_A", "viseme_B", "viseme_C", "viseme_D", "viseme_E", "viseme_F", "viseme_G", "viseme_H"]
const EXPRESSIONS := ["smile", "sad", "angry", "surprised", "suspicious"]
## Face and body are posed every frame on screen within LOD_NEAR metres of the camera (or when close,
## frightened, crawling, reaching or wearing face_weights), else LOD_HZ times a second.
const LOD_NEAR := 15.0
const LOD_HZ := 8.0
static var lod := true              # (false: every character every frame; for perf comparisons)

## The mouth fit per face mesh (key -> {surface: skin bytes}): station staff are freed with their
## station and loaded again at the next, and the fit is a GDScript pass over the face's vertices.
static var _mouth_fits := {}

@export var model: PackedScene
@export var look_range: float = 4.5            # turns to the player within this distance
@export var arm_spread: float = 11.0           # upper arm, degrees out from hanging straight down
@export var elbow_bend: float = 14.0           # forearm, degrees forward
@export var voice_bus: StringName = &"Master"
@export var speaker_name := ""
@export var mumbles: Array[AudioStream] = []   # long murmured takes in this character's voice
@export var subtitle_range: float = 9.0        # the player reads its lines within this distance
@export var sit_height: float = 0.42           # cushion top above the feet's floor when seated (m)
## A solid upright capsule (layer 1) while the body stands or walks inside the train: the player
## cannot walk through it and a closing door stops and opens again for it (TrainDoor looks for a
## CharacterBody3D). Off while seated or lying down (the seat or berth is solid already) and out on
## a platform (where it would stand in the exterior doors' swing).
@export var solid := true

var look_at_target: Node3D
var sit_target := 0.0               # 0 standing, 1 seated
var asleep := false                 # lying in a berth: no looking round, slow deep breaths
var walk_speed := 0.0               # m/s, set by whatever moves the figure
var _sit := 0.0
var _gait := 0.0
var _phase := 0.0
var _hip_h := 0.95                  # hip joints' height standing
var _hips_rest := Vector3.ZERO      # the Hips bone's rest position
var _arms_stand := {}               # arm bones -> local rotation, standing / seated (hands on the thighs)
var _arms_sit := {}
var _arms_lie := {}                 # lying on the side: forearms folded in front of the chest
var _arms_tuck := {}                # lying: arms along the body, the hands resting on the thighs
## Lying down (0 up .. 1 lying): the arms fold in front of the chest instead of resting on the
## thighs (which, turned on the side, would hold them up in the air). Set by whoever lays it down.
var lie := 0.0
## Lying, arms kept to the body (0 .. 1): straight along the sides, neither spread nor forward - on
## the back "forward" is up and on the side "spread" is up, so either would lift a hand into the air
## while rolling over. Under `lie`.
var tuck := 0.0
## Lying on the side, the legs as a side sleeper has them (0 .. 1): the upper leg forward and down
## onto the lower, the lower one nearly straight - not held a hip's width apart in the air.
## `lie_side`: +1 lying on the left side (the body's +X down), -1 on the right.
var lie_legs := 0.0
var lie_side := 1.0
var _player: Node3D
var _skel: Skeleton3D
var _face: MeshInstance3D
var _shape := {}                    # blend shape name -> index
var _expr_target := {}              # expression -> target weight
var _expr := {}
var _blink_t := 0.0
var _blink_next := 2.0
var _voice: AudioStreamPlayer3D
var _last_clip := -1
var _cur_vis := 0                   # viseme of the syllable being said
var _open := 0.0                    # smoothed vowel (mid band) loudness
var _op_peak := 0.0                 # the voice's recent loudest vowel (slowly decaying)
var _say_t := -1.0
var _say_len := 1.0
var _vis := PackedFloat32Array()    # current viseme weights
var _vis_to := PackedFloat32Array() # this frame's target weights (kept: no allocation per frame)
var _lod_t := 0.0                   # time since the face and body were last posed
var _vis_idle := false              # silent, the mouth at rest
var _bones := {}                    # short name (Head, LeftArm..) -> bone index
var _rest := {}                     # arm bones -> their standing pose (local rotation)
var _head_h := 1.6
var _time := 0.0
var _rng := RandomNumberGenerator.new()
var _level := 0.0                   # smoothed loudness of the line (0..1)
var _bus_name := ""                 # (by name: removing another bus shifts the indices)

func _ready() -> void:
	_rng.randomize()
	if model:
		add_child(model.instantiate())
		# No takes given: the murmured takes beside the model (mumble_1.mp3, mumble_2.mp3 ...).
		if mumbles.is_empty() and model.resource_path != "":
			for k in range(1, 6):
				var p := model.resource_path.get_base_dir().path_join("mumble_%d.mp3" % k)
				if ResourceLoader.exists(p):
					mumbles.append(load(p) as AudioStream)
	_skel = find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D if not find_children("*", "Skeleton3D", true, false).is_empty() else null
	for mi: Node in find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh and m.mesh.get_blend_shape_count() > 0:
			_face = m
			break
	if _face:
		_fit_mouth_weights(_face.mesh as ArrayMesh, _fit_key())
		for i in _face.mesh.get_blend_shape_count():
			_shape[str(_face.mesh.get_blend_shape_name(i))] = i
	_vis.resize(VISEMES.size())
	_vis_to.resize(VISEMES.size())
	for e in EXPRESSIONS:
		_expr[e] = 0.0
		_expr_target[e] = 0.0
	if _skel:
		# glTF import turns "mixamorig:Head" into "mixamorig_Head"; accept either.
		for b in ["LeftArm", "RightArm", "LeftForeArm", "RightForeArm", "Spine", "Spine1", "Spine2", "Neck", "Head",
				"LeftHand", "RightHand", "LeftHandMiddle1", "RightHandMiddle1",
				"Hips", "LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase", "RightUpLeg", "RightLeg", "RightFoot", "RightToeBase"]:
			for nm in ["mixamorig_" + b, "mixamorig:" + b, b]:
				var i := _skel.find_bone(nm)
				if i >= 0:
					_bones[b] = i
					break
		_arm_pose("Left", 1.0, arm_spread, 0.0, elbow_bend)
		_arm_pose("Right", -1.0, arm_spread, 0.0, elbow_bend)
		_arms_stand = _rest.duplicate()
		_arm_pose("Left", 1.0, 8.0, 28.0, 62.0)
		_arm_pose("Right", -1.0, 8.0, 28.0, 62.0)
		_arms_sit = _rest.duplicate()
		_arm_pose("Left", 1.0, 4.0, 62.0, 95.0)
		_arm_pose("Right", -1.0, 4.0, 62.0, 95.0)
		_arms_lie = _rest.duplicate()
		_arm_pose("Left", 1.0, 3.5, 4.0, 10.0)
		_arm_pose("Right", -1.0, 3.5, 4.0, 10.0)
		_arms_tuck = _rest.duplicate()
		_rest = _arms_stand.duplicate()
		for b in _rest:
			_skel.set_bone_pose_rotation(_bones[b], _rest[b])
		if _bones.has("Head"):
			_head_h = _skel.get_bone_global_rest(_bones["Head"]).origin.y + 0.1
		if _bones.has("Hips"):
			_hips_rest = _skel.get_bone_rest(_bones["Hips"]).origin
		if _bones.has("LeftUpLeg"):
			_hip_h = _skel.get_bone_global_rest(_bones["LeftUpLeg"]).origin.y
	_voice = AudioStreamPlayer3D.new()
	_voice.unit_size = 3.0
	_voice.max_distance = 18.0
	_voice.bus = _base_bus()
	_voice.position.y = _head_h
	if solid:
		_make_solid()
	add_child(_voice)
	_blink_next = _rng.randf_range(1.0, 4.0)
	_time = _rng.randf() * 10.0
	_lod_t = _rng.randf() / LOD_HZ                  # (the slow ones spread over the frames)

func _fit_key() -> String:
	var m := _face.mesh
	if m.resource_path != "":
		return m.resource_path
	return "%s|%s|%d" % [model.resource_path, m.resource_name, m.get_surface_count()] if model and model.resource_path != "" else ""

## face_rig.py weighted the mouth's inside (cavity, teeth, tongue, seals) 100% to the Head bone, but
## the lips and chin round it are ~70% Head / 30% Neck: turning the head moved the inside further than
## the lips and it bulged out through them. Each part vertex takes the bone weights of the skin vertex
## nearest it, so the inside and the lips move as one. Done once per mesh (shared by every instance);
## with a `fit_key` the result is kept, and the same model loaded again only uploads it.
static func _fit_mouth_weights(mesh: ArrayMesh, fit_key := "") -> void:
	if mesh == null or mesh.has_meta("_mouth_fit"):
		return
	mesh.set_meta("_mouth_fit", true)
	if fit_key != "" and _mouth_fits.has(fit_key):
		var done: Dictionary = _mouth_fits[fit_key]
		for s: int in done:
			mesh.surface_update_skin_region(s, 0, done[s])
		return
	var fitted := {}                                    # (kept as it fills, so an early return is kept too)
	if fit_key != "":
		_mouth_fits[fit_key] = fitted
	var parts: Array[int] = []
	var skin: Array[int] = []
	for s in mesh.get_surface_count():
		var mat := mesh.surface_get_material(s)
		var nm := mat.resource_name if mat else ""
		if nm.contains("mouth_cavity") or nm.contains("teeth_") or nm.contains("tongue"):
			parts.append(s)
		else:
			skin.append(s)
	if parts.is_empty():
		return
	var part_arr := {}
	var box: AABB
	for s in parts:
		var a := mesh.surface_get_arrays(s)
		part_arr[s] = a
		var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		if part_arr.size() == 1:
			box = AABB(vs[0], Vector3.ZERO)
		for v in vs:
			box = box.expand(v)
	box = box.grow(0.08)
	# Skin vertices near the mouth, hashed into 1 cm cells.
	const CELL := 0.01
	var grid := {}
	for s in skin:
		var a := mesh.surface_get_arrays(s)
		var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var bs: PackedInt32Array = a[Mesh.ARRAY_BONES]
		var ws: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
		if bs.size() != vs.size() * 4:
			return                                      # (8-weight skins: not what face_rig makes)
		for i in vs.size():
			if not box.has_point(vs[i]):
				continue
			var key := Vector3i((vs[i] / CELL).floor())
			if not grid.has(key):
				grid[key] = []
			grid[key].append([vs[i], bs.slice(i * 4, i * 4 + 4), ws.slice(i * 4, i * 4 + 4)])
	if grid.is_empty():
		return
	for s in parts:
		var vs: PackedVector3Array = part_arr[s][Mesh.ARRAY_VERTEX]
		var data := PackedByteArray()
		data.resize(vs.size() * 16)                     # per vertex: 4 x u16 bones, 4 x u16 unorm weights
		for i in vs.size():
			var c := Vector3i((vs[i] / CELL).floor())
			var best: Array = []
			var bd := INF
			for r in 9:                                 # widen the search until something is found
				for x in range(-r, r + 1):
					for y in range(-r, r + 1):
						for z in range(-r, r + 1):
							if maxi(absi(x), maxi(absi(y), absi(z))) != r:
								continue
							for p: Array in grid.get(c + Vector3i(x, y, z), []):
								var d: float = vs[i].distance_squared_to(p[0])
								if d < bd:
									bd = d
									best = p
				if not best.is_empty() and bd < pow((r + 1) * CELL, 2):
					break
			if best.is_empty():
				return                                  # (leave the mesh as it was)
			var bones: PackedInt32Array = best[1]
			var w: PackedFloat32Array = best[2]
			for k in 4:
				data.encode_u16(i * 16 + k * 2, bones[k])
				data.encode_u16(i * 16 + 8 + k * 2, int(round(clampf(w[k], 0.0, 1.0) * 65535.0)))
		mesh.surface_update_skin_region(s, 0, data)
		fitted[s] = data

# Where the voice goes: `voice_bus`, or the mix's Voice bus when that is left at Master.
func _base_bus() -> StringName:
	return &"Voice" if voice_bus == &"Master" and AudioServer.get_bus_index("Voice") >= 0 else voice_bus

# While it speaks, a bus of its own with a spectrum analyser, to read the line's loudness as it plays
# (an analyser on every character's bus all night costs the mixer for nothing).
func _open_bus() -> void:
	if _bus_name != "" and AudioServer.get_bus_index(_bus_name) >= 0:
		return
	var nm := "Voice_%d" % get_instance_id()
	AudioServer.add_bus()
	var bi := AudioServer.bus_count - 1
	AudioServer.set_bus_name(bi, nm)
	AudioServer.set_bus_send(bi, _base_bus())
	_bus_name = nm
	var an := AudioEffectSpectrumAnalyzer.new()
	an.fft_size = AudioEffectSpectrumAnalyzer.FFT_SIZE_512
	AudioServer.add_bus_effect(bi, an)
	_voice.bus = StringName(nm)

func _close_bus() -> void:
	if _voice:
		_voice.bus = _base_bus()
	var bi := AudioServer.get_bus_index(_bus_name) if _bus_name != "" else -1
	if bi >= 0:
		AudioServer.remove_bus(bi)
	_bus_name = ""

var _solid: CharacterBody3D
var _solid_on := false

func _make_solid() -> void:
	_solid = CharacterBody3D.new()
	_solid.name = "Solid"
	_solid.top_level = true
	_solid.collision_layer = 1
	_solid.collision_mask = 0
	_solid.add_to_group("npc_solid")
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.2
	cap.height = 1.7
	cs.shape = cap
	cs.position.y = 0.85
	cs.disabled = true
	_solid.add_child(cs)
	add_child(_solid)

func _physics_process(_delta: float) -> void:
	if _solid == null:
		return
	# Inside the cars only (floor 1.4 m): on a platform it would stand in the exterior doors' swing.
	var on := solid and _sit < 0.35 and not asleep and is_visible_in_tree() and global_position.y > 1.2 and absf(global_position.z) < 1.5
	if on != _solid_on:
		_solid_on = on
		(_solid.get_child(0) as CollisionShape3D).set_deferred("disabled", not on)
	if on:
		_solid.global_transform = Transform3D(Basis.IDENTITY, global_position)

func _exit_tree() -> void:
	_close_bus()

## Mumbles `text` (shown as a subtitle) for `seconds`, or as long as it takes to read.
func say(text: String, seconds: float = -1.0) -> void:
	_say_len = seconds if seconds > 0.0 else clampf(0.9 + text.length() * 0.058, 1.4, 9.0)
	if not mumbles.is_empty():
		var k := _rng.randi_range(0, mumbles.size() - 1)
		if k == _last_clip and mumbles.size() > 1:
			k = (k + 1) % mumbles.size()
		_last_clip = k
		var clip := mumbles[k]
		if "loop" in clip:
			clip.set("loop", true)
		_open_bus()
		_voice.stream = clip
		_voice.volume_db = -40.0
		_voice.play(_rng.randf() * maxf(clip.get_length() - _say_len, 0.0))
	_say_t = 0.0
	if text != "" and _player_within(subtitle_range):
		Subtitles.show_line(self, speaker_name, text, _say_len + 0.6)

func set_expression(name: String, weight: float) -> void:
	for e in EXPRESSIONS:
		_expr_target[e] = weight if e == name else 0.0

func is_speaking() -> bool:
	return _say_t >= 0.0

func _player_within(d: float) -> bool:
	var p := _find_player()
	return p == null or p.global_position.distance_to(global_position) < d

## Seated at once (placed straight into a seat).
func sit_now() -> void:
	sit_target = 1.0
	_sit = 1.0

# The player, found once (a search of the whole tree every frame is too dear with the world loaded).
func _find_player() -> Node3D:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
		if _player == null:
			_player = get_tree().root.find_child("Player", true, false) as Node3D
	return _player

func _process(delta: float) -> void:
	_time += delta
	_update_voice(delta)
	_lod_t += delta
	if lod and _lod_t < 1.0 / LOD_HZ and not _full_rate():
		return
	var d := _lod_t
	_lod_t = 0.0
	_update_face(d)
	_update_body(d)

# Seen up close, or doing something that must not stutter (the scares).
func _full_rate() -> bool:
	if fear > 0.0 or crawl > 0.0 or grab > 0.0 or not face_weights.is_empty():
		return true
	if not is_visible_in_tree():
		return false
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return true
	var head := global_transform * Vector3(0, _head_h, 0)
	var d2 := cam.global_position.distance_squared_to(head)
	return d2 < 9.0 or (d2 < LOD_NEAR * LOD_NEAR and cam.is_position_in_frustum(head))

func _update_voice(delta: float) -> void:
	if _vis_idle and _say_t < 0.0:
		return                                          # (silent and the mouth at rest: nothing to do)
	_vis_to.fill(0.0)
	_vis_to[0] = 1.0
	if _say_t >= 0.0:
		_say_t += delta
		# Fade in and out, so a stretch cut from the middle of a take starts and ends softly.
		var g := minf(_say_t / 0.08, 1.0) * clampf((_say_len - _say_t) / 0.3, 0.0, 1.0)
		_voice.volume_db = linear_to_db(maxf(g, 0.0001))
		if _bus_name == "" and _voice.playing:
			_open_bus()                                 # (taken out of the tree and back mid-line)
		var bi := AudioServer.get_bus_index(_bus_name) if _bus_name != "" else -1
		var an := AudioServer.get_bus_effect_instance(bi, 0) as AudioEffectSpectrumAnalyzerInstance if bi >= 0 else null
		var lv := 0.0
		var op := 0.0
		if an:
			lv = clampf(an.get_magnitude_for_frequency_range(80.0, 4000.0).length() * 9.0, 0.0, 1.0)
			# Vowel loudness against this voice's own recent peak, so quiet takes open the mouth too.
			var raw := an.get_magnitude_for_frequency_range(500.0, 3000.0).length()
			_op_peak = maxf(_op_peak * (1.0 - delta * 0.3), raw)
			op = clampf(raw / maxf(_op_peak, 0.004), 0.0, 1.0)
		var was := _level
		_level = lerpf(_level, lv, clampf(delta * 18.0, 0.0, 1.0))
		_open = lerpf(_open, op, clampf(delta * 18.0, 0.0, 1.0))
		if _level > 0.08 and was <= 0.08 or _rng.randf() < delta * 2.0:
			_cur_vis = [2, 3, 4, 5, 8, 3, 4][_rng.randi_range(0, 6)]   # B C D E H C D: varied, some open wide
		if _level > 0.06:
			_vis_to[0] = 0.0
			if _open < 0.15:
				_vis_to[1] = 0.6                                    # a hum: lips together
			else:
				_vis_to[_cur_vis] = clampf(0.3 + _open * 0.55, 0.0, 0.8)
		if _say_t >= _say_len:
			_say_t = -1.0
			_voice.stop()
			_close_bus()
			finished_speaking.emit()
	else:
		_level = 0.0
		_open = 0.0
	for k in VISEMES.size():
		_vis[k] = move_toward(_vis[k], _vis_to[k], delta * 12.0)
	_vis_idle = _say_t < 0.0 and _vis == _vis_to

func _update_face(delta: float) -> void:
	if _face == null:
		return
	for k in VISEMES.size():
		_set_shape(VISEMES[k], _vis[k] if k > 0 else 0.0)
	# Blinks: quick close, slower open; now and then a double blink.
	_blink_t += delta
	var b := 0.0
	if _blink_t > _blink_next:
		var p := (_blink_t - _blink_next) / 0.16
		b = 1.0 - absf(p * 2.0 - 1.0) if p < 1.0 else 0.0
		if p >= 1.0:
			_blink_t = 0.0
			_blink_next = 0.25 if _rng.randf() < 0.12 else _rng.randf_range(2.2, 6.0)
	if fear > 0.3:
		b = 0.0                                   # (staring at it)
	_set_shape("lids_open_L", 1.0 - b)
	_set_shape("lids_open_R", 1.0 - b)
	if fear > 0.05 and _say_t < 0.0:
		_set_shape("viseme_D", maxf(_vis[4], 0.5 * clampf(fear, 0.0, 1.0)))    # (a gasp, the mouth hanging open)
	for e in EXPRESSIONS:
		_expr[e] = move_toward(float(_expr[e]), float(_expr_target[e]), delta * 2.5)
		_set_shape(e, _expr[e])
	for k: String in face_weights:
		_set_shape(k, face_weights[k])

func _set_shape(name: String, w: float) -> void:
	if _shape.has(name):
		_face.set_blend_shape_value(_shape[name], w)

# Arms hanging at the sides, whatever the rest pose (T or A): the upper arm is turned (in model
# space, the character facing +Z, its left at +X) to point down, `spread` degrees out and `fwd`
# degrees forward, the forearm `elbow` degrees forward of it. Stored as local rotations in _rest.
func _arm_pose(side: String, sx: float, spread: float, fwd: float, elbow: float) -> void:
	if not (_bones.has(side + "Arm") and _bones.has(side + "ForeArm")):
		return
	var ai: int = _bones[side + "Arm"]
	var fi: int = _bones[side + "ForeArm"]
	var hi := _skel.find_bone(_skel.get_bone_name(fi).replace("ForeArm", "Hand"))
	var pg := _skel.get_bone_global_rest(_skel.get_bone_parent(ai)).basis
	var ag := _skel.get_bone_global_rest(ai)
	var fg := _skel.get_bone_global_rest(fi)
	var hand := _skel.get_bone_global_rest(hi).origin if hi >= 0 else fg.origin + (fg.origin - ag.origin)
	var s := deg_to_rad(spread)
	var f := deg_to_rad(fwd)
	var up_dir := Vector3(sx * sin(s), -cos(s) * cos(f), 0.04 + sin(f)).normalized()
	var q1 := Quaternion((fg.origin - ag.origin).normalized(), up_dir)
	var a_new := Basis(q1) * ag.basis
	_rest[side + "Arm"] = (pg.inverse() * a_new).get_rotation_quaternion()
	var b := deg_to_rad(elbow)
	var fore_dir := (up_dir * cos(b) + Vector3(0, 0, 1) * sin(b)).normalized()
	var q2 := Quaternion((Basis(q1) * (hand - fg.origin)).normalized(), fore_dir)
	var f_new := Basis(q2) * Basis(q1) * fg.basis
	_rest[side + "ForeArm"] = (a_new.inverse() * f_new).get_rotation_quaternion()

# Turns a bone by `r` about the model's axes (on top of its parent's current pose).
func _bone(name: String, r: Quaternion) -> void:
	if not _bones.has(name):
		return
	var i: int = _bones[name]
	var p := _skel.get_bone_parent(i)
	var pb := _skel.get_bone_global_pose(p).basis.orthonormalized() if p >= 0 else Basis()
	var local := Basis(_rest[name]) if _rest.has(name) else _skel.get_bone_rest(i).basis.orthonormalized()
	_skel.set_bone_pose_rotation(i, (pb.inverse() * Basis(r) * pb * local).get_rotation_quaternion())

# Points a bone along `dir` (model space) from its rest direction toward `child`, keeping its rest
# twist, whatever its parent's pose.
func _aim(name: String, child: String, dir: Vector3) -> void:
	if not (_bones.has(name) and _bones.has(child)):
		return
	var i: int = _bones[name]
	var g := _skel.get_bone_global_rest(i)
	var rest_dir := (_skel.get_bone_global_rest(_bones[child]).origin - g.origin).normalized()
	var want := Basis(Quaternion(rest_dir, dir.normalized())) * g.basis.orthonormalized()
	var p := _skel.get_bone_parent(i)
	var pb := _skel.get_bone_global_pose(p).basis.orthonormalized() if p >= 0 else Basis()
	_skel.set_bone_pose_rotation(i, (pb.inverse() * want).get_rotation_quaternion())

func _rest_dir(name: String, child: String) -> Vector3:
	if not (_bones.has(name) and _bones.has(child)):
		return Vector3.DOWN
	return (_skel.get_bone_global_rest(_bones[child]).origin - _skel.get_bone_global_rest(_bones[name]).origin).normalized()

# Hips and legs: standing straight, a walk cycle (driven by walk_speed: a step about 0.65 m), or
# seated (thighs forward on the cushion, shins down, the pelvis lowered onto the seat and leaning back
# a little against the backrest), blended by _sit.
func _update_legs(delta: float) -> void:
	_sit = move_toward(_sit, sit_target, delta * 1.1)
	var s := _sit * _sit * (3.0 - 2.0 * _sit)
	_gait = move_toward(_gait, clampf(walk_speed / 1.1, 0.0, 1.0) * (1.0 - s), delta * 4.0)
	_phase = fmod(_phase + delta * TAU * walk_speed / 1.3, TAU)
	if _bones.has("Hips"):
		var bob := -0.022 * _gait * absf(sin(_phase))
		var drop := (sit_height + 0.1 - _hip_h) * s
		_skel.set_bone_pose_position(_bones["Hips"], _hips_rest + Vector3(0, drop + bob, -0.03 * s))
		_skel.set_bone_pose_rotation(_bones["Hips"], _skel.get_bone_rest(_bones["Hips"]).basis.get_rotation_quaternion()
				* Quaternion(Vector3.RIGHT, -0.09 * s))
	for side: String in ["Left", "Right"]:
		var sx := 1.0 if side == "Left" else -1.0
		var ph := _phase if side == "Left" else _phase + PI
		var a := 0.4 * _gait * sin(ph)                                  # thigh swing (forward +)
		var k := _gait * (0.12 + 0.6 * maxf(cos(ph), 0.0))             # knee bend, most in the swing
		var thigh := Basis(Vector3.RIGHT, -a) * _rest_dir(side + "UpLeg", side + "Leg")
		var shin := Basis(Vector3.RIGHT, k - a) * _rest_dir(side + "Leg", side + "Foot")
		var foot := Basis(Vector3.RIGHT, (k - a) * 0.4) * _rest_dir(side + "Foot", side + "ToeBase")
		thigh = thigh.lerp(Vector3(sx * 0.09, -0.1, 1.0).normalized(), s)
		shin = shin.lerp(Vector3(sx * 0.03, -1.0, 0.12).normalized(), s)
		if lie_legs > 0.0:
			var w := clampf(lie_legs, 0.0, 1.0)
			if sx == -lie_side:
				# the upper leg: drawn up in front and dropped across onto the lower one
				thigh = thigh.lerp(Vector3(-sx * 0.30, -0.62, 0.72).normalized(), w)
				shin = shin.lerp(Vector3(-sx * 0.10, -1.0, -0.12).normalized(), w)
			else:
				# the lower leg: nearly straight, a little forward
				thigh = thigh.lerp(Vector3(sx * 0.01, -0.92, 0.33).normalized(), w)
				shin = shin.lerp(Vector3(0.0, -1.0, -0.18).normalized(), w)
		_aim(side + "UpLeg", side + "Leg", thigh)
		_aim(side + "Leg", side + "Foot", shin)
		_aim(side + "Foot", side + "ToeBase", foot)

# The arms: standing / hands on the thighs, swinging against the legs when walking (after the spine).
func _update_arms() -> void:
	var s := _sit * _sit * (3.0 - 2.0 * _sit)
	for b in _arms_stand:
		_rest[b] = (_arms_stand[b] as Quaternion).slerp(_arms_sit[b], s)
		if tuck > 0.0 and _arms_tuck.has(b):
			_rest[b] = (_rest[b] as Quaternion).slerp(_arms_tuck[b], clampf(tuck, 0.0, 1.0))
		if lie > 0.0 and _arms_lie.has(b):
			_rest[b] = (_rest[b] as Quaternion).slerp(_arms_lie[b], clampf(lie, 0.0, 1.0))
	var sw := 0.3 * _gait * sin(_phase)
	_bone("LeftArm", Quaternion(Vector3.RIGHT, sw))
	_bone("RightArm", Quaternion(Vector3.RIGHT, -sw))
	_bone("LeftForeArm", Quaternion(Vector3.RIGHT, -0.25 * _gait * maxf(-sin(_phase), 0.0)))
	_bone("RightForeArm", Quaternion(Vector3.RIGHT, -0.25 * _gait * maxf(sin(_phase), 0.0)))

func _update_body(delta: float) -> void:
	if _skel == null:
		return
	_update_legs(delta)
	# Breathing and the train's sway.
	var br := sin(_time * (1.25 if asleep else 1.6)) * (0.03 if asleep else 0.012)
	var sway := 0.0 if asleep else sin(_time * 0.9) * 0.01
	_bone("Spine1", Quaternion(Vector3.RIGHT, -br))
	_bone("Spine2", Quaternion(Vector3.BACK, sway))
	_update_arms()
	_update_fear_body()
	# Head toward the target (the player when close), within a natural range; frightened, on what
	# frightens it, quick and farther round.
	var tgt := look_at_target
	if tgt == null and not asleep:
		var p := _find_player()
		if p and p.global_position.distance_to(global_position) < look_range:
			tgt = p
	var afraid := fear > 0.05
	var yaw := 0.0
	var pitch := 0.0
	if tgt or afraid:
		var head_pos := global_transform * Vector3(0, _head_h, 0)
		var eye := fear_at
		if not afraid:
			eye = tgt.global_position + Vector3(0, 1.5, 0) if not tgt is Camera3D else tgt.global_position
		var local := global_transform.basis.inverse() * (eye - head_pos)
		yaw = clampf(atan2(local.x, local.z), -1.0, 1.0)
		pitch = clampf(-atan2(local.y, Vector2(local.x, local.z).length()), -0.4, 0.75 if afraid else 0.4)
	var turn := 20.0 if afraid else 3.0
	_head_yaw = lerp_angle(_head_yaw, yaw, clampf(delta * turn, 0.0, 1.0))
	_head_pitch = lerpf(_head_pitch, pitch, clampf(delta * turn, 0.0, 1.0))
	_bone("Neck", Quaternion(Vector3.UP, _head_yaw * 0.4) * Quaternion(Vector3.RIGHT, _head_pitch * 0.4))
	_bone("Head", Quaternion(Vector3.UP, _head_yaw * 0.6) * Quaternion(Vector3.RIGHT, _head_pitch * 0.6))
	_update_crawl(delta)
	_update_grab()
	_update_fear_arms()
	_update_twist()

var _head_yaw := 0.0
var _head_pitch := 0.0

# ————— on all fours, and reaching (AnomalyFrenzy) —————

## On all fours (0 .. 1), belly up: the spine bridged over the floor, hands and feet under it, elbows
## and knees out like a spider's, the head hung back upside down from a broken-looking neck, looking
## the way the head end of the body points and twitching; it scuttles at walk_speed, head first, or
## feet first with crawl_back. Posed over whatever the body was doing. The figure's origin stays on
## the floor under it.
var crawl := 0.0
var crawl_back := false
## Reaching (0 .. 1): the hands at grab_l and grab_r (global), the fingers hooked.
var grab := 0.0
var grab_l := Vector3.ZERO
var grab_r := Vector3.ZERO
## Shape keys held at these weights over everything else (they may be above 1: MonsterFace).
var face_weights := {}
## The head wrenched about its own axes, over everything else: (pitch, yaw, roll).
var head_twist := Vector3.ZERO
var _cr_phase := 0.0
var _tw := Vector2.ZERO             # the head's twitch: where it is, where it is going
var _tw_to := Vector2.ZERO
var _tw_t := 0.0
var _fingers: Array[int] = []

# A bone turned to `want` (model space, whatever its parent's pose), `w` of the way from its pose now.
func _set_global(name: String, want: Basis, w: float) -> void:
	if not _bones.has(name):
		return
	var i: int = _bones[name]
	var p := _skel.get_bone_parent(i)
	var pb := _skel.get_bone_global_pose(p).basis.orthonormalized() if p >= 0 else Basis()
	_skel.set_bone_pose_rotation(i, _skel.get_bone_pose_rotation(i).slerp((pb.inverse() * want).get_rotation_quaternion(), w))

# `_aim`, `w` of the way from the bone's pose now.
func _aim_w(name: String, child: String, dir: Vector3, w: float) -> void:
	if not (_bones.has(name) and _bones.has(child)):
		return
	var g := _skel.get_bone_global_rest(_bones[name])
	var rest_dir := (_skel.get_bone_global_rest(_bones[child]).origin - g.origin).normalized()
	_set_global(name, Basis(Quaternion(rest_dir, dir.normalized())) * g.basis.orthonormalized(), w)

# Two bones reaching for `target` (model space), the joint between them bent toward `pole`.
func _limb(a: String, b: String, c: String, target: Vector3, pole: Vector3, w: float) -> void:
	if not (_bones.has(a) and _bones.has(b) and _bones.has(c)):
		return
	var ra := _skel.get_bone_global_rest(_bones[a]).origin
	var rb := _skel.get_bone_global_rest(_bones[b]).origin
	var rc := _skel.get_bone_global_rest(_bones[c]).origin
	var l1 := ra.distance_to(rb)
	var l2 := rb.distance_to(rc)
	var root := _skel.get_bone_global_pose(_bones[a]).origin
	var to := target - root
	var d := clampf(to.length(), absf(l1 - l2) + 0.01, l1 + l2 - 0.005)
	var dir := to.normalized()
	var ca := clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
	var side := (pole - dir * pole.dot(dir)).normalized()
	var mid := root + dir * l1 * ca + side * l1 * sqrt(1.0 - ca * ca)
	_aim_w(a, b, mid - root, w)
	_aim_w(b, c, root + dir * d - mid, w)

func _update_crawl(delta: float) -> void:
	var w := clampf(crawl, 0.0, 1.0)
	if w <= 0.0 or not _bones.has("Hips"):
		return
	const STRIDE := 0.4
	var go := clampf(walk_speed, 0.0, 1.0)
	var way := -1.0 if crawl_back else 1.0
	_cr_phase = fposmod(_cr_phase + way * delta * TAU * walk_speed / (STRIDE * 4.0), TAU)
	var bob := 0.045 * go * sin(_cr_phase * 2.0)
	var roll := 0.16 * go * sin(_cr_phase)
	var flip := Basis(Vector3.UP, PI)
	# The pelvis high, the spine a bridge down to the shoulders, chest to the ceiling.
	var hi: int = _bones["Hips"]
	var hrest := _skel.get_bone_rest(hi).basis.orthonormalized()
	var pos := _hips_rest + Vector3(0, _hip_h * -0.38 + bob, -0.34)
	_skel.set_bone_pose_position(hi, _skel.get_bone_pose_position(hi).lerp(pos, w))
	var hq := (Basis(Vector3.BACK, roll) * flip * Basis(Vector3.RIGHT, -1.32) * hrest).get_rotation_quaternion()
	_skel.set_bone_pose_rotation(hi, _skel.get_bone_pose_rotation(hi).slerp(hq, w))
	for e: Array in [["Spine", -1.42], ["Spine1", -1.62], ["Spine2", -1.82], ["Neck", -2.45]]:
		if _bones.has(e[0]):
			_set_global(e[0], Basis(Vector3.BACK, -roll * 0.6) * flip * Basis(Vector3.RIGHT, e[1]) * _skel.get_bone_global_rest(_bones[e[0]]).basis.orthonormalized(), w)
	# The head hung back, upside down, twitching: a new tilt every moment.
	_tw_t -= delta
	if _tw_t <= 0.0:
		_tw_t = _rng.randf_range(0.07, 0.3)
		_tw_to = Vector2(_rng.randf_range(-0.3, 0.3), _rng.randf_range(-0.55, 0.55))
	_tw = _tw.lerp(_tw_to, clampf(delta * 32.0, 0.0, 1.0))
	if _bones.has("Head"):
		_set_global("Head", Basis(Vector3.UP, _tw.x) * Basis(Vector3.BACK, _tw.y) * flip * Basis(Vector3.RIGHT, -2.75) * _skel.get_bone_global_rest(_bones["Head"]).basis.orthonormalized(), w)
	# A trot: a hand and the opposite foot together; each lifts and swings forward by turns.
	for side: String in ["Left", "Right"]:
		var sx := 1.0 if side == "Left" else -1.0
		var ph := _cr_phase + (0.0 if side == "Left" else PI)
		var hand := Vector3(sx * 0.34, 0.03, 0.16 + STRIDE * go * cos(ph))
		hand.y += 0.2 * go * maxf(sin(ph), 0.0)
		var foot := Vector3(sx * 0.3, 0.04, -0.62 + STRIDE * go * cos(ph + PI))
		foot.y += 0.17 * go * maxf(sin(ph + PI), 0.0)
		_limb(side + "UpLeg", side + "Leg", side + "Foot", foot, Vector3(sx * 0.7, 1.0, 0.5), w)
		_aim_w(side + "Foot", side + "ToeBase", Vector3(sx * 0.15, -0.45, -0.85), w)
		_limb(side + "Arm", side + "ForeArm", side + "Hand", hand, Vector3(sx, 0.55, -0.5), w)
		_aim_w(side + "Hand", side + "HandMiddle1", Vector3(sx * 0.45, -0.25, -0.85), w)

func _update_twist() -> void:
	if head_twist == Vector3.ZERO or not _bones.has("Head"):
		return
	var i: int = _bones["Head"]
	_skel.set_bone_pose_rotation(i, _skel.get_bone_pose_rotation(i) * Quaternion.from_euler(head_twist))

func _update_grab() -> void:
	var w := clampf(grab, 0.0, 1.0)
	if w <= 0.0 or _skel == null:
		return
	var inv := _skel.global_transform.affine_inverse()
	_limb("LeftArm", "LeftForeArm", "LeftHand", inv * grab_l, Vector3(0.9, -0.5, -0.4), w)
	_limb("RightArm", "RightForeArm", "RightHand", inv * grab_r, Vector3(-0.9, -0.5, -0.4), w)
	# Fingers hooked: every joint of every finger bent the same way.
	if _fingers.is_empty():
		for i in _skel.get_bone_count():
			var n := _skel.get_bone_name(i)
			if n.contains("Hand") and not n.ends_with("Hand") and not n.ends_with("4") and not n.contains("Thumb"):
				_fingers.append(i)
	for i in _fingers:
		var r := _skel.get_bone_rest(i).basis.get_rotation_quaternion()
		_skel.set_bone_pose_rotation(i, r.slerp(r * Quaternion(Vector3.RIGHT, 0.85), w))
		_skel.set_bone_pose_scale(i, Vector3.ONE.lerp(Vector3(0.92, 1.3, 0.92), w))    # (too long)

# ————— frightened (FrenzyPanic) —————

## Frightened (0 .. 1) by whatever is at fear_at (global): it shrinks back from it, the upper body
## leaning away, the knees bent (seated: the feet drawn up off the floor), the arms up between its
## face and the thing, shaking, the eyes wide on it and the mouth hanging open.
var fear := 0.0
var fear_at := Vector3.ZERO
var _feared := false

# Turns a bone further by `r` about the model's axes, on top of its pose now.
func _turn(name: String, r: Quaternion) -> void:
	if not _bones.has(name):
		return
	var i: int = _bones[name]
	var p := _skel.get_bone_parent(i)
	var pb := _skel.get_bone_global_pose(p).basis.orthonormalized() if p >= 0 else Basis()
	_skel.set_bone_pose_rotation(i, (pb.inverse() * Basis(r) * pb * Basis(_skel.get_bone_pose_rotation(i))).get_rotation_quaternion())

# Away from it, level, in the skeleton's space.
func _fear_away() -> Vector3:
	var inv := _skel.global_transform.affine_inverse()
	var v := inv * global_position - inv * fear_at
	v.y = 0.0
	return v.normalized() if v.length() > 0.001 else Vector3.BACK

func _update_fear_body() -> void:
	var w := clampf(fear, 0.0, 1.0)
	if w <= 0.0 or not _bones.has("Hips"):
		if _feared:
			_feared = false
			_bone("Spine", Quaternion.IDENTITY)       # (nothing else sets it back)
		return
	_feared = true
	var s := _sit * _sit * (3.0 - 2.0 * _sit)
	var shake := sin(_time * 47.0) * 0.5 + sin(_time * 71.0) * 0.5
	# The upper body leans away (seated, back into the seat), shaking.
	var away := _fear_away()
	var axis := Vector3.UP.cross(away)
	if axis.length() > 0.001:
		var lean := w * lerpf(0.34, 0.2, s) + shake * 0.022 * w
		# (Spine from its rest: nothing else poses it each frame, and turned on top it would add up)
		_bone("Spine", Quaternion(axis.normalized(), lean * 0.35))
		_turn("Spine1", Quaternion(axis.normalized(), lean * 0.35))
		_turn("Spine2", Quaternion(axis.normalized(), lean * 0.3))
	var hi: int = _bones["Hips"]
	var ws := w * (1.0 - s)
	if ws > 0.0:
		# Standing: down on bent knees, the feet where they were.
		_skel.set_bone_pose_position(hi, _skel.get_bone_pose_position(hi) + Vector3(0, -_hip_h * 0.1 * ws, 0) + away * 0.04 * ws)
		for side: String in ["Left", "Right"]:
			var sx := 1.0 if side == "Left" else -1.0
			if _bones.has(side + "Foot"):
				var foot := _skel.get_bone_global_rest(_bones[side + "Foot"]).origin
				_limb(side + "UpLeg", side + "Leg", side + "Foot", foot, Vector3(sx * 0.25, 0.0, 1.0), ws)
				_aim_w(side + "Foot", side + "ToeBase", _rest_dir(side + "Foot", side + "ToeBase"), ws)
	var wl := w * s
	if wl > 0.0:
		# Seated: the knees up, the feet off the floor.
		for side: String in ["Left", "Right"]:
			var sx := 1.0 if side == "Left" else -1.0
			_aim_w(side + "UpLeg", side + "Leg", Vector3(sx * 0.1, 0.3, 0.95), wl)
			_aim_w(side + "Leg", side + "Foot", Vector3(sx * 0.02, -0.82, -0.57), wl)
			_aim_w(side + "Foot", side + "ToeBase", Vector3(sx * 0.05, -0.55, 0.83), wl)

# The hands up between its face and the thing, the palms to it, the elbows in.
func _update_fear_arms() -> void:
	var w := clampf(fear, 0.0, 1.0)
	if w <= 0.0 or not _bones.has("Head"):
		return
	var inv := _skel.global_transform.affine_inverse()
	var head := _skel.get_bone_global_pose(_bones["Head"]).origin
	var aim := inv * fear_at - head
	# (it cannot hold its hands up behind it: the front half only)
	aim = Vector3(aim.x, 0.0, aim.z).normalized() if Vector2(aim.x, aim.z).length() > 0.001 else Vector3.BACK
	aim.z = maxf(aim.z, 0.45)
	aim = aim.normalized()
	var low := clampf((inv * fear_at).y - head.y, -1.2, 0.2)
	var left := Vector3.UP.cross(aim).normalized()
	var j := Vector3(sin(_time * 53.0), sin(_time * 67.0), sin(_time * 59.0)) * 0.008 * w
	var mid := head + aim * 0.27 + Vector3(0, -0.07 + low * 0.1, 0) + j
	_limb("LeftArm", "LeftForeArm", "LeftHand", mid + left * 0.12, Vector3(0.8, -0.6, -0.3), w)
	_limb("RightArm", "RightForeArm", "RightHand", mid - left * 0.12, Vector3(-0.8, -0.6, -0.3), w)
	var up := (Vector3.UP * 0.85 + aim * 0.4).normalized()
	_aim_w("LeftHand", "LeftHandMiddle1", (up + left * 0.25).normalized(), w)
	_aim_w("RightHand", "RightHandMiddle1", (up - left * 0.25).normalized(), w)
