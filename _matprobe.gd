extends SceneTree
func _initialize() -> void:
	for p in ["res://assets/models/hd_props/bankers_lamp.gltf", "res://_wb_preview/hd/bankers_lamp.gltf"]:
		var n: Node = (load(p) as PackedScene).instantiate()
		root.add_child(n)
		print("== ", p)
		for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
			for s in mi.mesh.get_surface_count():
				var m := mi.get_active_material(s) as StandardMaterial3D
				if m == null:
					continue
				print("  ", mi.name, "/", s, " metallic ", m.metallic, " tex ", m.metallic_texture != null, " ch ", m.metallic_texture_channel, " rough ", m.roughness, " rtex ", m.roughness_texture != null, " rch ", m.roughness_texture_channel, " ao ", m.ao_enabled, " emis ", m.emission_enabled, " ", m.emission, " ", m.emission_energy_multiplier, " normal ", m.normal_enabled, " spec ", m.metallic_specular)
		n.queue_free()
	quit(0)
