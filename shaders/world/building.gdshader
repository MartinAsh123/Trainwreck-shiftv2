// building.gdshader — houses, churches and station buildings with scanned surfaces (CC0,
// art_source/world_hd). Same inputs as snow_cover.gdshader (base × vertex colour; vertex alpha =
// snow may lie here) plus a texture set projected along each face in the building's own space
// (u along the face, v down the slope), so tiles follow every roof pitch and plaster lines up on
// every wall without UVs:
//   kind 0  plaster walls (grey detail tinted by the vertex colour), stone plinth below plinth_h
//   kind 1  roof tiles (clay or slate), snow lying thick on top
//   kind 2  timber (canopies, shelters, benches)
//   kind 3  stone / platform paving
shader_type spatial;
render_mode diffuse_lambert_wrap, cull_disabled;

#include "res://shaders/world/world_common.gdshaderinc"

uniform int kind = 0;
uniform vec3 base : source_color = vec3(1.0);
uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D plinth_albedo : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D plinth_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D snow_albedo : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D snow_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tex_size = 2.5;          // metres per texture tile
uniform float plinth_h = 0.62;
uniform vec3 snow_col : source_color = vec3(0.92, 0.94, 1.0);
uniform float snow_amount : hint_range(0.0, 1.0) = 0.6;
uniform float snow_sharp = 0.18;
uniform float roughness = 0.85;
uniform float metallic_v = 0.0;
uniform float normal_k = 1.0;
// Merged village meshes (Buildings.merge_group): the height above the building's own foot is in UV.y.
uniform bool merged = false;

varying vec3 lp;
varying vec3 ln;
varying vec3 v_world;

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Face frame in the building's space (front faces only: cull is off, so flip on the back).
	// The face's own flat normal (smoothed normals bend at box corners and would smear the projection).
	vec3 n = normalize(cross(dFdx(lp), dFdy(lp)));
	if (dot(n, ln) < 0.0) {
		n = -n;
	}
	vec3 t;
	vec3 b;
	wc_face_frame(n, t, b);
	vec2 uv = vec2(dot(lp, t), dot(lp, b)) / tex_size;
	vec3 col = base * COLOR.rgb;
	vec4 alb = texture(albedo_tex, uv);
	vec3 orm = texture(orm_tex, uv).rgb;
	vec3 nts = texture(normal_tex, uv).rgb;
	float vertical = 1.0 - abs(n.y);
	if (kind == 0) {
		// Plaster: grey detail ×2 around its mean keeps the house colour.
		col *= alb.rgb * 1.25;
		// Stone plinth at the foot of the walls.
		float hy = merged ? UV.y : lp.y;
		float pl = (1.0 - smoothstep(plinth_h - 0.03, plinth_h + 0.01, hy)) * step(0.5, vertical);
		if (pl > 0.0) {
			vec2 puv = vec2(dot(lp, t), hy) / 1.6;
			col = mix(col, texture(plinth_albedo, puv).rgb * 1.1, pl);
			nts = mix(nts, texture(plinth_normal, puv).rgb, pl);
		}
	} else if (kind == 1) {
		col *= alb.rgb;
	} else {
		col *= alb.rgb * 1.1;
	}
	// Snow on whatever faces up (the shading normal turned toward the viewer).
	vec3 wnf = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float n1 = wc_vnoise3(lp * 3.0) * 0.6 + wc_vnoise3(lp * 11.0) * 0.4;
	float up = wnf.y + (n1 - 0.5) * 0.5;
	float thresh = mix(1.1, 0.05, snow_amount);
	float k = smoothstep(thresh - snow_sharp, thresh + snow_sharp, up) * COLOR.a;
	float sa = dot(texture(snow_albedo, v_world.xz * 0.5).rgb, vec3(0.333));
	ALBEDO = mix(col, snow_col * (0.9 + 0.12 * sa), k);
	vec3 sn = texture(snow_normal, v_world.xz * 0.5).rgb;
	NORMAL_MAP = mix(nts, sn, k);
	NORMAL_MAP_DEPTH = normal_k;
	ROUGHNESS = mix(roughness * mix(1.0, orm.g, 0.6), 0.7, k);
	METALLIC = metallic_v * (1.0 - k);
	AO = mix(orm.r, 1.0, k);
	AO_LIGHT_AFFECT = 0.3;
	SPECULAR = mix(0.4, 0.3, k);
	BACKLIGHT = vec3(0.08, 0.1, 0.15) * k;
}
