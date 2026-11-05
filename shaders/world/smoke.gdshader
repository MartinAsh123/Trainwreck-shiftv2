// smoke.gdshader (particles) — locomotive exhaust.
// Each particle leaves the chimney at a speed set by the current exhaust beat (`puff`, 0..1,
// pulsed by LocoSmoke four times per driving-wheel turn), then drags toward the air velocity
// (train frame: the air streams toward +X at the train's speed), rises while warm, grows and thins.
// COLOR.a carries the opacity; CUSTOM.x = age 0..1, CUSTOM.y = start size.
shader_type particles;

uniform vec3 air = vec3(0.0);
uniform float puff = 0.3;
uniform float drag = 1.6;
uniform float rise = 1.2;
uniform float grow = 2.6;
uniform float base_size = 0.45;

float hash(uint n) {
	n = (n << 13U) ^ n;
	n = n * (n * n * 15731U + 789221U) + 1376312589U;
	return float(n & uint(0x7fffffff)) / float(0x7fffffff);
}

void start() {
	uint seed = INDEX * 1013U + RANDOM_SEED;
	vec3 jitter = vec3(hash(seed), hash(seed + 1U), hash(seed + 2U)) - 0.5;
	vec3 p = EMISSION_TRANSFORM[3].xyz + jitter * vec3(0.25, 0.05, 0.25);
	float up = mix(1.5, 9.0, puff) * (0.8 + 0.4 * hash(seed + 3U));
	VELOCITY = vec3(jitter.x * 1.2, up, jitter.z * 1.2);
	float sz = base_size * mix(0.7, 1.3, puff) * (0.8 + 0.4 * hash(seed + 4U));
	TRANSFORM = mat4(vec4(sz, 0, 0, 0), vec4(0, sz, 0, 0), vec4(0, 0, sz, 0), vec4(p, 1.0));
	CUSTOM = vec4(0.0, sz, hash(seed + 5U), 0.0);
	COLOR = vec4(1.0, 1.0, 1.0, mix(0.45, 0.85, puff));
}

void process() {
	float age = clamp(CUSTOM.x + DELTA / LIFETIME, 0.0, 1.0);
	CUSTOM.x = age;
	VELOCITY += (air - VELOCITY) * min(drag * DELTA, 1.0);
	VELOCITY.y += rise * (1.0 - age) * DELTA;
	vec3 p = TRANSFORM[3].xyz + VELOCITY * DELTA;
	float sz = CUSTOM.y * (1.0 + grow * sqrt(age) * 3.0);
	TRANSFORM = mat4(vec4(sz, 0, 0, 0), vec4(0, sz, 0, 0), vec4(0, 0, sz, 0), vec4(p, 1.0));
	COLOR.a *= 1.0 - DELTA / LIFETIME * 0.6;
	if (age >= 1.0) {
		ACTIVE = false;
	}
}
