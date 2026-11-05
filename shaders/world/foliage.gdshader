// foliage.gdshader — the twig cards of the HD conifers and birches (assets/models/hd_world).
// Cut-out scanned twig (alpha scissor, two-sided), snow settling on the upper side of each spray,
// darker deep inside the crown (vertex colour R), wind sway, a little light through the needles.
// COLOR.g = snow may lie on this card.
shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_schlick_ggx;

#include "res://shaders/world/world_common.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec3 tint : source_color = vec3(1.0);
uniform vec3 snow_col : source_color = vec3(0.9, 0.93, 1.0);
uniform float snow_amount : hint_range(0.0, 1.0) = 0.55;
uniform float alpha_cut : hint_range(0.05, 0.95) = 0.36;
uniform float normal_k = 0.8;
// Set by the scenery from the weather every frame.
uniform vec3 wind = vec3(1.0, 0.0, 0.0);
uniform float wind_strength = 0.2;
uniform float tree_height = 15.0;      // typical instance height, metres (scales the sway)

varying vec3 v_world;
varying float v_h;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 origin = MODEL_MATRIX[3].xyz;
	float hscale = length(MODEL_MATRIX[1].xyz);
	v_h = clamp(VERTEX.y, 0.0, 1.0);
	// Sway grows with height; branch tips (bright COLOR.r) flutter a little extra.
	vec3 off = wc_wind(origin, v_h, wind, wind_strength * 0.03 * hscale, TIME);
	off += vec3(0.0, sin(TIME * 3.1 + dot(wp, vec3(1.3, 0.7, 1.1))) * 0.02, 0.0) * COLOR.r * wind_strength * hscale * 0.01;
	VERTEX += transpose(mat3(MODEL_MATRIX)) * off / (hscale * hscale);
	v_world = wp;
}

void fragment() {
	vec4 a = texture(albedo_tex, UV);
	float dist = length(VERTEX);
	// Mipmapped cut-outs thin out with distance: hold the coverage up.
	float cover = a.a * mix(1.0, 1.9, smoothstep(8.0, 70.0, dist));
	vec3 col = a.rgb * tint;
	// Crown occlusion (dark inside, lit tips).
	col *= mix(0.35, 1.0, COLOR.r);
	// Which side of the card we see: snow lies on the upper side only.
	vec3 geo_n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(geo_n, 0.0)).xyz);
	vec3 wv = normalize((INV_VIEW_MATRIX * vec4(-VIEW, 0.0)).xyz);
	if (dot(wn, wv) > 0.0) {
		wn = -wn;      // face the camera
	}
	float n1 = wc_vnoise3(v_world * 2.7) * 0.6 + wc_vnoise3(v_world * 9.0) * 0.4;
	float up = wn.y + (n1 - 0.5) * 0.6;
	float k = smoothstep(mix(1.0, 0.0, snow_amount) - 0.15, mix(1.0, 0.0, snow_amount) + 0.15, up) * COLOR.g;
	// Snow clings to the needles, so it follows the twig's own brightness a little.
	float needle = smoothstep(0.02, 0.25, dot(a.rgb, vec3(0.33)));
	k *= mix(0.6, 1.0, needle);
	col = mix(col, snow_col * (0.85 + 0.15 * n1), k);
	ALBEDO = col;
	ALPHA = cover;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	vec3 tn = wc_ts_normal(texture(normal_tex, UV), normal_k * (1.0 - k * 0.7));
	NORMAL_MAP = tn * 0.5 + 0.5;
	ROUGHNESS = mix(0.72, 0.8, k);
	SPECULAR = 0.3;
	BACKLIGHT = mix(vec3(0.06, 0.09, 0.05), vec3(0.12, 0.14, 0.18), k);
}
