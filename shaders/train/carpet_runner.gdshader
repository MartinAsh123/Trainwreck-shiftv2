// carpet_runner.gdshader
// 1930s aisle runner, in the carpet mesh's own space (origin at its center, X along the car):
// burgundy field with a row of gold-and-cream diamond medallions, a dark border with a chain of
// small diamonds between two gold lines, wool pile, and wear down the middle and near the ends.
shader_type spatial;

uniform vec3 field_color : source_color = vec3(0.36, 0.075, 0.07);
uniform vec3 border_color : source_color = vec3(0.13, 0.04, 0.035);
uniform vec3 gold : source_color = vec3(0.74, 0.56, 0.27);
uniform vec3 cream : source_color = vec3(0.86, 0.78, 0.6);
uniform vec3 navy : source_color = vec3(0.1, 0.12, 0.2);
uniform vec2 half_size = vec2(5.2, 0.35);   // set by PassengerCar
uniform float border_width = 0.075;
uniform float motif_pitch = 0.62;
uniform float wear_amount : hint_range(0.0, 1.0) = 0.5;

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

// Anti-aliased band where |d| < w (d in metres).
float band(float d, float w) {
	float aa = max(fwidth(d), 1e-4);
	return 1.0 - smoothstep(w - aa, w + aa, abs(d));
}

void vertex() {
	v_pos = VERTEX;
}

void fragment() {
	vec2 p = v_pos.xz;                        // x along the runner, y across
	vec2 edge_d = half_size - abs(p);         // distance to the long edges (y) and ends (x)
	float d = min(edge_d.x, edge_d.y);
	vec3 col = field_color;
	float gold_mask = 0.0;

	if (d < border_width) {
		// Border: dark band, gold lines at its inner and outer edge, a chain of small diamonds.
		col = border_color;
		float mid = border_width * 0.5;
		gold_mask = max(band(d - 0.012, 0.004), band(d - (border_width - 0.01), 0.0035));
		float along = edge_d.y < edge_d.x ? p.x : p.y;
		float cell = fract(along / 0.07) - 0.5;
		float dia = abs(cell) * 0.07 + abs(d - mid);
		float chain = band(dia - 0.016, 0.004);
		col = mix(col, cream, chain * 0.85);
		col = mix(col, gold, band(dia, 0.006));
	} else {
		// Field: medallions along the center line, small navy lozenges between them,
		// and a faint lattice in a darker red.
		float cx = (fract(p.x / motif_pitch) - 0.5) * motif_pitch;
		float fy = half_size.y - border_width;
		vec2 q = vec2(cx, p.y);
		float dia = abs(q.x) * 0.9 + abs(q.y) * 1.15;
		col = mix(col, gold, band(dia - 0.19, 0.008));
		col = mix(col, cream, band(dia - 0.155, 0.005));
		col = mix(col, navy, 1.0 - smoothstep(0.1, 0.106, dia));
		float petals = 0.5 + 0.5 * cos(atan(q.y, q.x) * 4.0);
		float r = length(q);
		col = mix(col, gold, 1.0 - smoothstep(0.035, 0.045, r - petals * 0.03));
		col = mix(col, field_color * 1.3, 1.0 - smoothstep(0.012, 0.018, r));
		// Lozenges halfway between medallions, near both edges of the field.
		float hx = (fract(p.x / motif_pitch) - 0.5 + 0.5 * sign(0.5 - fract(p.x / motif_pitch))) * motif_pitch;
		for (int s = 0; s < 2; s++) {
			float ly = (s == 0 ? 1.0 : -1.0) * fy * 0.62;
			float ld = abs(hx) * 1.4 + abs(p.y - ly) * 2.2;
			col = mix(col, navy, 1.0 - smoothstep(0.045, 0.05, ld));
			col = mix(col, gold, band(ld - 0.06, 0.004));
		}
		float lattice = band(fract((p.x + p.y) / 0.09) - 0.5, 0.02) + band(fract((p.x - p.y) / 0.09) - 0.5, 0.02);
		col = mix(col, col * 0.88, clamp(lattice, 0.0, 1.0) * 0.5 * step(0.22, dia));
		gold_mask = band(dia - 0.19, 0.008);
	}

	// Wool pile: fine fibres and tufts, directional sheen.
	float pile = vnoise(p * 900.0) * 0.5 + vnoise(p * 260.0) * 0.5;
	col *= 0.9 + 0.18 * pile;
	col *= 0.95 + 0.1 * fbm(p * 12.0);

	// Wear: flattened, paler pile down the middle and near the doors at both ends.
	float centre = 1.0 - smoothstep(0.05, half_size.y * 0.75, abs(p.y));
	float ends = 1.0 - smoothstep(0.0, 1.2, edge_d.x);
	float wear = clamp((centre * 0.8 + ends * 0.6) * (0.4 + 0.6 * fbm(p * 2.5 + 3.1)), 0.0, 1.0) * wear_amount;
	vec3 worn = mix(col, vec3(dot(col, vec3(0.3, 0.5, 0.2))), 0.35) * 1.18;
	col = mix(col, worn, wear);

	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.85, gold_mask);
	SPECULAR = 0.25;
	// Pile relief: tiny bumps so the carpet reads as fabric at grazing angles.
	float e = 0.0015;
	float h0 = vnoise(p * 300.0);
	vec3 bump = vec3(-(vnoise((p + vec2(e, 0.0)) * 300.0) - h0), 0.0, -(vnoise((p + vec2(0.0, e)) * 300.0) - h0)) * 0.6;
	NORMAL = normalize((VIEW_MATRIX * (MODEL_MATRIX * vec4(normalize(vec3(0.0, 1.0, 0.0) + bump * (1.0 - wear * 0.6)), 0.0))).xyz);
}
