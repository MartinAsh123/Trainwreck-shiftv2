// ballast.gdshader — the track bed: crushed-stone ballast (scanned, CC0) under and between the
// sleepers, snow drifted onto the shoulders and in patches across the bed (thinner in the middle
// where the trains pass), oil and soot along the four-foot. UV = route metres (s along, z across).
shader_type spatial;
render_mode diffuse_lambert_wrap;

#include "res://shaders/world/world_common.gdshaderinc"

uniform sampler2D ballast_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ballast_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ballast_orm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D snow_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D snow_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tile = 0.55;              // ballast texture repeats per metre
uniform float snow_amount : hint_range(0.0, 1.0) = 0.8;
uniform vec3 snow_col : source_color = vec3(0.92, 0.94, 1.0);

void fragment() {
	vec2 p = UV;
	vec2 t = p * tile;
	vec3 b = texture(ballast_albedo, t).rgb;
	vec3 bo = texture(ballast_orm, t).rgb;
	float az = abs(p.y);
	// Soot and oil dripped between and beside the rails.
	float soot = (1.0 - smoothstep(0.5, 1.1, az)) * (0.5 + 0.5 * wc_vnoise(p * vec2(0.8, 3.0)));
	b *= mix(1.0, 0.55, soot);
	// Snow: deep on the shoulders, patchy on the crib, thin in the four-foot.
	float cover = mix(0.45, 1.0, smoothstep(0.9, 2.0, az)) * snow_amount;
	float n = wc_fbm(p * vec2(0.35, 0.9)) * 0.7 + wc_vnoise(p * 3.1) * 0.3;
	// The stones stick up through thin snow: the ballast's own cavities (its AO) fill first.
	float th = 1.0 - cover;
	float k = smoothstep(th - 0.08, th + 0.08, n + (0.55 - bo.r) * 0.45);
	vec3 s = texture(snow_albedo, p * 0.6).rgb;
	vec3 sc = snow_col * (0.9 + 0.1 * dot(s, vec3(0.333)));
	ALBEDO = mix(b, sc, k);
	vec3 nb = texture(ballast_normal, t).rgb;
	vec3 ns = texture(snow_normal, p * 0.6).rgb;
	NORMAL_MAP = mix(nb, ns, k);
	ROUGHNESS = mix(bo.g, 0.68, k);
	AO = mix(bo.r, 1.0, k);
	AO_LIGHT_AFFECT = 0.4;
	BACKLIGHT = vec3(0.1, 0.13, 0.2) * k;
}
