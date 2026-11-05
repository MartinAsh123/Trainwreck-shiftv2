// window_glass.gdshader
// Carriage window glass. Clean glass has almost no body color: it is see-through head-on and turns
// into a mirror only at grazing angles (Schlick Fresnel), and its reflections (lamps, sky) are
// added on top instead of being faded by the transparency (premultiplied alpha). A thin film of
// grime collects along the bottom edge and in the corners, with a few very faint wipe marks.
// frosted = 1 turns it into milky privacy glass. Coordinates are in the window's own space
// (origin at the window center), so every window gets the same weathering pattern placement.
shader_type spatial;
render_mode blend_premul_alpha, depth_draw_opaque, cull_disabled;

uniform vec3 tint : source_color = vec3(0.78, 0.86, 0.84);
uniform float clarity : hint_range(0.0, 1.0) = 0.04;     // opacity of clean glass seen straight on
uniform float frosted : hint_range(0.0, 1.0) = 0.0;
uniform float dirt_amount : hint_range(0.0, 1.0) = 0.35;
uniform vec2 half_size = vec2(0.7, 0.45);
uniform vec3 grime_color : source_color = vec3(0.42, 0.38, 0.3);
// Faint fake reflections so clean glass still reads as glass head-on (lighting independent).
uniform float sheen : hint_range(0.0, 1.0) = 0.5;

varying vec3 v_pos;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
			mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
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

void vertex() {
	v_pos = VERTEX;
}

void fragment() {
	vec2 p = v_pos.xy;
	float edge_x = half_size.x - abs(p.x);
	float from_bottom = p.y + half_size.y;
	float from_top = half_size.y - p.y;
	float to_edge = min(edge_x, min(from_bottom, from_top));
	// Grime: a narrow band along the bottom rail and into the corners only.
	float grime = (1.0 - smoothstep(0.0, 0.06, from_bottom)) * 0.8;
	grime = max(grime, (1.0 - smoothstep(0.0, 0.025, to_edge)) * 0.5);
	grime *= 0.4 + 0.6 * fbm(p * 18.0);
	// Wipe marks: large, very faint arcs.
	float wipe = smoothstep(0.62, 0.85, fbm(p * vec2(3.0, 5.0) + 7.3)) * 0.08;
	// Fingerprints and hand smudges around the middle height, very faint.
	float prints = smoothstep(0.62, 0.8, fbm(p * 40.0 + 3.1)) * smoothstep(0.75, 0.6, fbm(p * 4.0 + 9.0));
	float d = clamp(grime + wipe + prints * 0.1, 0.0, 1.0) * dirt_amount;
	// Reflection sheen: two soft diagonal bands and a slow gradient, like a room reflected in glass.
	float diag = p.x * 0.8 + p.y;
	float bands = 0.6 * exp(-pow((fract(diag * 0.9 + 0.15) - 0.5) / 0.09, 2.0))
			+ 0.35 * exp(-pow((fract(diag * 0.9 + 0.42) - 0.5) / 0.035, 2.0));
	float glow = (0.25 + 0.75 * bands) * (0.75 + 0.25 * fbm(p * 2.5));

	float c = clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
	float fres = 0.04 + 0.96 * pow(1.0 - c, 5.0);

	vec3 milky = vec3(0.86, 0.87, 0.85) * (0.96 + 0.04 * fbm(p * 40.0));
	// Premultiplied: ALBEDO is the light the glass itself scatters (near zero when clean).
	float body = mix(clarity, 0.85, frosted);
	float a = clamp(body + fres * 0.6 * (1.0 - frosted) + d * 0.6, 0.0, 1.0);
	vec3 base = mix(tint * 0.02, milky, frosted);
	ALBEDO = mix(base, grime_color, d);
	float sh = sheen * (1.0 - frosted) * (1.0 - d);
	EMISSION = vec3(0.8, 0.86, 0.9) * glow * sh * 0.08;
	ALPHA = clamp(a + glow * sh * 0.05, 0.0, 1.0);
	ROUGHNESS = mix(mix(0.03, 0.55, frosted), 0.8, d);
	SPECULAR = 0.5;
}
