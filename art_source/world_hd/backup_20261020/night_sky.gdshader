// night_sky.gdshader
// Winter evening and night sky. Driven by Weather:
//   sun_dir  — below the horizon after dusk; its afterglow lingers on that side of the sky
//   moon_dir — a moon disc with a soft halo (dimmed by cloud)
//   cloud    — 0 clear … 1 overcast; snow clouds hide the stars and moon and glow faintly grey
//   wind_t   — drifts the cloud field
// Stars twinkle a little and thin out toward the horizon. The fog colour for the ground is taken
// from the same palette (Environment.fog_sky_affect).
shader_type sky;

uniform vec3 sun_dir = vec3(0.0, -0.1, -1.0);
uniform vec3 moon_dir = vec3(0.3, 0.5, 0.6);
uniform float cloud : hint_range(0.0, 1.0) = 0.4;
uniform float wind_t = 0.0;
uniform float moon_phase : hint_range(0.0, 1.0) = 0.8;    // 1 = full
uniform vec3 zenith_night : source_color = vec3(0.012, 0.018, 0.04);
uniform vec3 horizon_night : source_color = vec3(0.04, 0.055, 0.09);
uniform vec3 dusk_glow : source_color = vec3(0.55, 0.3, 0.2);
uniform vec3 dusk_blue : source_color = vec3(0.12, 0.2, 0.38);
uniform vec3 cloud_col : source_color = vec3(0.07, 0.075, 0.09);
uniform float star_brightness = 1.0;

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

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
	for (int i = 0; i < 5; i++) {
		s += a * vnoise(p);
		p = p * 2.07 + vec2(11.3, 7.9);
		a *= 0.5;
	}
	return s;
}

void sky() {
	vec3 d = EYEDIR;
	float up = clamp(d.y, -1.0, 1.0);
	vec3 sd = normalize(sun_dir);
	float sun_h = sd.y;                                   // < 0 after sunset
	float dusk = smoothstep(-0.22, 0.02, sun_h);          // 1 at sunset, 0 by astronomical night
	// Base gradient.
	float hz = pow(1.0 - max(up, 0.0), 3.0);
	vec3 col = mix(zenith_night, horizon_night, hz);
	// Twilight: a blue cast over the whole sky and an orange band low on the sunset side.
	float toward_sun = max(dot(normalize(vec3(d.x, 0.0, d.z)), normalize(vec3(sd.x, 0.0, sd.z))), 0.0);
	col += dusk_blue * dusk * (0.35 + 0.65 * hz);
	col += dusk_glow * dusk * pow(toward_sun, 3.0) * pow(1.0 - max(up, 0.0), 8.0) * 1.4;
	// Stars.
	if (!AT_HALF_RES_PASS && up > 0.0) {
		vec3 sp = d * 420.0;
		vec3 cell = floor(sp);
		float h = hash13(cell);
		float star = 0.0;
		if (h > 0.9965) {
			vec3 c = cell + 0.5 + (vec3(hash13(cell + 1.7), hash13(cell + 3.1), hash13(cell + 5.3)) - 0.5) * 0.6;
			float r = length(sp - c);
			float mag = pow(hash13(cell + 9.9), 6.0);
			float tw = 0.75 + 0.25 * sin(TIME * (2.0 + h * 9.0) + h * 80.0);
			star = (1.0 - smoothstep(0.0, 0.42 + mag * 0.4, r)) * (0.25 + 2.5 * mag) * tw;
		}
		star *= smoothstep(0.0, 0.25, up) * (1.0 - dusk * 0.9);
		col += vec3(0.85, 0.9, 1.0) * star * star_brightness * (1.0 - smoothstep(0.25, 0.85, cloud));
	}
	// Moon: disc with phase shading and a halo.
	vec3 md = normalize(moon_dir);
	float mcos = dot(d, md);
	float disc = smoothstep(0.99955, 0.99968, mcos);
	float halo = pow(max(mcos, 0.0), 180.0) * 0.25 + pow(max(mcos, 0.0), 12.0) * 0.04;
	float moon_vis = 1.0 - smoothstep(0.4, 0.95, cloud);
	// Simple maria and phase: darken one side.
	vec3 mt = normalize(cross(md, vec3(0.0, 1.0, 0.0)));
	vec3 mb = cross(mt, md);
	vec2 mp = vec2(dot(d - md * mcos, mt), dot(d - md * mcos, mb)) / 0.03;
	float maria = 0.85 + 0.15 * vnoise(mp * 4.0 + 3.0);
	float lit_side = smoothstep(-0.2, 0.2, mp.x + (moon_phase - 0.5) * 2.2);
	col += vec3(1.0, 0.97, 0.9) * disc * maria * mix(0.08, 1.6, lit_side) * moon_vis;
	col += vec3(0.6, 0.7, 0.9) * halo * (moon_vis * 0.7 + 0.3 * cloud) * smoothstep(-0.05, 0.1, md.y);
	// Clouds: a layer projected on a dome; their underside picks up a little moon and dusk light.
	if (up > -0.05) {
		vec2 cp = d.xz / (max(up, 0.0) + 0.12) * 1.6 + vec2(wind_t * 0.02, wind_t * 0.007);
		float n = fbm(cp);
		float cov = smoothstep(1.0 - cloud * 1.05, 1.15 - cloud * 0.6, n + cloud * 0.25);
		cov = max(cov, smoothstep(0.75, 1.0, cloud));
		vec3 cc = cloud_col + dusk_glow * dusk * 0.18 * pow(toward_sun, 2.0) + vec3(0.08, 0.09, 0.11) * pow(max(mcos, 0.0), 6.0) * (1.0 - cloud * 0.5);
		cc *= 0.8 + 0.4 * n;
		col = mix(col, cc, cov * smoothstep(-0.05, 0.12, up));
	}
	// Below the horizon: the fog colour.
	if (up < 0.0) {
		col = mix(col, horizon_night + dusk_blue * dusk * 0.3, smoothstep(0.0, -0.1, up));
	}
	COLOR = col;
}
