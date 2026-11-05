// snow_lump.gdshader — snow lying on things (branch pillows on the HD trees, roof caps, sills):
// the scanned snow surface (triplanar, world space), soft blue in the shade, rare glints, light
// scattering under the surface. Sways with the trees when `sway` > 0.
shader_type spatial;
render_mode diffuse_lambert_wrap;

#include "res://shaders/world/world_common.gdshaderinc"

uniform sampler2D snow_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D snow_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tint : source_color = vec3(0.93, 0.95, 1.0);
uniform vec3 shade_col : source_color = vec3(0.72, 0.8, 0.95);
uniform float tile = 0.7;              // texture repeats per metre
uniform float normal_k = 0.8;
uniform float sparkle = 1.0;
uniform float sway = 1.0;
uniform vec3 wind = vec3(1.0, 0.0, 0.0);
uniform float wind_strength = 0.2;

varying vec3 v_world;
varying vec3 v_wn;

void vertex() {
	if (sway > 0.0) {
		vec3 origin = MODEL_MATRIX[3].xyz;
		float hscale = length(MODEL_MATRIX[1].xyz);
		vec3 off = wc_wind(origin, clamp(VERTEX.y, 0.0, 1.0), wind, wind_strength * 0.03 * hscale * sway, TIME);
		VERTEX += transpose(mat3(MODEL_MATRIX)) * off / (hscale * hscale);
	}
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(v_wn);
	vec3 p = v_world * tile;
	float a = dot(wc_tri(snow_albedo, p, n).rgb, vec3(0.333));
	vec3 nw = wc_tri_normal(snow_normal, p, n, normal_k);
	float up = clamp(n.y * 0.5 + 0.5, 0.0, 1.0);
	vec3 col = mix(shade_col, tint, smoothstep(0.2, 0.9, up)) * (0.9 + 0.12 * a);
	ALBEDO = col;
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	ROUGHNESS = 0.62;
	SPECULAR = 0.35;
	float dist = length(VERTEX);
	vec2 g = floor(v_world.xz * 30.0 + v_world.y * 13.0);
	float h = wc_hash12(g);
	float vk = dot(normalize(VIEW), NORMAL);
	float glint = step(0.988, h) * step(0.5, fract(h * 91.7 + vk * 6.0)) * (1.0 - smoothstep(4.0, 25.0, dist));
	EMISSION = vec3(0.6, 0.7, 0.9) * glint * sparkle * 0.3;
	BACKLIGHT = vec3(0.12, 0.15, 0.22);
}
