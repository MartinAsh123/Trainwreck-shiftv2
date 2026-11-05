// gauge_dial.gdshader
// Instrument dial face on a QuadMesh: cream enamel face, graduated arc with major and minor ticks,
// coloured warning / normal bands, and a thin inner ring. Numbers, units and the needle are
// separate nodes. Angles are measured clockwise from 12 o'clock.
shader_type spatial;
render_mode cull_back;

uniform vec3 face_color : source_color = vec3(0.93, 0.9, 0.82);
uniform vec3 ink : source_color = vec3(0.06, 0.05, 0.045);
uniform float start_deg = -135.0;
uniform float sweep_deg = 270.0;
uniform int major_count = 6;          // number of major divisions
uniform int minor_per_major = 5;
uniform vec2 red_band = vec2(-1.0);   // fractions of the scale (x < 0 = none)
uniform vec2 green_band = vec2(-1.0);

// Anti-aliased band |d| < w in screen space.
float aa_band(float d, float w) {
	float f = max(fwidth(d), 1e-5);
	return 1.0 - smoothstep(w - f, w + f, abs(d));
}

void fragment() {
	vec2 p = (UV - 0.5) * vec2(2.0, -2.0);
	float r = length(p);
	if (r > 1.0) {
		discard;
	}
	float a = degrees(atan(p.x, p.y));                 // 0 at top, clockwise positive
	float t = (a - start_deg) / sweep_deg;
	t = t < -0.5 ? t + 360.0 / sweep_deg : t;          // wrap
	float on_scale = step(-0.002, t) * step(t, 1.002);
	float arc = radians(sweep_deg);

	vec3 col = face_color;
	// Soft vignette toward the bezel.
	col *= 1.0 - 0.12 * smoothstep(0.8, 1.0, r);

	float ink_mask = 0.0;
	// Scale arc line.
	ink_mask = max(ink_mask, aa_band(r - 0.9, 0.006) * on_scale);
	// Minor ticks.
	float n_minor = float(major_count * minor_per_major);
	float km = t * n_minor;
	float dm = (km - round(km)) / n_minor * arc * r;
	ink_mask = max(ink_mask, aa_band(dm, 0.0055) * step(0.815, r) * step(r, 0.9) * on_scale);
	// Major ticks.
	float kM = t * float(major_count);
	float dM = (kM - round(kM)) / float(major_count) * arc * r;
	ink_mask = max(ink_mask, aa_band(dM, 0.012) * step(0.74, r) * step(r, 0.93) * on_scale);
	// Half-way ticks (between majors) when the minor count is even.
	if (minor_per_major % 2 == 0) {
		float kH = t * float(major_count * 2);
		float dH = (kH - round(kH)) / float(major_count * 2) * arc * r;
		ink_mask = max(ink_mask, aa_band(dH, 0.0075) * step(0.78, r) * step(r, 0.9) * on_scale);
	}
	// Coloured bands just outside the arc.
	float band_r = aa_band(r - 0.945, 0.03);
	if (red_band.x >= 0.0) {
		float in_red = step(red_band.x, t) * step(t, red_band.y);
		col = mix(col, vec3(0.72, 0.08, 0.06), band_r * in_red);
	}
	if (green_band.x >= 0.0) {
		float in_green = step(green_band.x, t) * step(t, green_band.y);
		col = mix(col, vec3(0.12, 0.5, 0.2), band_r * in_green);
	}
	// Inner decorative ring and the hub area.
	ink_mask = max(ink_mask, aa_band(r - 0.25, 0.004) * 0.6);

	ALBEDO = mix(col, ink, ink_mask);
	ROUGHNESS = mix(0.45, 0.6, ink_mask);
	SPECULAR = 0.35;
}
