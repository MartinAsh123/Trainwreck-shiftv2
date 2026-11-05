// spindrift.gdshader (particles)
// Snow blown along the ground by the wind: wisps in a low slab around the camera (ground level near
// the line), carried by the wind and the air rushing past the train, skipping and settling. They
// wrap round the box like the snowfall, so the drift never thins out. Drawn by snowflake.gdshader
// (streaked along their motion) with a larger, fainter flake.
shader_type particles;
render_mode disable_velocity;

uniform vec3 box_half = vec3(30.0, 0.7, 30.0);
uniform float ground_y = -0.1;          // centre height of the slab (world)
uniform vec3 air = vec3(0.0);           // wind + train speed, m/s (world)
uniform float size_min = 0.05;
uniform float size_max = 0.16;
uniform vec3 hide_min = vec3(-85.0, -1.0, -1.55);
uniform vec3 hide_max = vec3(9.4, 4.8, 1.55);
// A second sheltered volume (the station booking hall nearby), far away when there is none.
uniform vec3 hide2_min = vec3(1e6);
uniform vec3 hide2_max = vec3(1e6);

float hash(uint n) {
	n = (n << 13U) ^ n;
	n = n * (n * n * 15731U + 789221U) + 1376312589U;
	return float(n & uint(0x7fffffff)) / float(0x7fffffff);
}

void start() {
	uint seed = INDEX * 7919U + RANDOM_SEED;
	vec3 r = vec3(hash(seed), hash(seed + 1U), hash(seed + 2U));
	vec3 origin = vec3(EMISSION_TRANSFORM[3].x, ground_y, EMISSION_TRANSFORM[3].z);
	vec3 p = origin + (r * 2.0 - 1.0) * box_half;
	float sz = mix(size_min, size_max, hash(seed + 3U));
	TRANSFORM = mat4(vec4(sz, 0.0, 0.0, 0.0), vec4(0.0, sz, 0.0, 0.0), vec4(0.0, 0.0, sz, 0.0), vec4(p, 1.0));
	CUSTOM = vec4(0.0, 0.0, 0.0, sz);
	COLOR = vec4(1.0);
}

void process() {
	uint seed = INDEX * 7919U;
	float ph = hash(seed + 5U) * 6.283;
	float sz = mix(size_min, size_max, hash(seed + 3U));
	// Gusty: each wisp moves at its own fraction of the air speed and skips up and down.
	float k = 0.55 + 0.45 * hash(seed + 6U);
	vec3 v = air * k;
	v.y = sin(TIME * (1.5 + hash(seed + 7U) * 2.0) + ph) * 0.25 * length(air.xz) * 0.08;
	vec3 p = TRANSFORM[3].xyz + v * DELTA;
	vec3 origin = vec3(EMISSION_TRANSFORM[3].x, ground_y, EMISSION_TRANSFORM[3].z);
	vec3 rel = p - origin;
	rel = mod(rel + box_half, box_half * 2.0) - box_half;
	p = origin + rel;
	// Hug the ground: fainter (smaller) toward the top of the slab.
	float hk = 1.0 - smoothstep(-0.2, 1.0, rel.y / box_half.y);
	bool inside = all(greaterThan(p, hide_min)) && all(lessThan(p, hide_max))
			|| all(greaterThan(p, hide2_min)) && all(lessThan(p, hide2_max));
	float s = inside ? 0.0 : sz * hk;
	TRANSFORM = mat4(vec4(s, 0.0, 0.0, 0.0), vec4(0.0, s, 0.0, 0.0), vec4(0.0, 0.0, s, 0.0), vec4(p, 1.0));
	CUSTOM = vec4(v, sz);
}
