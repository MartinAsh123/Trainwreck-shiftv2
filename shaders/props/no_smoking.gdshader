// no_smoking.gdshader
// "No smoking" pictogram on a QuadMesh: black cigarette with a lit end and rising smoke, under a
// red prohibition circle with a diagonal bar (top-left to bottom-right), on cream enamel.
shader_type spatial;

uniform vec3 enamel : source_color = vec3(0.95, 0.93, 0.87);
uniform vec3 red : source_color = vec3(0.74, 0.07, 0.05);
uniform vec3 ink : source_color = vec3(0.04, 0.035, 0.03);

// Anti-aliased coverage of a signed distance (inside < 0).
float cover(float d) {
	float f = max(fwidth(d), 1e-5);
	return 1.0 - smoothstep(-f, f, d);
}

float box(vec2 p, vec2 c, vec2 half_size) {
	vec2 q = abs(p - c) - half_size;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
}

void fragment() {
	vec2 p = (UV - 0.5) * vec2(2.0, -2.0);
	vec3 col = enamel;
	float rough = 0.35;

	// Cigarette: long black body, a thin enamel gap, then the short lit end.
	float body = box(p, vec2(-0.12, -0.16), vec2(0.43, 0.085));
	float tip = box(p, vec2(0.41, -0.16), vec2(0.07, 0.085));
	float cig = min(body, tip);
	// Smoke: two wavy strokes rising from the lit end.
	float smoke = 1e3;
	for (int i = 0; i < 2; i++) {
		float x0 = 0.36 + 0.13 * float(i);
		float y = p.y;
		float wave = x0 + 0.045 * sin((y + 0.1 * float(i)) * 13.0);
		float d = abs(p.x - wave) - 0.026;
		d = max(d, max(0.0 - y, y - (0.52 - 0.08 * float(i))));
		smoke = min(smoke, d);
	}
	col = mix(col, ink, cover(min(cig, smoke)));

	// Prohibition circle and diagonal bar.
	float r = length(p);
	float ring = abs(r - 0.84) - 0.1;
	float bar = max(abs(p.x + p.y) * 0.70710678 - 0.085, r - 0.8);
	float red_mask = cover(min(ring, bar));
	col = mix(col, red, red_mask);

	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.4;
}
