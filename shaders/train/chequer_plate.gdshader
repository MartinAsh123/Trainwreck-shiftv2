// chequer_plate.gdshader
// Steel tread ("chequer") plate: raised teardrop lugs in a herringbone pattern (alternating ±45°
// per cell), worn shiny on top, dirt collecting between the lugs and toward the edges.
// Pattern coordinates are the mesh's local XZ in metres, so scale the mesh, not the UVs.
shader_type spatial;

uniform vec3 steel : source_color = vec3(0.3, 0.3, 0.31);
uniform vec3 dirt : source_color = vec3(0.11, 0.1, 0.09);
uniform float cell = 0.032;              // lug pitch (m)
uniform vec2 half_size = vec2(0.4, 0.56);

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

// Lug height 0..1 at q (m).
float lug(vec2 q) {
	vec2 g = q / cell;
	vec2 id = floor(g);
	vec2 f = fract(g) - 0.5;
	float a = mod(id.x + id.y, 2.0) < 0.5 ? 0.785398 : -0.785398;
	vec2 r = vec2(cos(a) * f.x - sin(a) * f.y, sin(a) * f.x + cos(a) * f.y);
	// Elongated lozenge with rounded ends.
	float d = length(vec2(r.x * 0.42, r.y * 1.6));
	return 1.0 - smoothstep(0.1, 0.16, d);
}

void vertex() {
	v_pos = VERTEX;
}

void fragment() {
	vec2 q = v_pos.xz;
	float h = lug(q);
	float e = 0.0012;
	float hx = lug(q + vec2(e, 0.0)) - h;
	float hz = lug(q + vec2(0.0, e)) - h;
	// Relief on the top face only: lugs stand 1.5 mm proud.
	vec3 up_view = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	if (dot(NORMAL, up_view) > 0.5) {
		vec3 nm = normalize(vec3(-hx / e * 0.0015, 1.0, -hz / e * 0.0015));
		NORMAL = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(nm, 0.0)).xyz);
	}
	float grime = (1.0 - h) * (0.45 + 0.55 * vnoise(q * 40.0));
	vec2 to_edge = half_size - abs(q);
	grime = max(grime, 1.0 - smoothstep(0.0, 0.08, min(to_edge.x, to_edge.y)));
	float wear = h * (0.6 + 0.4 * vnoise(q * 9.0));
	vec3 col = mix(steel, dirt, grime * 0.75);
	col = mix(col, steel * 1.5, wear * 0.5);
	ALBEDO = col;
	METALLIC = mix(0.55, 0.85, wear);
	ROUGHNESS = mix(0.7, 0.32, wear) + grime * 0.15;
}
