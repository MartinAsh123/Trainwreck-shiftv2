extends SceneTree
## Soak test: the whole 20-minute journey, nothing forced, windowed. Every 10 s of game time it logs
## frame time, orphan nodes, static and video memory and node counts; every scare, haunting,
## passing train, frenzy, wake scare and stop is a marker in the log. At the end of the line Kevin
## turns in (EndOfDay.turn_in, no save is written) and a last sample is taken after the summary.
##   godot --path . --resolution 1920x1080 [--fixed-fps 60] -s tools/_soak.gd -- <out_dir> [pov=saloon|player] [cap_min=26]
## --fixed-fps 60 runs the game clock in steps of 1/60 s however fast frames come (deterministic,
## and quicker than real time on a fast machine); the frame ms in the log are still wall clock.
## The first 30 s are sampled every second (an unexplained crash was once seen about 14 s in).
## The log is flushed line by line, so after a crash its last lines say where the run was.
## Flags (end of the log): orphans or static memory not back near the baseline after an event,
## memory growth over the run, and 10-s windows much slower than the baseline.

const SAMPLE := 10.0
const EARLY := 30.0
const HITCH_MS := 33.3
const ORPHAN_SLACK := 3            # orphans allowed to stay after an event
const SETTLE := 20.0               # seconds after an event ends before it is checked

var _log: FileAccess
var _t := 0.0                      # game seconds since the journey started
var _events: Array = []            # {name, t0, orph0, mem0, end_t (-1 while running), checked}
var _flags: Array[String] = []
var _samples: Array = []           # [t, avg_ms, orphans, static_mb]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else OS.get_user_data_dir()
	var pov: String = args[1] if args.size() > 1 else "saloon"
	var cap_min := float(args[2]) if args.size() > 2 else 26.0
	DirAccess.make_dir_recursive_absolute(out_dir)
	_log = FileAccess.open(out_dir.path_join("soak.log"), FileAccess.WRITE)
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_line("# soak %s  pov=%s  %s  (game vs wall time at the end shows whether --fixed-fps was on)" % [
			Time.get_datetime_string_from_system(), pov, RenderingServer.get_video_adapter_name()])
	_line("boot: before instantiate  static %.0f MB" % _mb())
	var world: Node3D = load("res://scenes/game/journey.tscn").instantiate()
	_line("boot: instantiated  static %.0f MB" % _mb())
	root.add_child(world)
	_line("boot: in tree")
	var ts: Node = root.get_node("TrainState")
	var player: Node3D = world.get_node("Player")
	var nav: TrainNav = null
	var boot_frames := 0
	var w0 := Time.get_ticks_msec()
	while nav == null or not nav.ready_:
		await process_frame
		boot_frames += 1
		nav = get_first_node_in_group("train_nav")
	_line("boot: nav ready after %d frames, %.1f s wall" % [boot_frames, (Time.get_ticks_msec() - w0) / 1000.0])
	var hd: HorrorDirector = get_first_node_in_group("horror")
	var haunt := get_first_node_in_group("haunt")
	var ghost := get_first_node_in_group("ghost_story")
	var ptn := get_first_node_in_group("passing_train")
	var frenzy := get_first_node_in_group("anomaly_frenzy")
	var wake := get_first_node_in_group("wake_scare")
	var rec: ShiftRecord = get_first_node_in_group("shift_record")
	hd.seed_value = 7
	hd.event_started.connect(func(k: String, f: bool) -> void: _start("horror:" + k + (" forced" if f else "")))
	hd.event_finished.connect(func(k: String) -> void: _end("horror:" + k))
	player.global_position = Vector3(-31.0, 1.45, 0.6)   # Kevin in his room, out of everyone's way
	if pov == "saloon":
		var cam := Camera3D.new()
		cam.far = 9000
		cam.fov = 75
		world.add_child(cam)
		cam.global_position = Vector3(-4.0, 2.9, 0.4)
		cam.look_at(Vector3(-6.0, 2.6, 6.0))
		cam.make_current()
	var watched := {"haunt": [haunt, "stage", "waiting"], "ghost": [ghost, "stage", "dormant"],
			"passing": [ptn, "state", "idle"], "frenzy": [frenzy, "stage", ""], "wake": [wake, "sprung", false]}
	var last := {}
	for k in watched:
		last[k] = watched[k][0].get(watched[k][1]) if watched[k][0] else null
	var last_phase := str(ts.phase)
	var next_sample := 1.0
	var win := PackedFloat32Array()
	var last_us := Time.get_ticks_usec()
	var wall0 := Time.get_ticks_msec()
	var over_at := -1.0
	var turned := false
	_line("t_s | clock | s_m | phase | fps | avg_ms | max_ms | hitches | orphans | static_MB | vram_MB | nodes | objects | draws")
	while _t < cap_min * 60.0:
		await process_frame
		var dt := root.get_process_delta_time()
		_t += dt
		var now := Time.get_ticks_usec()
		var ms := float(now - last_us) / 1000.0
		last_us = now
		win.append(ms)
		if ms > 250.0:
			_line("%7.1f  LONG FRAME %.0f ms (s=%.0f)" % [_t, ms, float(ts.distance)])
		# markers
		if str(ts.phase) != last_phase:
			last_phase = str(ts.phase)
			_line("%7.1f  > TRAIN %s %s" % [_t, last_phase, ts.station if ts.station != "" else ts.next_stop])
		for k in watched:
			var node: Node = watched[k][0]
			if node == null:
				continue
			var v = node.get(watched[k][1])
			if v != last[k]:
				var idle = watched[k][2]
				if last[k] == idle:
					_start("%s:%s" % [k, str(v)])
				elif v == idle or (k in ["haunt", "ghost"] and str(v) == "done"):
					_end(k + ":")
				_line("%7.1f  > %s %s -> %s" % [_t, k.to_upper(), str(last[k]), str(v)])
				last[k] = v
		_check_settled()
		if _t >= next_sample:
			_sample(win, ts)
			win = PackedFloat32Array()
			next_sample += 1.0 if _t < EARLY else SAMPLE
		if rec.shift_over and over_at < 0.0:
			over_at = _t
			_line("%7.1f  > SHIFT OVER (end of the line)" % _t)
		if over_at >= 0.0 and not turned and _t > over_at + 20.0:
			turned = true
			var eod := get_first_node_in_group("end_of_day")
			if eod == null:
				eod = world.find_child("EndOfDay", true, false)
			if eod and eod.has_method("turn_in"):
				_line("%7.1f  > TURN IN" % _t)
				eod.call("turn_in")
			else:
				_line("%7.1f  (no EndOfDay node found)" % _t)
		if turned and _t > over_at + 45.0:
			break
	_sample(win, ts)
	_report(wall0)
	_log.close()
	quit(0)

func _start(name: String) -> void:
	_events.append({"name": name, "t0": _t, "orph0": _orph(), "mem0": _mb(), "end_t": -1.0, "checked": false})
	_line("%7.1f  * START %s  (orphans %d, static %.0f MB)" % [_t, name, _orph(), _mb()])

func _end(name: String) -> void:
	for e in _events:
		if e.name.begins_with(name) and e.end_t < 0.0:
			e.end_t = _t
			_line("%7.1f  * END %s after %.1f s  (orphans %d)" % [_t, e.name, _t - e.t0, _orph()])
			return

func _check_settled() -> void:
	for e in _events:
		if e.checked or e.end_t < 0.0 or _t < e.end_t + SETTLE:
			continue
		e.checked = true
		var d := _orph() - int(e.orph0)
		var dm := _mb() - float(e.mem0)
		var ok := d <= ORPHAN_SLACK
		_line("%7.1f  * CHECK %s: orphans %+d, static %+.1f MB %s" % [_t, e.name, d, dm, "ok" if ok else "<< NOT BACK"])
		if not ok:
			_flags.append("%s at %.0f s left %+d orphan nodes (%d -> %d)" % [e.name, e.t0, d, e.orph0, _orph()])

func _sample(win: PackedFloat32Array, ts: Node) -> void:
	if win.is_empty():
		return
	var sum := 0.0
	var mx := 0.0
	var hitches := 0
	for m in win:
		sum += m
		mx = maxf(mx, m)
		if m > HITCH_MS:
			hitches += 1
	var avg := sum / win.size()
	_samples.append([_t, avg, _orph(), _mb()])
	_line("%7.1f | %s | %6.0f | %-8s | %4.0f | %6.2f | %6.1f | %3d | %5d | %5.0f | %5.0f | %6d | %6d | %5d" % [_t,
			TerminalData.clock_text(), float(ts.distance), str(ts.phase), 1000.0 / avg, avg, mx, hitches, _orph(), _mb(),
			Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
			int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
			int(Performance.get_monitor(Performance.OBJECT_COUNT)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))])

func _report(wall0: int) -> void:
	_line("")
	_line("## summary: %.0f s game time in %.0f s wall" % [_t, (Time.get_ticks_msec() - wall0) / 1000.0])
	# Baseline: the samples between 60 s and 180 s (world built, nothing has fired yet).
	var base: Array = _samples.filter(func(s: Array) -> bool: return s[0] >= 60.0 and s[0] <= 180.0)
	if base.is_empty():
		base = _samples.slice(0, 3)
	var b_ms := _median(base.map(func(s: Array) -> float: return s[1]))
	var b_orph := _median(base.map(func(s: Array) -> float: return float(s[2])))
	var b_mem := _median(base.map(func(s: Array) -> float: return s[3]))
	var last: Array = _samples.back()
	var all_ms: Array = _samples.map(func(s: Array) -> float: return s[1])
	var worst := 0.0
	var slow := 0
	for s: Array in _samples:
		worst = maxf(worst, s[1])
		if s[1] > b_ms * 1.5 and s[0] > EARLY:
			slow += 1
			_flags.append("window at %.0f s averaged %.2f ms (baseline %.2f)" % [s[0], s[1], b_ms])
	_line("baseline (60-180 s): %.2f ms/frame, %d orphans, %.0f MB static" % [b_ms, int(b_orph), b_mem])
	_line("end: %.2f ms/frame, %d orphans, %.0f MB static;  worst 10-s window %.2f ms;  median %.2f ms" % [
			last[1], last[2], last[3], worst, _median(all_ms)])
	# Memory slope over the run after the baseline (MB per minute, least squares).
	var pts: Array = _samples.filter(func(s: Array) -> bool: return s[0] >= 60.0)
	if pts.size() > 3:
		var n := float(pts.size())
		var sx := 0.0
		var sy := 0.0
		var sxx := 0.0
		var sxy := 0.0
		for s: Array in pts:
			var x: float = s[0] / 60.0
			sx += x
			sy += s[3]
			sxx += x * x
			sxy += x * s[3]
		var slope := (n * sxy - sx * sy) / maxf(n * sxx - sx * sx, 0.0001)
		_line("static memory slope after 60 s: %+.2f MB/min" % slope)
		if slope > 2.0:
			_flags.append("static memory grows %.2f MB/min" % slope)
	if float(last[2]) > b_orph + ORPHAN_SLACK * 3:
		_flags.append("orphans at the end %d vs baseline %d" % [last[2], int(b_orph)])
	if float(last[3]) > b_mem * 1.15:
		_flags.append("static memory at the end %.0f MB vs baseline %.0f MB" % [last[3], b_mem])
	for e in _events:
		if e.end_t < 0.0:
			_line("event never ended: %s (started %.0f s)" % [e.name, e.t0])
	_line("events: %d   flags: %d" % [_events.size(), _flags.size()])
	for f in _flags:
		_line("FLAG " + f)
	_line("SOAK " + ("PASS" if _flags.is_empty() else "FLAGS %d" % _flags.size()))

func _median(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := a.duplicate()
	s.sort()
	return float(s[s.size() / 2])

func _orph() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))

func _mb() -> float:
	return Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0

func _line(s: String) -> void:
	print(s)
	if _log:
		_log.store_line(s)
		_log.flush()
