extends SceneTree
## What a TalkingCharacter costs on the main thread when it enters the tree (as station staff do
## when a station streams in): load (fresh, as after the last station freed it), instantiate +
## _ready, and _fit_mouth_weights alone. Each model twice: fresh resource, then the cached one.
##   godot --path . -s tools/_perf_char_spawn.gd       (windowed: headless loses mesh data)

const MODELS := [
	"res://assets/characters/station/cashier.glb",
	"res://assets/characters/police_officer/police_officer.glb",
	"res://assets/characters/military_officer/military_officer.glb",
	"res://assets/characters/station/guard_female.glb",
]

func _initialize() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	await process_frame
	print("| model | pass | load ms | add_child (+_ready) ms | fit_mouth ms |")
	print("|---|---|---|---|---|")
	for path: String in MODELS:
		if not ResourceLoader.exists(path):
			continue
		for pass_i in 2:
			var t0 := Time.get_ticks_usec()
			var ps := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP if pass_i == 0 else ResourceLoader.CACHE_MODE_REUSE) as PackedScene
			var t1 := Time.get_ticks_usec()
			# _fit_mouth_weights alone, on a fresh copy of the face mesh.
			var fit_ms := -1.0
			if pass_i == 0:
				var probe := ps.instantiate()
				for mi: Node in probe.find_children("*", "MeshInstance3D", true, false):
					var m := (mi as MeshInstance3D).mesh as ArrayMesh
					if m and m.get_blend_shape_count() > 0:
						var copy := m.duplicate(true) as ArrayMesh
						var f0 := Time.get_ticks_usec()
						TalkingCharacter._fit_mouth_weights(copy)
						fit_ms = (Time.get_ticks_usec() - f0) / 1000.0
						break
				probe.free()
			var person := TalkingCharacter.new()
			person.model = ps
			var t2 := Time.get_ticks_usec()
			stage.add_child(person)
			var t3 := Time.get_ticks_usec()
			print("| %s | %s | %.0f | %.0f | %s |" % [path.get_file(), "fresh" if pass_i == 0 else "cached", (t1 - t0) / 1000.0,
					(t3 - t2) / 1000.0, "%.0f" % fit_ms if fit_ms >= 0.0 else "-"])
			person.queue_free()
			await process_frame
	quit(0)
