extends SceneTree
# The audio mix over a real-time stretch of the journey, windowed (the meters need the real mixer):
# departure (whistle, bell, chuffs), a dread swell cut by a scream, passengers talking beside Kevin
# (Ambience ducks under Voice), a goods train passing, a wake-scare shriek and a pile-up of sounds.
# Two captures on Master, before and after its limiter, give the envelope; it fails on clipping.
#   godot --path . -s tools/_check_mix.gd -- [seconds=150]
var pre: AudioEffectCapture
var post: AudioEffectCapture
var stats := {"pre_max": 0.0, "post_max": 0.0, "post_over_1db": 0, "post_clip": 0, "frames": 0}
var env: Array[float] = []          # post-limiter peak per 5 s
var env_pre: Array[float] = []
var bus_max := {}

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var seconds := float(args[0]) if args.size() > 0 else 150.0
	DisplayServer.window_set_size(Vector2i(1280, 720))
	print("buses: ", _bus_list())
	pre = AudioEffectCapture.new()
	pre.buffer_length = 0.5
	post = AudioEffectCapture.new()
	post.buffer_length = 0.5
	AudioServer.add_bus_effect(0, pre, 0)
	AudioServer.add_bus_effect(0, post, -1)
	var world: Node3D = load("res://scenes/game/journey.tscn").instantiate()
	root.add_child(world)
	var nav: TrainNav = null
	while nav == null or not nav.ready_:
		await process_frame
		nav = get_first_node_in_group("train_nav")
	var j = world.get_node("Journey")
	var pax: Passengers = world.get_node("Passengers")
	var hd: HorrorDirector = get_first_node_in_group("horror")
	var ptn = get_first_node_in_group("passing_train")
	var audio: GameAudio = world.get_node("Audio")
	var player: Node3D = world.get_node("Player")
	player.global_position = Vector3(2.0, 1.45, 0.0)
	pre.clear_buffer()
	post.clear_buffer()
	var t0 := Time.get_ticks_msec()
	var done := {}
	var talk_n := 0
	while true:
		await process_frame
		var t := (Time.get_ticks_msec() - t0) / 1000.0
		_pull(t)
		if t > seconds:
			break
		if t > 2.0 and _once(done, "depart"):
			j._timer = 0.0
			print("%5.1f depart" % t)
		if t > 25.0 and _once(done, "swell"):
			GameAudio.dread(0.9, 8.0)
			print("%5.1f dread swell -> 0.9 over 8 s" % t)
		if t > 34.0 and _once(done, "hit"):
			GameAudio.dread(0.0, 0.0)
			hd.trigger("scream")
			print("%5.1f dread cut + scream (level now %.2f)" % [t, GameAudio.dread_level()])
		if t > 45.0 and t < 75.0 and talk_n < int((t - 45.0) / 4.0) + 1:
			talk_n += 1
			var near := _nearest_rider(pax, player.global_position)
			if near:
				near.say("Some weather tonight, isn't it.")
				player.global_position = near.global_position + Vector3(0.0, 0.0, 0.8 if near.global_position.z < 0 else -0.8)
		if t > 80.0 and _once(done, "goods"):
			if ptn:
				ptn.start_now()
			print("%5.1f goods train (%s)" % [t, ptn.state if ptn else "none"])
		if t > 115.0 and _once(done, "shriek"):
			var p := AudioStreamPlayer.new()     # like WakeScare: a non-positional shriek at +2 dB
			p.stream = load("res://assets/audio/frenzy_scream_2.mp3")
			p.volume_db = 2.0
			root.add_child(p)
			p.play()
			print("%5.1f wake shriek" % t)
		if t > 125.0 and _once(done, "pileup"):
			GameAudio.dread(1.0, 0.0)
			for k in ["loco_whistle", "door_slide_open", "brakes", "station_bell", "horror_scream", "pass_scare"]:
				audio.play_at(k, player.global_position + Vector3(1.0, 0.0, 0.0), 2.0, 0.0)
			print("%5.1f pile-up at full dread" % t)
		if t > 135.0 and _once(done, "calm"):
			GameAudio.dread(0.0, 4.0)
	_report(audio)
	quit(0)

func _once(done: Dictionary, k: String) -> bool:
	if done.has(k):
		return false
	done[k] = true
	return true

func _nearest_rider(pax: Passengers, at: Vector3) -> TalkingCharacter:
	var best: TalkingCharacter = null
	var bd := 1e9
	for r in pax.riders():
		var b := r.body as TalkingCharacter
		if b and b.is_inside_tree() and b.global_position.distance_to(at) < bd:
			bd = b.global_position.distance_to(at)
			best = b
	return best

func _pull(t: float) -> void:
	var slot := int(t / 5.0)
	while env.size() <= slot:
		env.append(0.0)
		env_pre.append(0.0)
	for pair in [[pre, true], [post, false]]:
		var cap: AudioEffectCapture = pair[0]
		var n := cap.get_frames_available()
		if n <= 0:
			continue
		var buf := cap.get_buffer(n)
		var m := 0.0
		for v in buf:
			var a := maxf(absf(v.x), absf(v.y))
			m = maxf(m, a)
			if not pair[1]:
				if a > 0.891:
					stats.post_over_1db += 1
				if a >= 0.999:
					stats.post_clip += 1
		if pair[1]:
			stats.pre_max = maxf(stats.pre_max, m)
			env_pre[slot] = maxf(env_pre[slot], m)
		else:
			stats.post_max = maxf(stats.post_max, m)
			env[slot] = maxf(env[slot], m)
			stats.frames += n
	for b in ["SFX", "Ambience", "Voice", "Music", "Outside"]:
		var i := AudioServer.get_bus_index(b)
		var db := maxf(AudioServer.get_bus_peak_volume_left_db(i, 0), AudioServer.get_bus_peak_volume_right_db(i, 0))
		bus_max[b] = maxf(bus_max.get(b, -200.0), db)

func _db(x: float) -> String:
	return "%.1f" % linear_to_db(maxf(x, 1e-6))

func _bus_list() -> String:
	var out := []
	for i in AudioServer.bus_count:
		var fx := []
		for e in AudioServer.get_bus_effect_count(i):
			fx.append(AudioServer.get_bus_effect(i, e).get_class().trim_prefix("AudioEffect"))
		out.append("%s->%s%s" % [AudioServer.get_bus_name(i), AudioServer.get_bus_send(i), fx if fx.size() else ""])
	return ", ".join(out)

func _report(_audio: GameAudio) -> void:
	var on := {}
	var master := []
	for n in root.find_children("*", "AudioStreamPlayer", true, false) + root.find_children("*", "AudioStreamPlayer3D", true, false):
		var b := str(n.get("bus"))
		var k := b if not b.begins_with("Voice_") else "Voice_*"
		on[k] = on.get(k, 0) + 1
		if b == "Master":
			master.append(str(n.get_path()))
	var voice_sends := {}
	for i in AudioServer.bus_count:
		if AudioServer.get_bus_name(i).begins_with("Voice_"):
			var s := str(AudioServer.get_bus_send(i))
			voice_sends[s] = voice_sends.get(s, 0) + 1
	var env_s := []
	var pre_s := []
	for i in env.size():
		env_s.append(_db(env[i]))
		pre_s.append(_db(env_pre[i]))
	print("players by bus: ", on, " still on Master: ", master)
	print("voice buses send to: ", voice_sends)
	print("bus peak max dB: ", bus_max)
	print("envelope post-limiter dBFS per 5 s: ", " ".join(env_s))
	print("envelope pre-limiter  dBFS per 5 s: ", " ".join(pre_s))
	print("MIX pre-limiter max %s dBFS, post max %s dBFS, samples over -1 dB %d, clipped %d of %d frames" % [
			_db(stats.pre_max), _db(stats.post_max), stats.post_over_1db, stats.post_clip, stats.frames])
	print("MIX ", "PASS" if stats.post_clip == 0 and stats.post_max <= 0.9 and stats.frames > 0 else "FAIL")
