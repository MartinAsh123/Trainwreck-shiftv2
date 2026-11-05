// snow_ground.gdshader
// Snow-covered ground, near and far. UV = route coordinates in metres (s along the line, z
// across), so the pattern is fixed to the land however the chunks move.
//   - wind-sculpted drifts: soft ridges and hollows in the normal and a faint blue in the hollows
//   - the scanned snow surface (CC0, art_source/world_hd) up close: grain, crust and relief
//   - sastrugi ripples and sparkle (rare glints that come and go with the view)
//   - steep slopes and scoured ridges show rock (scanned, triplanar) through the snow
//   - vertex colour R = wheel/foot dirt (trodden snow by the track and in the villages)
//   - vertex colour G = forest beyond the modelled trees: on the far hills the land reads as
//     snow-laden conifer canopy, dark with white crowns
shader_type spatial;
render_mode diffuse_lambert_wrap, specular_schlick_ggx;

#include "res://shaders/world/world_common.gdshaderinc"

uniform vec3 snow_lit : source_color = vec3(0.93, 0.95, 1.0);
uniform vec3 snow_shade : source_color = vec3(0.70, 0.78, 0.92);
uniform vec3 rock : source_color = vec3(0.26, 0.25, 0.25);
uniform vec3 dirt : source_color = vec3(0.30, 0.27, 0.24);
uniform vec3 canopy : source_color = vec3(0.035, 0.05, 0.045);
uniform float sparkle = 1.0;
uniform bool use_textures = false;
uniform sampler2D snow_albedo : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D snow_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D trodden_albedo : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D trodden_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_albedo : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;

float fbm(vec2 p) {
	return wc_fbm(p);
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
	// Rock showing through on steep ground and on scoured ridges (more on high ground).
	float hi = smoothstep(120.0, 500.0, world_p.y);
	float scour = smoothstep(0.32, 0.55, slope + (fbm(p * 0.09) - 0.5) * 0.35 + (fbm(p * 0.011) - 0.5) * 0.3 * hi);
	float dirt_k = clamp(COLOR.r * (0.6 + 0.6 * fbm(p * 0.6)), 0.0, 1.0);

	vec3 snow = mix(snow_shade, snow_lit, smoothstep(0.3, 0.75, drift));
	vec3 rk = rock * (0.7 + 0.5 * fbm(p * 0.8));
	vec3 nd = vec3(0.0, 1.0, 0.0);
	float near_k = 1.0 - smoothstep(30.0, 140.0, dist);
	if (use_textures) {
		// Scanned snow: fine grain up close, the crust's larger patches further out.
		float sa = dot(texture(snow_albedo, p * 0.45).rgb, vec3(0.333));
		float sb = dot(texture(snow_albedo, p * 0.06 + 0.37).rgb, vec3(0.333));
		snow *= mix(1.0, 0.86 + 0.16 * sa, near_k) * (0.94 + 0.08 * sb);
		if (near_k > 0.0) {
			vec3 sn = texture(snow_normal, p * 0.45).rgb * 2.0 - 1.0;
			nd = normalize(vec3(sn.x, 1.0, sn.y) * vec3(near_k * 0.7, 1.0, near_k * 0.7));
		}
		// Rock (only where it shows): triplanar, cliff structure at a distance, surface up close.
		if (scour > 0.01) {
			vec3 ra = dist < 250.0 ? wc_tri(rock_albedo, world_p * 0.09, wn).rgb : vec3(0.45);
			rk = ra * wc_tri(rock_albedo, world_p * 0.013, wn).rgb * 2.2;
		}
		// Trodden snow by the line and in the lanes.
		if (dirt_k > 0.0) {
			vec3 ta = texture(trodden_albedo, p * 0.5).rgb;
			dirt_k = clamp(dirt_k * 1.15, 0.0, 1.0);
			vec3 tro = mix(snow * 0.92, ta * vec3(0.95, 0.97, 1.0), 0.55);
			snow = mix(snow, tro, dirt_k);
			dirt_k *= 0.35;
		}
	}
	snow *= 0.96 + 0.06 * fbm(p * 3.7) * (1.0 - smoothstep(10.0, 40.0, dist));
	vec3 col = mix(snow, rk, scour);
	col = mix(col, dirt * (0.8 + 0.4 * fbm(p * 1.7)), dirt_k * 0.85);
	// Distant forest: dark canopy speckled with snow-laden crowns (no 3D trees out here).
	float forest = COLOR.g * (1.0 - scour * 0.7);
	if (forest > 0.01) {
		float crowns = smoothstep(0.42, 0.62, wc_vnoise(p * 0.22) * 0.6 + wc_vnoise(p * 0.9) * 0.4);
		vec3 can = mix(canopy, snow * 0.9, crowns * 0.75);
		col = mix(col, can, smoothstep(0.1, 0.5, forest));
	}
	ALBEDO = col;
	ROUGHNESS = mix(0.72, 0.9, max(scour, dirt_k));
	SPECULAR = 0.35;
	// Perturb the normal: drift field and scanned relief in route space (tangent frame ~ world X/Z
	// on mostly-level ground), fading on rock.
	vec3 nw = normalize(vec3(wn.x + (n_ts.x + nd.x) * (1.0 - scour), wn.y, wn.z + (n_ts.z + nd.z) * (1.0 - scour)));
	if (use_textures && scour > 0.01 && dist < 400.0) {
		vec3 rn = wc_tri_normal(rock_normal, world_p * 0.09, wn, 1.0);
		nw = normalize(mix(nw, rn, scour));
	}
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	// Sparkle: rare grains that catch the light from the viewer's direction.
	vec2 g = floor(p * 26.0);
	float h = wc_hash12(g);
	float view_k = dot(normalize(VIEW), NORMAL);
	float glint = step(0.99, h) * step(0.5, fract(h * 91.7 + view_k * 6.0 + p.x * 0.05));
	glint *= (1.0 - scour) * (1.0 - dirt_k) * (1.0 - smoothstep(4.0, 18.0, dist)) * (1.0 - forest);
	EMISSION = vec3(0.6, 0.7, 0.9) * glint * sparkle * 0.2;
	// Snow scatters light under the surface: soft, bluish.
	BACKLIGHT = vec3(0.10, 0.14, 0.22) * (1.0 - scour) * (1.0 - forest);
}
