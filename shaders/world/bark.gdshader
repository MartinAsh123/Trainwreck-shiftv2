// bark.gdshader — tree trunks and branches of the HD trees: scanned bark (UV from the model: u
// around, v up), crown occlusion in COLOR.r, a warm orange upper trunk where COLOR.b = 1 (Scots
// pine), snow caught on upward-facing bits and wind sway matching the foliage.
shader_type spatial;
render_mode diffuse_lambert_wrap;

#include "res://shaders/world/world_common.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tint : source_color = vec3(1.0);
uniform vec3 upper_tint : source_color = vec3(1.3, 0.95, 0.75);
uniform vec3 snow_col : source_color = vec3(0.9, 0.93, 1.0);
uniform float snow_amount : hint_range(0.0, 1.0) = 0.35;
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
	vec3 col = texture(albedo_tex, UV).rgb * tint;
	col *= mix(vec3(1.0), upper_tint, COLOR.b);
	col *= mix(0.55, 1.0, COLOR.r);
	vec3 orm = texture(orm_tex, UV).rgb;
	float n1 = wc_vnoise3(v_world * 3.0);
	float k = smoothstep(0.55, 0.85, normalize(v_wn).y + (n1 - 0.5) * 0.4) * snow_amount;
	ALBEDO = mix(col, snow_col, k);
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = 1.0 - k;
	ROUGHNESS = mix(orm.g, 0.75, k);
	AO = orm.r;
	AO_LIGHT_AFFECT = 0.3;
}
