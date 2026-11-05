class_name StaticMerge
extends RefCounted
## Combines a car's static MeshInstance3Ds into a few big meshes, one per material per spatial
## cell, to cut draw calls (the procedural cars are built from thousands of small parts).
## Left alone:
##   - anything under a node with a script (doors, locks, terminals, curtain sets…) or listed in
##     `keep` (curtains, rings and tie-backs that CurtainSet animates)
##   - transparent materials (their sorting must stay per object), Label3D, MultiMesh, skinned meshes
## Materials that are separate resources but identical are treated as one.
## The merged parts are hidden (kept in the tree, so nothing that looks them up breaks).

const CELL := 4.0          # metres along the car (X) per merged chunk

static func merge(root: Node3D, keep: Array = []) -> Dictionary:
	var skip := {}
	for k: Node in keep:
		skip[k.get_instance_id()] = true
	var groups := {}       # key -> {mat, items: [[mi, surface, xf]]}
	var mat_keys := {}     # material instance id -> canonical key
	var canon := {}        # canonical key -> material
	var count := 0
	var shadow_cells := {}  # cell -> items for the shadow-only proxy of that cell
	var inv_root := root.global_transform.affine_inverse()
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if not _eligible(mi, root, skip):
			# Not mergeable for its looks (object-space or transparent material), but if it is a static,
			# opaque part its shadow can still come from the cell's shadow proxy.
			if _shadow_only_ok(mi, root, skip):
				var xs := inv_root * mi.global_transform
				var cs := int(floor(xs.origin.x / CELL))
				if not shadow_cells.has(cs):
					shadow_cells[cs] = []
				for s2 in mi.mesh.get_surface_count():
					var a2 := mi.mesh.surface_get_arrays(s2)
					var sa2 := []
					sa2.resize(Mesh.ARRAY_MAX)
					sa2[Mesh.ARRAY_VERTEX] = a2[Mesh.ARRAY_VERTEX]
					sa2[Mesh.ARRAY_INDEX] = a2[Mesh.ARRAY_INDEX]
					shadow_cells[cs].append([sa2, xs])
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			continue
		var xf := inv_root * mi.global_transform
		var cell := int(floor(xf.origin.x / CELL))
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s)
			var mk: String = mat_keys.get(mat.get_instance_id(), "")
			if mk == "":
				mk = _mat_key(mat)
				mat_keys[mat.get_instance_id()] = mk
				if not canon.has(mk):
					canon[mk] = mat
			var arrs := mi.mesh.surface_get_arrays(s)
			var sig := _sig(arrs)
			# Materials that work in object space (procedural grain, triplanar) keep each part's own
			# orientation and scale: the merged mesh gets that basis, so only the origin moves.
			var frame := Basis.IDENTITY
			var fkey := ""
			if _object_space(mat):
				frame = xf.basis
				fkey = "%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f" % [frame.x.x, frame.x.y, frame.x.z,
						frame.y.x, frame.y.y, frame.y.z, frame.z.x, frame.z.y, frame.z.z]
			# Shadows: one combined, shadow-only mesh per cell casts for every opaque part in it (all
			# materials together), so a lamp's shadow pass draws a handful of meshes, not hundreds.
			# Cut-out materials (alpha scissor / discard) keep casting their own, holed shadows.
			var shadow := mi.cast_shadow
			if shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and not _cutout(mat):
				if not shadow_cells.has(cell):
					shadow_cells[cell] = []
				var sa := []
				sa.resize(Mesh.ARRAY_MAX)
				sa[Mesh.ARRAY_VERTEX] = arrs[Mesh.ARRAY_VERTEX]
				sa[Mesh.ARRAY_INDEX] = arrs[Mesh.ARRAY_INDEX]
				shadow_cells[cell].append([sa, xf])
				shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var key := "%s|%s|%d|%d|%d|%s" % [mk, sig, cell, shadow, mi.layers, fkey]
			if not groups.has(key):
				groups[key] = {"mat": canon[mk], "items": [], "shadow": shadow, "layers": mi.layers, "frame": frame}
			groups[key].items.append([arrs, Transform3D(frame, Vector3.ZERO).affine_inverse() * xf])
		mi.set_meta("_merged", true)
		count += 1
	# Build the merged meshes.
	var holder := Node3D.new()
	holder.name = "MergedStatic"
	root.add_child(holder)
	var made := 0
	for key in groups:
		var g: Dictionary = groups[key]
		var mesh := _combine(g.items)
		if mesh == null:
			continue
		mesh.surface_set_material(0, g.mat)
		var out := MeshInstance3D.new()
		out.mesh = mesh
		out.basis = g.frame
		out.cast_shadow = g.shadow
		out.layers = g.layers
		holder.add_child(out)
		made += 1
	var proxies := 0
	var shadow_mat := StandardMaterial3D.new()
	shadow_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for cell in shadow_cells:
		var pm := _combine(shadow_cells[cell])
		if pm == null:
			continue
		pm.surface_set_material(0, shadow_mat)
		var sp := MeshInstance3D.new()
		sp.name = "ShadowProxy"
		sp.mesh = pm
		sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		holder.add_child(sp)
		proxies += 1
	# Hide what was merged (all surfaces of a merged instance went into groups).
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		if n.has_meta("_merged"):
			(n as MeshInstance3D).visible = false
	return {"merged_instances": count, "draw_meshes": made, "materials": canon.size(), "shadow_proxies": proxies}

# A static, opaque mesh that casts shadows (whatever its material looks like): its shadow can be
# drawn by the proxy instead.
static func _shadow_only_ok(mi: MeshInstance3D, root: Node, skip: Dictionary) -> bool:
	if mi.mesh == null or not mi.is_visible_in_tree() or mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
		return false
	if mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY or mi.get_script() != null:
		return false
	if mi.skeleton != NodePath("") and mi.get_node_or_null(mi.skeleton) != null:
		return false
	if mi.mesh is ArrayMesh and (mi.mesh as ArrayMesh).get_blend_shape_count() > 0:
		return false
	for s in mi.mesh.get_surface_count():
		var m := mi.get_active_material(s)
		if m == null or _transparent(m) or _cutout(m):
			return false
		if mi.mesh is ArrayMesh and (mi.mesh as ArrayMesh).surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
			return false
	var n: Node = mi
	while n != null and n != root:
		if skip.has(n.get_instance_id()) or n.has_meta("dynamic"):
			return false
		if n != mi and n.get_script() != null:
			return false
		if n is AnimatableBody3D or n is RigidBody3D or n is CharacterBody3D:
			return false
		n = n.get_parent()
	return true

static func _eligible(mi: MeshInstance3D, root: Node, skip: Dictionary) -> bool:
	if mi.mesh == null or not mi.is_visible_in_tree() or mi.skeleton != NodePath("") and mi.get_node_or_null(mi.skeleton) != null:
		return false
	if mi.get_script() != null or mi.material_overlay != null or mi.has_meta("_merged"):
		return false
	if mi.mesh is ArrayMesh and (mi.mesh as ArrayMesh).get_blend_shape_count() > 0:
		return false
	# Every surface must be mergeable; otherwise keep the whole instance as it is.
	for s in mi.mesh.get_surface_count():
		var m := mi.get_active_material(s)
		if m == null or _transparent(m):
			return false
		# Patterns computed in the part's own space (triplanar, procedural grain) would shift.
		if _object_space(m):
			return false
		if mi.mesh is ArrayMesh and (mi.mesh as ArrayMesh).surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
			return false
	var n: Node = mi
	while n != null and n != root:
		if skip.has(n.get_instance_id()):
			return false
		if n.has_meta("dynamic"):              # moving parts (wheelsets…)
			return false
		if n != mi and n.get_script() != null:
			return false
		if n is AnimatableBody3D or n is RigidBody3D or n is CharacterBody3D:
			return false
		n = n.get_parent()
	return true

# Does the material's look depend on the object's own space (so merging would move its pattern)?
static func _object_space(m: Material) -> bool:
	if m is BaseMaterial3D:
		var b := m as BaseMaterial3D
		return (b.uv1_triplanar and not b.uv1_world_triplanar) or (b.uv2_triplanar and not b.uv2_world_triplanar)
	if m is ShaderMaterial and (m as ShaderMaterial).shader:
		var code := (m as ShaderMaterial).shader.code
		return code.contains("MODEL_MATRIX") or code.contains("= VERTEX") or code.contains("NODE_POSITION")
	return false

# Materials that cut holes (alpha scissor / hash, or a shader that discards): their shadows have holes.
static func _cutout(m: Material) -> bool:
	if m is BaseMaterial3D:
		var t := (m as BaseMaterial3D).transparency
		return t == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR or t == BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
	if m is ShaderMaterial and (m as ShaderMaterial).shader:
		var code := (m as ShaderMaterial).shader.code
		return code.contains("discard") or code.contains("ALPHA_SCISSOR")
	return false

static func _transparent(m: Material) -> bool:
	if m is BaseMaterial3D:
		var b := m as BaseMaterial3D
		return b.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED and b.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR \
				and b.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
	if m is ShaderMaterial:
		var sh := (m as ShaderMaterial).shader
		if sh == null:
			return true
		var code := sh.code
		return code.contains("ALPHA") and not code.contains("ALPHA_SCISSOR") or code.contains("blend_add") or code.contains("blend_mul")
	return true

# Identical materials get the same key: every stored property, objects by identity.
static func _mat_key(m: Material) -> String:
	var parts := PackedStringArray()
	parts.append(m.get_class())
	if m is ShaderMaterial:
		var sm := m as ShaderMaterial
		parts.append(str(sm.shader.get_instance_id() if sm.shader else 0))
		if sm.shader:
			for u in sm.shader.get_shader_uniform_list():
				parts.append("%s=%s" % [u.name, _val(sm.get_shader_parameter(u.name))])
		parts.append(str(sm.next_pass.get_instance_id() if sm.next_pass else 0))
		parts.append(str(sm.render_priority))
		return "|".join(parts)
	for p in m.get_property_list():
		if not (p.usage & PROPERTY_USAGE_STORAGE):
			continue
		if p.name in ["resource_name", "resource_path", "resource_local_to_scene", "script", "metadata/_gltf_primary_texture_coord"]:
			continue
		parts.append("%s=%s" % [p.name, _val(m.get(p.name))])
	return "|".join(parts)

static func _val(v: Variant) -> String:
	if v is Object:
		return "#%d" % (v as Object).get_instance_id() if v != null else "null"
	return var_to_str(v)

# Which vertex attributes a surface carries.
static func _sig(arrs: Array) -> String:
	var s := ""
	for i in [Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT, Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2]:
		s += "1" if arrs[i] != null and (arrs[i] as Variant).size() > 0 else "0"
	return s

static func _combine(items: Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var tans := PackedFloat32Array()
	var cols := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	var first: Array = items[0][0]
	var has_n: bool = first[Mesh.ARRAY_NORMAL] != null and (first[Mesh.ARRAY_NORMAL] as PackedVector3Array).size() > 0
	var has_t: bool = first[Mesh.ARRAY_TANGENT] != null and (first[Mesh.ARRAY_TANGENT] as PackedFloat32Array).size() > 0
	var has_c: bool = first[Mesh.ARRAY_COLOR] != null and (first[Mesh.ARRAY_COLOR] as PackedColorArray).size() > 0
	var has_uv: bool = first[Mesh.ARRAY_TEX_UV] != null and (first[Mesh.ARRAY_TEX_UV] as PackedVector2Array).size() > 0
	var has_uv2: bool = first[Mesh.ARRAY_TEX_UV2] != null and (first[Mesh.ARRAY_TEX_UV2] as PackedVector2Array).size() > 0
	for it: Array in items:
		var a: Array = it[0]
		var xf: Transform3D = it[1]
		var base := verts.size()
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		if v.is_empty():
			continue
		verts.append_array(xf * v)
		var nb := xf.basis.inverse().transposed()
		var uniform := xf.basis.is_conformal()
		if has_n:
			var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
			if uniform:
				var rot := Transform3D(xf.basis.orthonormalized(), Vector3.ZERO)
				norms.append_array(rot * n)
			else:
				var out := PackedVector3Array()
				out.resize(n.size())
				for i in n.size():
					out[i] = (nb * n[i]).normalized()
				norms.append_array(out)
		if has_t:
			var t: PackedFloat32Array = a[Mesh.ARRAY_TANGENT]
			var flip := xf.basis.determinant() < 0.0
			var out_t := PackedFloat32Array()
			out_t.resize(t.size())
			for i in range(0, t.size(), 4):
				var tv := (xf.basis * Vector3(t[i], t[i + 1], t[i + 2])).normalized()
				out_t[i] = tv.x
				out_t[i + 1] = tv.y
				out_t[i + 2] = tv.z
				out_t[i + 3] = -t[i + 3] if flip else t[i + 3]
			tans.append_array(out_t)
		if has_c:
			cols.append_array(a[Mesh.ARRAY_COLOR])
		if has_uv:
			uv.append_array(a[Mesh.ARRAY_TEX_UV])
		if has_uv2:
			uv2.append_array(a[Mesh.ARRAY_TEX_UV2])
		var ind = a[Mesh.ARRAY_INDEX]
		var flip_w := xf.basis.determinant() < 0.0
		var pi: PackedInt32Array
		if ind == null or (ind as PackedInt32Array).is_empty():
			pi = PackedInt32Array(range(v.size()))
		else:
			pi = ind
		var start := idx.size()
		idx.resize(start + pi.size())
		if flip_w:
			for i in range(0, pi.size(), 3):
				idx[start + i] = base + pi[i]
				idx[start + i + 1] = base + pi[i + 2]
				idx[start + i + 2] = base + pi[i + 1]
		else:
			for i in pi.size():
				idx[start + i] = base + pi[i]
	if verts.is_empty():
		return null
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	if has_n:
		arr[Mesh.ARRAY_NORMAL] = norms
	if has_t:
		arr[Mesh.ARRAY_TANGENT] = tans
	if has_c:
		arr[Mesh.ARRAY_COLOR] = cols
	if has_uv:
		arr[Mesh.ARRAY_TEX_UV] = uv
	if has_uv2:
		arr[Mesh.ARRAY_TEX_UV2] = uv2
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh
