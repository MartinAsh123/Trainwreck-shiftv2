// needles_far.gdshader — the opaque low-detail conifers (the *_lod meshes): needle-canopy texture
// on drooping skirts, snow on the upper side (COLOR.g), dark underside, crown occlusion (COLOR.r),
// the same wind sway as the near trees.
shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap;

#include "res://shaders/world/world_common.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tint : source_color = vec3(1.0);
uniform vec3 snow_col : source_color = vec3(0.88, 0.91, 0.98);
uniform float snow_amount : hint_range(0.0, 1.0) = 0.3;
uniform vec3 wind = vec3(1.0, 0.0, 0.0);
uniform float wind_strength = 0.2;

varying vec3 v_world;
varying vec3 v_wn;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float hscale = length(MODEL_MATRIX[1].xyz);
	vec3 off = wc_wind(origin, clamp(VERTEX.y, 0.0, 1.0), wind, wind_strength * 0.03 * hscale, TIME);
	VERTEX += transpose(mat3(MODEL_MATRIX)) * off / (hscale * hscale);
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 col = texture(albedo_tex, UV).rgb * tint * 1.1;
	col *= mix(0.4, 1.0, COLOR.r);
	float n1 = wc_vnoise3(v_world * 0.9) * 0.6 + wc_vnoise3(v_world * 4.0) * 0.4;
	float up = normalize(v_wn).y + (n1 - 0.5) * 0.7;
	float th = mix(1.0, 0.0, snow_amount);
	float k = smoothstep(th - 0.2, th + 0.2, up) * COLOR.g;
	// Snow sits in clumps on the needle mass, not as a sheet.
	float lum = dot(texture(albedo_tex, UV * 1.7).rgb, vec3(0.33));
	k *= smoothstep(0.02, 0.12, lum + n1 * 0.08);
	ALBEDO = mix(col, snow_col * (0.88 + 0.12 * n1), k);
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = 1.0 - k * 0.6;
	ROUGHNESS = 0.8;
	SPECULAR = 0.3;
	BACKLIGHT = vec3(0.05, 0.07, 0.05) + vec3(0.06, 0.07, 0.1) * k;
}
