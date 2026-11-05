// world_pbr.gdshader — textured outdoor objects of the HD landscape (sleepers, poles, rocks,
// stumps, benches, lamp posts): scanned albedo / normal / ORM through the model's UVs, and snow
// settling on whatever faces up (world normal + noise), with the scanned snow surface.
shader_type spatial;
render_mode diffuse_lambert_wrap;

#include "res://shaders/world/world_common.gdshaderinc"

uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D snow_albedo : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D snow_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tint : source_color = vec3(1.0);
uniform float roughness_k = 1.0;
uniform float metallic_k = 0.0;
uniform float uv_scale = 1.0;
uniform vec3 snow_col : source_color = vec3(0.92, 0.94, 1.0);
uniform float snow_amount : hint_range(0.0, 1.0) = 0.6;
uniform float snow_sharp = 0.12;
uniform float snow_tile = 0.8;
uniform vec3 emission_col : source_color = vec3(0.0);
uniform float emission_k = 0.0;

varying vec3 v_world;
varying vec3 v_wn;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 uv = UV * uv_scale;
	vec3 col = texture(albedo_tex, uv).rgb * tint * COLOR.rgb;
	vec3 orm = texture(orm_tex, uv).rgb;
	vec3 nmap = texture(normal_tex, uv).rgb;
	// Snow on top: world-up of the shading normal, broken by noise.
	vec3 wn_shade = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float n1 = wc_vnoise3(v_world * 2.3) * 0.6 + wc_vnoise3(v_world * 8.0) * 0.4;
	float up = wn_shade.y + (n1 - 0.5) * 0.5;
	float th = mix(1.05, 0.1, snow_amount);
	float k = smoothstep(th - snow_sharp, th + snow_sharp, up);
	vec3 sp = v_world * snow_tile;
	float sa = dot(wc_tri(snow_albedo, sp, normalize(v_wn)).rgb, vec3(0.333));
	ALBEDO = mix(col, snow_col * (0.9 + 0.12 * sa), k);
	NORMAL_MAP = nmap;
	NORMAL_MAP_DEPTH = 1.0 - k * 0.8;
	ROUGHNESS = mix(orm.g * roughness_k, 0.65, k);
	METALLIC = orm.b * metallic_k * (1.0 - k);
	AO = orm.r;
	AO_LIGHT_AFFECT = 0.25;
	EMISSION = emission_col * emission_k;
	BACKLIGHT = vec3(0.1, 0.13, 0.2) * k;
}
