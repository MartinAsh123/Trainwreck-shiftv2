// monster_eye.gdshader — a lidless, staring eye for MonsterFace, on a unit sphere looking along +Z: a sclera
// gone the colour of old teeth, shot with blood from the rim in; a pale washed iris and a pupil shrunk to a
// point; wet. black = 1 is an eye all black and glassy with a pale point in it.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform float pupil = 0.06;         // radius, in radians from the eye's axis
uniform float iris = 0.5;
uniform float black = 0.0;
uniform float seed = 0.0;

varying vec3 op;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	op = normalize(VERTEX);
}

void fragment() {
	vec3 p = normalize(op);
	float ang = acos(clamp(p.z, -1.0, 1.0));
	float th = atan(p.y, p.x);
	vec2 pol = vec2(cos(th), sin(th));
	// Blood: thin threads running in from the rim, forking as they go.
	float q = noise(vec3(pol * 7.0, seed)) + 0.5 * noise(vec3(pol * 19.0, ang * 3.0 + seed));
	float thread = 1.0 - smoothstep(0.0, 0.055, abs(q - 0.72 - 0.07 * sin(ang * 6.0 + th * 3.0)));
	float blood = thread * smoothstep(iris * 0.9, iris * 1.9, ang);
	blood = max(blood, smoothstep(1.2, 1.75, ang + 0.32 * noise(vec3(pol * 4.0, seed + 3.0))));
	vec3 sc = vec3(0.68, 0.58, 0.42) * (0.82 + 0.3 * noise(p * 6.0 + seed));
	sc = mix(sc, vec3(0.42, 0.02, 0.025), clamp(blood, 0.0, 1.0));
	// The iris: fibres round a point of a pupil.
	float fib = noise(vec3(pol * 21.0, seed + 7.0));
	vec3 ir = mix(vec3(0.05, 0.055, 0.05), vec3(0.34, 0.36, 0.3), fib * smoothstep(pupil, iris, ang));
	ir *= 1.0 - 0.75 * smoothstep(iris * 0.82, iris, ang);
	float in_iris = 1.0 - smoothstep(iris * 0.96, iris * 1.04, ang);
	float in_pupil = 1.0 - smoothstep(pupil * 0.9, pupil * 1.15, ang);
	vec3 c = mix(sc, ir, in_iris);
	c = mix(c, vec3(0.002), in_pupil);
	// All black: only a pale ring round the point.
	vec3 k = mix(vec3(0.004), vec3(0.75, 0.72, 0.6), (1.0 - smoothstep(pupil * 0.5, pupil * 1.3, ang)));
	ALBEDO = mix(c, k, black);
	ROUGHNESS = 0.07;
	SPECULAR = 0.85;
	EMISSION = mix(c * 0.09 * in_iris, k * 0.5, black);
}
