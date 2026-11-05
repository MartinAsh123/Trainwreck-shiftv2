// snowfall.gdshader (particles)
// An endless field of snowflakes in a box around the emitter (which follows the camera). Each
// flake falls, flutters and is carried by the wind plus the air rushing past the moving train
// (train frame: the air moves toward +X at the train's speed). Flakes that leave the box wrap to
// the other side, so the density never changes however fast the train goes. Flakes inside the
// train's body are hidden (scaled to nothing) so it never snows indoors.
// CUSTOM.xyz carries the flake's velocity to the draw shader (motion streaks).
shader_type particles;
render_mode disable_velocity;

uniform vec3 box_half = vec3(35.0, 22.0, 35.0);
uniform vec3 air = vec3(0.0);             // wind + train speed, m/s (world)
uniform float fall = 1.1;                 // m/s
uniform float flutter = 0.5;
uniform float size_min = 0.012;
uniform float size_max = 0.03;
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
	vec3 origin = EMISSION_TRANSFORM[3].xyz;
	vec3 p = origin + (r * 2.0 - 1.0) * box_half;
	float sz = mix(size_min, size_max, pow(hash(seed + 3U), 2.0));
	TRANSFORM = mat4(vec4(sz, 0.0, 0.0, 0.0), vec4(0.0, sz, 0.0, 0.0), vec4(0.0, 0.0, sz, 0.0), vec4(p, 1.0));
	CUSTOM = vec4(0.0, -fall, 0.0, sz);
	COLOR = vec4(1.0);
}

void process() {
	uint seed = INDEX * 7919U;
	float ph = hash(seed + 5U) * 6.283;
	float fr = 0.6 + hash(seed + 6U) * 1.4;
	// Size from the current weather (flakes live for minutes, so it is not fixed at birth).
	float sz = mix(size_min, size_max, pow(hash(seed + 3U), 2.0));
	// Heavier flakes fall faster.
	float f = fall * (0.75 + sz / max(size_max, 0.001) * 0.5);
	vec3 v = air + vec3(sin(TIME * fr + ph) * flutter, -f, cos(TIME * fr * 0.8 + ph * 1.3) * flutter);
	vec3 p = TRANSFORM[3].xyz + v * DELTA;
	vec3 origin = EMISSION_TRANSFORM[3].xyz;
	vec3 rel = p - origin;
	rel = mod(rel + box_half, box_half * 2.0) - box_half;
	p = origin + rel;
	bool inside = all(greaterThan(p, hide_min)) && all(lessThan(p, hide_max))
			|| all(greaterThan(p, hide2_min)) && all(lessThan(p, hide2_max));
	float s = inside ? 0.0 : sz;
	TRANSFORM = mat4(vec4(s, 0.0, 0.0, 0.0), vec4(0.0, s, 0.0, 0.0), vec4(0.0, 0.0, s, 0.0), vec4(p, 1.0));
	CUSTOM = vec4(v, sz);
}
