// monster_maw.gdshader — the wet red inside of the mouth (MonsterFace): gums and the bowl behind them, ridged
// and veined, going to black with depth. tint is the flesh; deep is 0 at the lips, 1 in the throat, given
// per vertex in COLOR.r.
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec3 tint : source_color = vec3(0.34, 0.03, 0.05);
uniform float ridges = 0.0;

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
	op = VERTEX;
}

void fragment() {
	float deep = clamp(COLOR.r, 0.0, 1.0);
	float n = noise(op * 150.0) + 0.5 * noise(op * 420.0);
	float rib = 0.5 + 0.5 * sin(op.z * 520.0 + 5.0 * noise(op * 70.0));
	vec3 c = tint * (0.55 + 0.6 * n);
	c = mix(c, c * 0.45, ridges * rib);
	c = mix(c, vec3(0.012, 0.001, 0.002), smoothstep(0.25, 0.95, deep));
	ALBEDO = c;
	ROUGHNESS = 0.16 + 0.2 * n;
	SPECULAR = 0.7;
	vec3 bump = vec3(noise(op * 240.0 + 11.0), noise(op * 240.0 + 23.0), 1.4) - vec3(0.5, 0.5, 0.0);
	NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(bump.x, bump.y, 0.0, 0.0)).xyz * 0.55);
}
