// snow_ground.gdshader
// Snow-covered ground. UV = route coordinates in metres (s along the line, z across), so the
// pattern is fixed to the land however the chunks move.
//   - wind-sculpted drifts: soft ridges and hollows in the normal and a faint blue in the hollows
//   - sastrugi ripples, fine grain and sparkle (tiny glints that come and go with the view)
//   - steep slopes and the ground near the track show rock and frozen earth through the snow
//   - vertex colour R = wheel/foot dirt (0..1) for the track shoulders and village lanes
shader_type spatial;
render_mode diffuse_lambert_wrap, specular_schlick_ggx;

uniform vec3 snow_lit : source_color = vec3(0.93, 0.95, 1.0);
uniform vec3 snow_shade : source_color = vec3(0.70, 0.78, 0.92);
uniform vec3 rock : source_color = vec3(0.26, 0.25, 0.25);
uniform vec3 dirt : source_color = vec3(0.30, 0.27, 0.24);
uniform float sparkle = 1.0;

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
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p = p * 2.03 + vec2(17.1, 5.3);
		a *= 0.5;
	}
	return s;
}

varying vec3 world_n;
varying vec3 world_p;

void vertex() {
	world_n = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
	world_p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = UV;
	float dist = length(VERTEX);
	// Drifts: elongated along the prevailing wind (across the line), several scales.
	vec2 q = vec2(p.x * 0.7, p.y * 1.3);
	float d1 = fbm(q * 0.045);
	float d2 = fbm(q * 0.21 + 3.1);
	float drift = d1 * 0.7 + d2 * 0.3;
	// Ripples (sastrugi), fading with distance so they never shimmer.
	float rip_fade = 1.0 - smoothstep(25.0, 70.0, dist);
	float rip = sin(p.y * 2.3 + d2 * 9.0 + p.x * 0.4) * 0.5 + 0.5;
	// Normal from the drift field (finite differences in route space).
	float e = 0.6;
	float hx = fbm((q + vec2(e, 0.0)) * 0.21 + 3.1) - d2;
	float hz = fbm((q + vec2(0.0, e)) * 0.21 + 3.1) - d2;
	vec3 n_ts = normalize(vec3(-hx * 1.8, 1.0, -hz * 1.8) + vec3(0.0, 0.0, (rip - 0.5) * 0.18 * rip_fade));

	vec3 wn = normalize(world_n);
	float slope = 1.0 - wn.y;
	// Rock and earth showing through on steep ground and in scoured patches.
	float scour = smoothstep(0.32, 0.55, slope + (fbm(p * 0.09) - 0.5) * 0.35);
	float dirt_k = clamp(COLOR.r * (0.6 + 0.6 * fbm(p * 0.6)), 0.0, 1.0);

	vec3 snow = mix(snow_shade, snow_lit, smoothstep(0.3, 0.75, drift));
	snow *= 0.96 + 0.06 * fbm(p * 3.7) * (1.0 - smoothstep(10.0, 40.0, dist));
	vec3 col = mix(snow, rock * (0.7 + 0.5 * fbm(p * 0.8)), scour);
	col = mix(col, dirt * (0.8 + 0.4 * fbm(p * 1.7)), dirt_k * 0.85);
	ALBEDO = col;
	ROUGHNESS = mix(0.72, 0.9, max(scour, dirt_k));
	SPECULAR = 0.35;
	// Perturb the normal in view space: tangent frame ~ world X/Z on mostly-level ground.
	vec3 nw = normalize(vec3(wn.x + n_ts.x * (1.0 - scour), wn.y, wn.z + n_ts.z * (1.0 - scour)));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	// Sparkle: rare grains that catch the light from the viewer's direction.
	vec2 g = floor(p * 26.0);
	float h = hash12(g + floor(world_p.xz * 0.0));
	float view_k = dot(normalize(VIEW), NORMAL);
	float glint = step(0.985, h) * step(0.5, fract(h * 91.7 + view_k * 6.0 + p.x * 0.05));
	glint *= (1.0 - scour) * (1.0 - dirt_k) * (1.0 - smoothstep(6.0, 30.0, dist));
	EMISSION = vec3(0.6, 0.7, 0.9) * glint * sparkle * 0.25;
	// Snow scatters light under the surface: soft, bluish.
	BACKLIGHT = vec3(0.10, 0.14, 0.22) * (1.0 - scour);
}
