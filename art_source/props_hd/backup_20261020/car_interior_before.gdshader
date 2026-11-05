// car_interior.gdshader
// Procedural 1930s carriage interior for every inner surface of the shell (model space, no textures):
//   floor            -> dark wooden floorboards
//   walls below sill -> varnished walnut panelling (skirting, recessed panels, top rail)
//   walls above sill -> cream embossed wallpaper, with a brown cornice line at the eave
//   curved ceiling   -> cream, transverse ribs, embossed Lincrusta panels, gold lining;
//                       shaded with the exact ellipse normal so the flat CSG strips don't show
// force_wood = true turns it into plain varnished walnut (used for window and door reveals).
shader_type spatial;

uniform vec3 wood_light : source_color = vec3(0.416, 0.227, 0.133);
uniform vec3 wood_dark : source_color = vec3(0.235, 0.120, 0.068);
uniform vec3 cream : source_color = vec3(0.910, 0.867, 0.769);
uniform vec3 lining_color : source_color = vec3(0.55, 0.40, 0.20);
uniform vec3 floor_light : source_color = vec3(0.47, 0.32, 0.19);
uniform vec3 floor_dark : source_color = vec3(0.25, 0.155, 0.09);

uniform float sill_y = 0.8;          // top of the panelling (window sill height)
uniform float panel_width = 0.62;    // panel pitch along the wall
uniform float frame_width = 0.07;    // stile and rail width around each panel
uniform float skirting_height = 0.12;
uniform float cap_height = 0.05;     // top rail at the sill
uniform float panel_depth = 0.006;
uniform float board_width = 0.14;
uniform float board_length = 2.2;

// Ceiling arc (set by PassengerCar): ellipse centered at (z = 0, y = eave_y).
uniform float eave_y = 2.0;
uniform float arc_rx = 1.295;
uniform float arc_ry = 0.3;
uniform float rib_pitch = 1.05;
uniform float emboss_scale = 0.2;    // size of one wallpaper / Lincrusta motif (m)
uniform float emboss_depth = 0.0018;

uniform bool force_wood = false;

varying vec3 v_pos;
varying vec3 v_nrm;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return s;
}

// Wood grain running along uv.x. Returns 0..1 (dark..light).
float grain(vec2 uv, float seed) {
	uv += seed * 17.0;
	float g = fbm(vec2(uv.x * 1.3, uv.y * 30.0));
	float rings = 0.5 + 0.5 * sin(uv.y * 70.0 + g * 9.0);
	return clamp(0.35 + 0.35 * rings + (g - 0.5) * 0.9, 0.0, 1.0);
}

// Varnished walnut at wood coordinates w = (along the grain, across it) in metres, for one piece
// of timber (`seed`). Flat-sawn growth rings bend into cathedral arches; long fine streaks, short
// dark pores, slow colour drift and the odd dark mineral streak. `late` returns the dark ring bands.
vec3 walnut(vec2 w, float seed, out float late) {
	// Distance from the heart line (w.y = 0 is the centre of a bookmatched panel); along the grain
	// the cut moves in and out of the log, so the rings close into arches ("cathedrals").
	float h = w.y + fract(seed * 7.31) * 0.03;
	float cut = 0.055 * (1.0 + sin(w.x * 3.6 + seed * 6.0)) + 0.01;
	w.x += seed * 13.7;
	float warp = fbm(vec2(w.x * 0.6, h * 6.0 + seed));
	float t = 22.0 * length(vec2(h, cut)) + warp * 2.2;
	t += 0.35 * vnoise(vec2(floor(t) * 1.7, seed * 3.0));        // uneven ring widths
	w.y = h + seed * 5.3;
	float r = fract(t);
	// Earlywood fades gradually into a dark latewood band that ends sharply.
	late = smoothstep(0.5, 0.88, r) * (1.0 - smoothstep(0.93, 1.0, r));
	float aa = clamp(fwidth(t) * 2.0, 0.0, 1.0);
	late = mix(late, 0.3, aa);                                    // no ring shimmer far away
	float streak = vnoise(vec2(w.x * 3.0, w.y * 260.0));
	float streak2 = vnoise(vec2(w.x * 1.2, w.y * 90.0 + 3.0));
	float pore = smoothstep(0.8, 0.93, vnoise(vec2(w.x * 90.0, w.y * 700.0)));
	pore *= 1.0 - smoothstep(0.0004, 0.0016, fwidth(w.y));       // pores only up close
	float drift = fbm(vec2(w.x * 0.25, w.y * 4.0) + seed * 3.1);
	float mineral = smoothstep(0.72, 0.8, vnoise(vec2(w.x * 0.8, w.y * 18.0) + seed * 9.0));
	float tone = 0.5 + 0.28 * (drift - 0.5) * 2.0 + 0.16 * (streak - 0.5) + 0.1 * (streak2 - 0.5) - 0.32 * late;
	vec3 col = mix(wood_dark, wood_light, clamp(tone, 0.0, 1.0));
	col *= mix(vec3(1.0), vec3(1.07, 0.97, 0.88), drift);        // honey to purple-brown
	col = mix(col, col * vec3(0.62, 0.6, 0.62), mineral * 0.6);
	col *= 1.0 - 0.3 * pore;
	return col;
}

// Signed distance inside the recessed panel of the dado at (u, v); negative outside a panel.
float panel_sdf(float u, float v) {
	float lu = mod(u, panel_width);
	float du = min(lu - frame_width * 0.5, panel_width - frame_width * 0.5 - lu);
	float v0 = skirting_height + frame_width;
	float v1 = sill_y - cap_height - frame_width;
	float dv = min(v - v0, v1 - v);
	return min(du, dv);
}

// Surface height of the panelling: panels recessed with a bevelled edge, skirting and rail proud.
float dado_height(float u, float v) {
	float d = panel_sdf(u, v);
	float h = -panel_depth * smoothstep(0.0, 0.018, d);
	h += 0.004 * step(v, skirting_height);
	h += 0.006 * step(sill_y - cap_height, v);
	return h;
}

// Ceiling Lincrusta motif (0..1 raised): diamond outline with a four-petal rosette, rows offset
// like brickwork so no continuous grid lines form.
float emboss(vec2 q) {
	q.x += 0.5 * mod(floor(q.y), 2.0);
	vec2 f = fract(q) - 0.5;
	float diamond = abs(f.x) + abs(f.y);
	float ring = 1.0 - smoothstep(0.02, 0.05, abs(diamond - 0.34));
	float r = length(f);
	float petals = 0.5 + 0.5 * cos(atan(f.y, f.x) * 4.0);
	float rosette = 1.0 - smoothstep(0.06, 0.1, r - petals * 0.05);
	return max(ring * 0.7, rosette);
}

// Period wallpaper (0..1 raised): fine vertical pinstripes with small rosettes in offset rows.
float wallpaper(vec2 q) {
	float stripe = 1.0 - smoothstep(0.03, 0.06, abs(fract(q.x * 2.0) - 0.5) - 0.44);
	vec2 g = q;
	g.x += 0.5 * mod(floor(g.y), 2.0);
	vec2 f = fract(g) - 0.5;
	float petals = 0.5 + 0.5 * cos(atan(f.y, f.x) * 5.0);
	float rosette = 1.0 - smoothstep(0.05, 0.09, length(f) - petals * 0.04);
	return max(stripe * 0.5, rosette);
}

// Ceiling relief at (u along the car, s along the arc): ribs proud, Lincrusta inside the panels.
float ceiling_height(float u, float s) {
	float du = abs(fract(u / rib_pitch + 0.5) - 0.5) * rib_pitch;
	float rib = 1.0 - smoothstep(0.03, 0.05, du);
	float panel = smoothstep(0.07, 0.1, du);
	return rib * 0.008 + panel * emboss(vec2(u, s) / emboss_scale) * emboss_depth;
}

// Floorboard surface height at q = (x, z): sunken joints, bevelled edges, domed nail heads.
float floor_height(vec2 q) {
	float row = floor(q.y / board_width);
	float off = hash12(vec2(row, 7.0)) * board_length;
	float fz = fract(q.y / board_width) * board_width;
	float fx = fract((q.x + off) / board_length) * board_length;
	float edge = min(min(fz, board_width - fz), min(fx, board_length - fx));
	float h = -(1.0 - smoothstep(0.0035, 0.012, edge)) * 0.0012 - (1.0 - smoothstep(0.0015, 0.0035, edge)) * 0.0015;
	for (int e = 0; e < 2; e++) {
		float nx = e == 0 ? fx - 0.03 : board_length - fx - 0.03;
		for (int k = 0; k < 2; k++) {
			float nz = fz - board_width * (k == 0 ? 0.28 : 0.72);
			h += max(0.0, 1.0 - length(vec2(nx, nz)) / 0.004) * 0.0006;
		}
	}
	return h;
}

vec3 to_view(vec3 nm, mat4 model, mat4 view) {
	return normalize((view * (model * vec4(nm, 0.0))).xyz);
}

// Anti-aliased thin line at t0 along coordinate t.
float line_at(float t, float t0, float w) {
	float aa = max(fwidth(t), 1e-4);
	return 1.0 - smoothstep(w * 0.5, w * 0.5 + aa, abs(t - t0));
}

void vertex() {
	v_pos = VERTEX;
	v_nrm = NORMAL;
}

void fragment() {
	vec3 p = v_pos;
	vec3 n = normalize(v_nrm);
	vec3 col;
	float rough;
	bool on_ceiling = !force_wood && p.y > eave_y + 0.002 && n.y < -0.05 && abs(n.x) < 0.5;

	bool varnish = false;
	if (force_wood) {
		// Plain varnished walnut for reveals and trims: grain along the face's horizontal axis.
		float u = abs(n.z) > abs(n.x) ? p.x : p.z;
		float late;
		col = walnut(vec2(u, p.y + (abs(n.y) > 0.5 ? (abs(n.z) > abs(n.x) ? p.z : p.x) : 0.0)), 3.0, late);
		rough = 0.5 + 0.12 * late;
		varnish = true;
	} else if (n.y > 0.8 && p.y < 0.05) {
		// Varnished floorboards along the car (X): staggered butt joints, per-board tone, bevelled
		// edges with grime in the gaps, two nail heads at each board end, and wear down the aisle.
		float row = floor(p.z / board_width);
		float off = hash12(vec2(row, 7.0)) * board_length;
		float seg = floor((p.x + off) / board_length);
		float id = hash12(vec2(row, seg));
		float id2 = hash12(vec2(seg, row) + 3.7);
		float fz = fract(p.z / board_width) * board_width;
		float fx = fract((p.x + off) / board_length) * board_length;
		float edge = min(min(fz, board_width - fz), min(fx, board_length - fx));

		// Grain: long flowing lines plus fine pores, per-board offset so neighbours differ.
		float g = grain(vec2(p.x * 0.8 + id * 11.0, p.z * 0.55 + id2), id * 5.0);
		float pores = vnoise(vec2(p.x * 180.0, p.z * 14.0 + id * 40.0));
		float tone = 0.55 + 0.45 * id;                     // light and dark boards
		col = mix(floor_dark, floor_light, clamp(g * 0.75 * tone + id2 * 0.2, 0.0, 1.0));
		col *= 0.93 + 0.1 * pores;
		// Slight honey/red shift per board, like different planks under the same varnish.
		col *= mix(vec3(1.0), vec3(1.08, 0.98, 0.9), id2 * 0.6);

		// Gaps and bevels: dark grime in the joint, a soft bevel just inside it.
		float gap = 1.0 - smoothstep(0.0015, 0.0035, edge);
		float bevel = 1.0 - smoothstep(0.0035, 0.012, edge);
		col = mix(col, col * 0.78, bevel * (1.0 - gap));
		col = mix(col, vec3(0.03, 0.022, 0.016), gap);

		// Nail heads: two per board end, 3 cm in from the joint.
		float nail = 0.0;
		for (int e = 0; e < 2; e++) {
			float nx = e == 0 ? fx - 0.03 : board_length - fx - 0.03;
			for (int k = 0; k < 2; k++) {
				float nz = fz - board_width * (k == 0 ? 0.28 : 0.72);
				nail = max(nail, 1.0 - smoothstep(0.0025, 0.004, length(vec2(nx, nz))));
			}
		}
		col = mix(col, vec3(0.06, 0.055, 0.05), nail);

		// Wear: the varnish is duller and paler along the aisle and in front of the seats.
		float wear = (1.0 - smoothstep(0.25, 0.75, abs(p.z))) * (0.5 + 0.5 * fbm(p.xz * 3.0));
		wear = clamp(wear, 0.0, 1.0);
		col = mix(col, col * 1.18 + vec3(0.02, 0.015, 0.01), wear * 0.45);
		// Scuffs: a few light scratches running along the car.
		float scratch = smoothstep(0.82, 0.95, vnoise(vec2(p.x * 3.0, p.z * 260.0))) * wear;
		col = mix(col, col * 1.35, scratch * 0.35);

		rough = mix(0.32, 0.62, wear);
		rough = mix(rough, 0.95, max(gap, bevel * 0.4));
		rough = mix(rough, 0.3, nail);
		rough += (pores - 0.5) * 0.08;

		// Relief: bevelled board edges and nail heads catch the light.
		float e2 = 0.001;
		float h0 = floor_height(p.xz);
		float dhx = (floor_height(p.xz + vec2(e2, 0.0)) - h0) / e2;
		float dhz = (floor_height(p.xz + vec2(0.0, e2)) - h0) / e2;
		NORMAL = to_view(normalize(vec3(-dhx, 1.0, -dhz)), MODEL_MATRIX, VIEW_MATRIX);
	} else if (on_ceiling) {
		// Position on the ellipse: angle a (0 at the right eave, PI/2 at the crown), arc coordinate s.
		float a = atan((p.y - eave_y) / arc_ry, p.z / arc_rx);
		float s = (PI * 0.5 - a) * (arc_rx + arc_ry) * 0.5;
		// Exact inward normal of the ellipse, so the flat strips of the mesh shade as one smooth curve.
		vec3 n_arc = -normalize(vec3(0.0, (p.y - eave_y) / (arc_ry * arc_ry), p.z / (arc_rx * arc_rx)));
		vec3 t_u = vec3(1.0, 0.0, 0.0);
		vec3 t_s = normalize(vec3(0.0, arc_ry * cos(a), -arc_rx * sin(a)));

		float e = 0.002;
		float h0 = ceiling_height(p.x, s);
		float dhu = (ceiling_height(p.x + e, s) - h0) / e;
		float dhs = (ceiling_height(p.x, s + e) - h0) / e;
		vec3 nm = normalize(n_arc - dhu * t_u - dhs * t_s);
		NORMAL = to_view(nm, MODEL_MATRIX, VIEW_MATRIX);

		float du = abs(fract(p.x / rib_pitch + 0.5) - 0.5) * rib_pitch;
		float rib = 1.0 - smoothstep(0.03, 0.05, du);
		float motif = emboss(vec2(p.x, s) / emboss_scale) * smoothstep(0.07, 0.1, du);
		col = cream * (0.93 + 0.07 * motif) * (1.0 - 0.06 * rib);
		// Gold lining: a double line either side of the crown, and a single line near each eave.
		float lines = max(line_at(abs(s), 0.42, 0.012), line_at(abs(s), 0.46, 0.006));
		float s_eave = (PI * 0.5) * (arc_rx + arc_ry) * 0.5;
		lines = max(lines, line_at(abs(s), s_eave - 0.06, 0.01));
		col = mix(col, lining_color, lines * (1.0 - rib));
		rough = mix(0.7, 0.45, lines);
	} else if (p.y > sill_y || n.y < -0.3) {
		// Cream embossed wallpaper on upper walls and partitions, brown cornice at the eave.
		float u = abs(n.z) > abs(n.x) ? p.x : p.z;
		float ws = emboss_scale * 0.6;
		float m = wallpaper(vec2(u, p.y) / ws);
		col = cream * (0.96 + 0.04 * m);
		float cornice = line_at(p.y, eave_y - 0.03, 0.03);
		col = mix(col, wood_dark, cornice);
		rough = mix(0.7, 0.4, cornice);

		float e = 0.002;
		float depth = emboss_depth * 0.4;
		vec3 t = abs(n.z) > abs(n.x) ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 0.0, 1.0);
		float h0 = m * depth;
		float dhu = (wallpaper(vec2(u + e, p.y) / ws) * depth - h0) / e;
		float dhv = (wallpaper(vec2(u, p.y + e) / ws) * depth - h0) / e;
		NORMAL = to_view(normalize(n - (dhu * t + dhv * vec3(0.0, 1.0, 0.0))), MODEL_MATRIX, VIEW_MATRIX);
	} else {
		// Walnut dado panelling below the sill.
		vec3 t = abs(n.z) > abs(n.x) ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 0.0, 1.0);
		float u = dot(p, t);
		float v = p.y;
		float d = panel_sdf(u, v);
		bool in_panel = d > 0.0;
		float lu = mod(u, panel_width);
		float pid = floor(u / panel_width + 0.5);
		float v0 = skirting_height + frame_width;
		float v1 = sill_y - cap_height - frame_width;
		bool in_rail_band = v > v0 && v < v1;
		bool is_stile = !in_panel && in_rail_band;
		// Each piece of timber gets its own figure: bookmatched vertical veneer in the panels
		// (mirrored about the panel centre line), vertical stiles, horizontal rails and skirting.
		vec2 w;
		float seed;
		if (in_panel) {
			w = vec2(v, abs(lu - panel_width * 0.5));
			seed = hash12(vec2(floor(u / panel_width), 1.0));
		} else if (is_stile) {
			w = vec2(v, lu);
			seed = hash12(vec2(pid, 2.0)) + 0.5;
		} else if (v < skirting_height) {
			w = vec2(u, v);
			seed = 0.31;
		} else if (v > sill_y - cap_height) {
			w = vec2(u, v + 0.37);
			seed = 0.73;
		} else {
			w = vec2(u, v);
			seed = v < v0 ? 0.19 : 0.57;
		}
		float late;
		col = walnut(w, seed, late);
		if (in_panel) {
			col *= 0.95;
		}
		if (v < skirting_height) {
			col *= 0.72;
		}
		// Bevel into each panel: shaded slope with a light bead just inside it.
		col *= 1.0 - 0.32 * (1.0 - smoothstep(0.0, 0.018, d)) * step(0.0, d);
		col = mix(col, col * 1.22, line_at(d, 0.022, 0.003) * step(0.0, d));
		// Hairline joints: rails butting into stiles, skirting/rail and rail/cap seams.
		float seam = 0.0;
		float du = min(lu, panel_width - lu);
		if (!in_rail_band && v > skirting_height && v < sill_y - cap_height) {
			seam = max(seam, line_at(du, frame_width * 0.5, 0.0015));
		}
		seam = max(seam, line_at(v, skirting_height, 0.0018));
		seam = max(seam, line_at(v, sill_y - cap_height, 0.0018));
		col = mix(col, col * 0.35, seam);
		rough = 0.5 + 0.12 * late + 0.3 * seam;
		varnish = true;

		// Relief from the height field (finite differences, 2 mm).
		float e = 0.002;
		float h0 = dado_height(u, v);
		float dhu = (dado_height(u + e, v) - h0) / e;
		float dhv = (dado_height(u, v + e) - h0) / e;
		vec3 nm = normalize(n - (dhu * t + dhv * vec3(0.0, 1.0, 0.0)));
		NORMAL = to_view(nm, MODEL_MATRIX, VIEW_MATRIX);
	}

	ALBEDO = col;
	ROUGHNESS = rough;
	if (varnish) {
		// French-polished finish: a glossy clear coat over the satin wood.
		CLEARCOAT = 0.75;
		CLEARCOAT_ROUGHNESS = 0.16;
	}
}
