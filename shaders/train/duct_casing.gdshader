// duct_casing.gdshader
// Painted casing of the corridor's air-conditioning duct (a moulded cove along the wall/ceiling
// corner, built by SleeperCar). Cream enamel matching the ceiling, with:
//   - a row of small embossed rosettes along the upper front (the ceiling's motif, smaller)
//   - a gold pinstripe under the rosette row and a gilt bead line along the bottom edge
//   - recessed panel joints every `panel_len` along the car, with two domed screw heads
//   - over the doors (vertex COLOR.r = 1) a sunk panel with a gold line border
// UV.x = distance along the car (m), UV.y = distance down the profile from its top (m).
// UV2.x = profile length at this ring (m), UV2.y = height above the casing's underside (m).
shader_type spatial;

uniform vec3 cream : source_color = vec3(0.910, 0.867, 0.769);
uniform vec3 gold : source_color = vec3(0.62, 0.46, 0.22);
uniform float panel_len = 0.96;
uniform float motif = 0.11;          // rosette spacing (m)

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

float band(float t, float t0, float w) {
	float aa = max(fwidth(t), 1e-4);
	return 1.0 - smoothstep(w * 0.5, w * 0.5 + aa, abs(t - t0));
}

// Surface height (m) at (u along the car, v down the profile), with the gold mask in .y.
vec2 relief(float u, float v, float h_up, float total, float dip) {
	float h = 0.0;
	float g = 0.0;
	// Rosette row on the upper front.
	float rv = 0.05;                       // row centre, measured down from the top
	vec2 q = vec2((fract(u / motif) - 0.5) * motif, v - rv);
	float r = length(q);
	float ang = atan(q.y, q.x);
	float petals = 0.012 + 0.006 * cos(ang * 4.0);
	h += 0.0016 * (1.0 - smoothstep(petals - 0.002, petals + 0.001, r));
	h += 0.0008 * (1.0 - smoothstep(0.019, 0.022, abs(abs(q.x) + abs(q.y) - 0.026) + 0.019));
	// Pinstripe under the row and a bead along the bottom edge.
	g = max(g, band(v, 0.083, 0.003));
	float bead_v = total - 0.012;
	h += 0.0015 * band(v, bead_v, 0.006);
	g = max(g, band(v, bead_v, 0.004));
	// Joints: recessed grooves across the casing, two screws on the front.
	float ju = (fract(u / panel_len + 0.5) - 0.5) * panel_len;
	float joint = band(ju, 0.0, 0.004) * (1.0 - step(0.5, dip));
	h -= 0.0012 * joint;
	for (int k = 0; k < 2; k++) {
		float sv = k == 0 ? 0.11 : total - 0.05;
		float sd = length(vec2(ju - 0.018, v - sv));
		h += 0.0012 * (1.0 - smoothstep(0.003, 0.0045, sd)) * (1.0 - step(0.5, dip));
	}
	// Sunk panel over the doors, framed by a gold line.
	if (dip > 0.95) {
		float top_v = 0.1;
		float bot_v = total - 0.07;
		if (bot_v > top_v + 0.03) {
			float inside = step(top_v, v) * step(v, bot_v);
			h -= 0.0015 * inside;
			g = max(g, (band(v, top_v - 0.008, 0.002) + band(v, bot_v + 0.008, 0.002)));
		}
	}
	return vec2(h, clamp(g, 0.0, 1.0));
}

void fragment() {
	float u = UV.x;
	float v = UV.y;
	float total = UV2.x;
	float h_up = UV2.y;
	float dip = COLOR.r;
	vec2 rg = relief(u, v, h_up, total, dip);
	float e = 0.0015;
	float hu = relief(u + e, v, h_up, total, dip).x;
	float hv = relief(u, v + e, h_up, total, dip).x;
	// Height gradient -> normal map (tangent = +u, binormal = +v).
	vec3 nm = normalize(vec3(-(hu - rg.x) / e, -(hv - rg.x) / e, 1.0));
	NORMAL_MAP = nm * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;

	float n = vnoise(vec2(u * 9.0, v * 30.0));
	vec3 col = cream * (0.97 + 0.04 * n);
	// Dust settles on the upward-facing curve, faint soot along the bottom.
	col *= 1.0 - 0.06 * smoothstep(total - 0.05, total, v);
	col = mix(col, gold * (0.85 + 0.25 * n), rg.y);
	ALBEDO = col;
	ROUGHNESS = mix(0.55, 0.3, rg.y);
	METALLIC = 0.55 * rg.y;
	SPECULAR = 0.45;
}
