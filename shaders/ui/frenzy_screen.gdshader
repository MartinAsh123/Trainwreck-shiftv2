// frenzy_screen.gdshader — what fear does to the picture (AnomalyFrenzy), a full-screen pass over everything
// drawn so far: the lens bulging, colour fringing out from the middle, the edges going soft and dark,
// the blood-vessels of a tunnel closing in on the beat of the heart, tearing bands, grain.
// The tearing bands are adapted from glitch.gdshader, and the fringing from chromatic.gdshader, of
// Godot Post Process by Korin (MIT, see LICENSE-Godot-Post-Process-Plugin.txt beside this file).
shader_type canvas_item;

uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform float warp = 0.0;           // 0..1 the lens bulges
uniform float fringe = 0.0;         // 0..1 colour fringing
uniform float soft = 0.0;           // 0..1 the edges out of focus
uniform float tear = 0.0;           // 0..1 tearing bands
uniform float tunnel = 0.0;         // 0..1 dark closing in from the edges
uniform float vessels = 0.0;        // 0..1 blood vessels with it
uniform float drain = 0.0;          // 0..1 the colour going out of things
uniform float flash = 0.0;          // 0..1 a white-hot blink
uniform float beat = 0.0;           // 0..1 the pulse
uniform float grain = 0.0;

float rand(vec2 co) {
	return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(rand(i), rand(i + vec2(1, 0)), f.x), mix(rand(i + vec2(0, 1)), rand(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0, a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(13.1, 7.7);
		a *= 0.5;
	}
	return v;
}

float vertical_bar(float pos, float y, float offset, float range) {
	return (smoothstep(pos - range, pos, y) - smoothstep(pos, pos + range, y)) * offset;
}

void fragment() {
	vec2 size = 1.0 / SCREEN_PIXEL_SIZE;
	float aspect = size.x / size.y;
	vec2 uv = SCREEN_UV;
	vec2 c = uv - 0.5;
	vec2 ca = c * vec2(aspect, 1.0);
	float r2 = dot(ca, ca);
	float r = sqrt(r2);

	// The lens: bulging out of the middle, breathing with the pulse.
	float bulge = warp * (0.34 + 0.05 * beat);
	vec2 w = c * (1.0 - bulge * 0.42 + bulge * r2 * 1.1);

	// Tearing bands, sliding sideways.
	float bars = 0.0;
	if (tear > 0.001) {
		for (float i = 0.0; i < 0.71; i += 0.1313) {
			float d = mod(TIME * (i + 0.37) * 3.1, 1.7) - 0.3;
			float o = sin(1.0 - tan(TIME * 1.24 * (i + 0.2)));
			bars += vertical_bar(d, UV.y, o * 0.035 * tear, 0.035);
		}
		float row = floor(UV.y * 130.0) / 130.0;
		bars += (rand(vec2(floor(TIME * 24.0), row)) - 0.5) * 0.012 * tear;
	}
	vec2 at = 0.5 + w + vec2(bars, 0.0);

	// Fringing from the middle out; the edges out of focus.
	vec2 dir = c * (0.012 + 0.03 * r) * fringe * 1.6;
	float lod = soft * 3.4 * smoothstep(0.12, 0.62, r);
	vec3 col = vec3(textureLod(screen, at + dir, lod).r, textureLod(screen, at, lod).g, textureLod(screen, at - dir, lod).b);

	// The colour draining, the blacks crushed, the reds kept.
	float l = dot(col, vec3(0.3, 0.59, 0.11));
	vec3 grey = vec3(l) * vec3(0.92, 0.95, 1.0);
	col = mix(col, mix(grey, col, smoothstep(0.03, 0.28, col.r - max(col.g, col.b))), drain);
	col = mix(col, max(col - 0.022, vec3(0.0)) * 1.1, drain);

	// The tunnel, and the vessels of the eye crawling in with it.
	float th = atan(ca.y, ca.x);
	vec2 pol = vec2(cos(th), sin(th)) * 2.4;
	float edge = smoothstep(0.74 - 0.5 * tunnel, 0.95 - 0.26 * tunnel, r + 0.06 * (fbm(pol + TIME * 0.2) - 0.5));
	col *= 1.0 - 0.97 * edge * clamp(tunnel * 1.6, 0.0, 1.0);
	if (vessels > 0.001) {
		float wob = fbm(ca * 3.0 + vec2(TIME * 0.05, 0.0));
		float n1 = fbm(vec2(th * 3.3, r * 4.0 - TIME * 0.07) + wob * 1.3);
		float n2 = fbm(vec2(th * 9.0 + 4.0, r * 10.0) + wob * 2.2);
		float v = 1.0 - smoothstep(0.0, 0.016 + 0.018 * r, abs(n1 - 0.5));
		v = max(v, (1.0 - smoothstep(0.0, 0.012, abs(n2 - 0.5))) * 0.6);
		float reach = smoothstep(0.86 - 0.3 * vessels, 1.0, r + 0.1 * wob);
		col = mix(col, vec3(0.16 + 0.34 * beat, 0.004, 0.012), v * reach * clamp(vessels * 1.4, 0.0, 1.0));
		col += vec3(0.05, 0.0, 0.004) * reach * beat * vessels;
	}

	col += vec3(1.0, 0.94, 0.88) * flash;
	col += (rand(uv + fract(TIME) * 7.3) - 0.5) * grain * (0.55 + 0.45 * (1.0 - l));
	COLOR = vec4(col, 1.0);
}
