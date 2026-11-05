// car_exterior.gdshader
// Procedural 1930s coach livery for the car body's outer skin (model space, no textures):
// bottle-green paint with gold lining, grey roof with soot, black skirt with rising grime.
// Heights are in the car's local space (floor top = 0); PassengerCar sets them from its layout.
shader_type spatial;

uniform vec3 paint_color : source_color = vec3(0.169, 0.290, 0.251);
uniform vec3 roof_color : source_color = vec3(0.227, 0.235, 0.239);
uniform vec3 skirt_color : source_color = vec3(0.102, 0.102, 0.102);
uniform vec3 lining_color : source_color = vec3(0.780, 0.620, 0.290);

uniform float roof_start_y = 2.08;   // above this the body is roof
uniform float skirt_top_y = 0.05;    // below this the body is black skirt
uniform float lining_y1 = 1.78;      // gold line above the windows
uniform float lining_y2 = 0.74;      // gold line between the stripe and the windows
uniform float lining_width = 0.012;
uniform float waist_y = 0.67;        // top of the waist moulding; panel seams run below it
uniform float panel_pitch = 1.2;     // spacing of the vertical panel seams on the lower body
uniform float seam_strength : hint_range(0.0, 1.0) = 0.45;
// Roof arc (set by PassengerCar): outer ellipse centered at (z = 0, y = eave_y).
uniform float eave_y = 2.0;
uniform float roof_rx = 1.495;
uniform float roof_ry = 0.45;

// Weathering (window and door positions are set by PassengerCar).
uniform float window_xs[24];
uniform int window_count = 0;
uniform float window_half_w = 0.7;
uniform float window_bottom_y = 0.8;
uniform float door_x = -7.2;
uniform float door_half_w = 0.4;
uniform float fade_amount : hint_range(0.0, 1.0) = 0.35;
uniform float rivet_pitch = 0.09;
uniform float paint_roughness : hint_range(0.0, 1.0) = 0.32;
uniform float grime_amount : hint_range(0.0, 1.0) = 0.35;
uniform float soot_amount : hint_range(0.0, 1.0) = 0.55;

// Scanned PBR detail (CC0, art_source/props_hd): paint surface on the body, painted canvas on the roof,
// projected triplanar in model space. Off when the textures are not assigned.
uniform bool use_detail = false;
uniform sampler2D paint_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D paint_orm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D roof_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D roof_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float paint_tiles_per_m = 0.7;
uniform float roof_tiles_per_m = 0.6;
uniform float paint_normal_strength : hint_range(0.0, 2.0) = 0.45;
uniform float roof_normal_strength : hint_range(0.0, 2.0) = 0.9;

varying vec3 v_pos;
varying vec3 v_nrm;

vec3 tri_weights(vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	return w / max(w.x + w.y + w.z, 1e-4);
}

// Triplanar tangent-space normal map, returned as a model-space offset (UDN blend).
vec3 tri_normal(sampler2D tex, vec3 p, vec3 n, float k) {
	vec3 w = tri_weights(n);
	vec2 tx = texture(tex, p.zy).xy * 2.0 - 1.0;
	vec2 ty = texture(tex, p.xz).xy * 2.0 - 1.0;
	vec2 tz = texture(tex, p.xy).xy * 2.0 - 1.0;
	return (vec3(0.0, tx.y, tx.x * sign(n.x)) * w.x + vec3(ty.x, 0.0, ty.y) * w.y + vec3(tz.x * sign(n.z), tz.y, 0.0) * w.z) * k;
}

vec4 tri_sample(sampler2D tex, vec3 p, vec3 n) {
	vec3 w = tri_weights(n);
	return texture(tex, p.zy) * w.x + texture(tex, p.xz) * w.y + texture(tex, p.xy) * w.z;
}

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

// Anti-aliased thin horizontal line at height y0.
float hline(float y, float y0, float w) {
	float aa = max(fwidth(y), 1e-4);
	return 1.0 - smoothstep(w * 0.5, w * 0.5 + aa, abs(y - y0));
}

void vertex() {
	v_pos = VERTEX;
	v_nrm = NORMAL;
}

void fragment() {
	vec3 p = v_pos;
	vec3 n = normalize(v_nrm);
	vec3 col = paint_color;
	float rough = paint_roughness;
	float metal = 0.0;

	// Grime rising from the bottom of the sides.
	float grime = 1.0 - smoothstep(skirt_top_y, skirt_top_y + 0.5, p.y);
	grime *= 0.55 + 0.45 * fbm(vec2(p.x * 3.0 + p.z, p.y * 14.0));
	col = mix(col, col * 0.5, grime * grime_amount);
	rough = mix(rough, 0.7, grime * grime_amount);

	// Vertical panel seams on the lower body of the side walls.
	if (abs(n.z) > 0.7 && p.y < waist_y && p.y > skirt_top_y) {
		float aa = max(fwidth(p.x), 1e-4);
		float d = abs(fract(p.x / panel_pitch + 0.5) - 0.5) * panel_pitch;
		float seam = 1.0 - smoothstep(0.004, 0.004 + aa, d);
		col = mix(col, col * 0.35, seam * seam_strength);
	}

	// Lining on side and end walls.
	if (abs(n.y) < 0.5) {
		float line = max(hline(p.y, lining_y1, lining_width), hline(p.y, lining_y2, lining_width));
		col = mix(col, lining_color, line);
		rough = mix(rough, 0.3, line);
		metal = mix(metal, 0.85, line);
	}

	// Roof: grey with lengthwise soot streaks, and a thin dark rain strip where it starts.
	if (p.y > roof_start_y) {
		vec3 rc = roof_color * (0.9 + 0.2 * fbm(vec2(p.x * 0.7, p.z * 5.0)));
		float soot = smoothstep(0.45, 0.8, fbm(vec2(p.x * 0.25, p.z * 9.0)));
		col = mix(rc, rc * 0.4, soot * soot_amount);
		rough = 0.85;
		metal = 0.0;
	}
	col = mix(col, skirt_color, hline(p.y, roof_start_y, 0.025) * step(abs(n.y), 0.95));

	bool side_wall = abs(n.z) > 0.7;
	vec3 rivet_n = vec3(0.0);

	if (side_wall && p.y <= roof_start_y) {

		// Hand grime around the boarding door.
		float dxd = abs(p.x - door_x) - door_half_w;
		float door_grime = (1.0 - smoothstep(0.0, 0.35, dxd)) * smoothstep(0.1, 0.3, dxd + 0.15);
		door_grime *= smoothstep(0.3, 0.9, p.y) * (1.0 - smoothstep(1.3, 1.8, p.y));
		door_grime *= 0.5 + 0.5 * fbm(vec2(p.x * 12.0, p.y * 12.0));
		col = mix(col, col * 0.55, door_grime * 0.7);

		// Rivet rows: along each panel seam, above the skirt and under the waist moulding.
		if (p.y < waist_y && p.y > skirt_top_y) {
			float seam_d = (fract(p.x / panel_pitch + 0.5) - 0.5) * panel_pitch;
			vec2 cell_v = vec2(seam_d - sign(seam_d) * 0.035, mod(p.y, rivet_pitch) - rivet_pitch * 0.5);
			float r_v = abs(seam_d) < 0.06 ? length(cell_v) : 1.0;
			vec2 cell_h1 = vec2(mod(p.x, rivet_pitch) - rivet_pitch * 0.5, p.y - (skirt_top_y + 0.035));
			vec2 cell_h2 = vec2(mod(p.x, rivet_pitch) - rivet_pitch * 0.5, p.y - (waist_y - 0.03));
			vec2 cell = cell_v;
			float r = r_v;
			if (length(cell_h1) < r) { cell = cell_h1; r = length(cell_h1); }
			if (length(cell_h2) < r) { cell = cell_h2; r = length(cell_h2); }
			float radius = 0.007;
			if (r < radius) {
				vec2 slope = cell / radius;
				rivet_n = vec3(slope.x, slope.y, 0.0);
				col *= 1.08;
				rough = 0.35;
			}
		}
	}

	// Sun-faded roof: paler and flatter toward the crown.
	if (p.y > roof_start_y) {
		float crown = smoothstep(0.3, 1.0, n.y);
		vec3 faded = mix(col, vec3(dot(col, vec3(0.33))) * 1.5, 0.5);
		col = mix(col, faded, crown * fade_amount * (0.6 + 0.4 * fbm(vec2(p.x * 0.8, p.z * 3.0))));
	}

	// Black skirt and underside.
	float skirt = max(step(p.y, skirt_top_y), step(n.y, -0.6));
	col = mix(col, skirt_color, skirt);
	rough = mix(rough, 0.75, skirt);
	metal = mix(metal, 0.0, skirt);

	// Subtle unevenness in the paint.
	rough = clamp(rough + (fbm(vec2(p.x * 6.0 + p.z * 6.0, p.y * 6.0)) - 0.5) * 0.08, 0.05, 1.0);

	// Shade the roof with the exact ellipse normal, so its flat mesh strips read as one smooth curve.
	vec3 nm = n;
	bool custom_n = false;
	bool on_roof = p.y > eave_y + 0.002 && n.y > 0.05 && abs(n.x) < 0.5;
	if (on_roof) {
		nm = normalize(vec3(0.0, (p.y - eave_y) / (roof_ry * roof_ry), p.z / (roof_rx * roof_rx)));
		custom_n = true;
	} else if (rivet_n != vec3(0.0)) {
		// Dome-shaped rivet head: tilt the wall normal toward the rivet's edge.
		nm = normalize(n + vec3(rivet_n.x, rivet_n.y, 0.0) * 0.8);
		custom_n = true;
	}
	if (use_detail) {
		if (p.y > roof_start_y) {
			// Painted canvas roof: weave relief and the canvas's own tone variation.
			vec3 q = p * roof_tiles_per_m;
			float canvas = dot(tri_sample(roof_albedo, q, n).rgb, vec3(0.333));
			col *= clamp(0.55 + canvas * 1.6, 0.6, 1.35);
			nm = normalize(nm + tri_normal(roof_normal, q, n, roof_normal_strength));
		} else {
			// Paint: brush marks and orange peel in the normal, uneven gloss from the scan.
			vec3 q = p * paint_tiles_per_m;
			float k = paint_normal_strength * (1.0 - skirt * 0.5);
			nm = normalize(nm + tri_normal(paint_normal, q, n, k));
			float g = tri_sample(paint_orm, q, n).g;
			rough = clamp(rough * (0.75 + 0.6 * g), 0.05, 1.0);
		}
		custom_n = true;
	}
	if (custom_n) {
		NORMAL = normalize((VIEW_MATRIX * (MODEL_MATRIX * vec4(nm, 0.0))).xyz);
	}

	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
}
