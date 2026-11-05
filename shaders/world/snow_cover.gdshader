// snow_cover.gdshader
// Any outdoor object with snow lying on it: snow settles where the surface faces up (world
// normal), broken up by noise, thicker on top. The base colour is `base` × vertex colour, so one
// material can colour many houses, trees or rocks; `grain` adds a fine surface texture
// (wood grain along a chosen local axis, bark furrows, or plaster mottling).
shader_type spatial;
render_mode diffuse_lambert_wrap, cull_disabled;

uniform vec3 base : source_color = vec3(1.0);
uniform vec3 snow_col : source_color = vec3(0.92, 0.94, 1.0);
uniform float snow_amount : hint_range(0.0, 1.0) = 0.6;
uniform float snow_sharp = 0.18;
uniform float roughness = 0.85;
uniform float metallic_v = 0.0;
uniform int grain = 0;          // 0 plaster/stone mottle, 1 wood (along local X), 2 bark (along local Y), 3 needles
uniform float grain_scale = 1.0;

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

float vnoise3(vec3 p) {
	return (vnoise(p.xy) + vnoise(p.yz + 7.1) + vnoise(p.zx + 3.3)) / 3.0;
}

varying vec3 wn;
varying vec3 lp;

void vertex() {
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	// Instances (forests) get their own noise.
	lp = VERTEX + vec3(float(INSTANCE_ID) * 3.71, 0.0, float(INSTANCE_ID) * 1.93);
}

void fragment() {
	vec3 col = base * COLOR.rgb;
	float g = 1.0;
	if (grain == 1) {
		g = 0.82 + 0.18 * vnoise(vec2(lp.x * 2.0, lp.y * 40.0 + lp.z * 40.0) * grain_scale);
	} else if (grain == 2) {
		g = 0.7 + 0.3 * vnoise(vec2(atan(lp.z, lp.x) * 6.0, lp.y * 3.0) * grain_scale);
	} else if (grain == 3) {
		g = 0.75 + 0.25 * vnoise3(lp * 22.0 * grain_scale);
	} else {
		g = 0.9 + 0.1 * vnoise3(lp * 6.0 * grain_scale);
	}
	col *= g;
	// Snow: settles on upward faces; patchy where the faces tilt.
	float n = vnoise3(lp * 3.0) * 0.6 + vnoise3(lp * 11.0) * 0.4;
	// The shading normal (already turned toward the viewer on back faces), in world space, so
	// snow lands on the upper side whichever way a face was wound.
	vec3 wnf = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float up = wnf.y + (n - 0.5) * 0.5;
	float thresh = mix(1.1, 0.05, snow_amount);
	float k = smoothstep(thresh - snow_sharp, thresh + snow_sharp, up) * COLOR.a;
	ALBEDO = mix(col, snow_col, k);
	ROUGHNESS = mix(roughness, 0.75, k);
	METALLIC = metallic_v * (1.0 - k);
	SPECULAR = mix(0.4, 0.3, k);
	BACKLIGHT = vec3(0.08, 0.1, 0.15) * k;
}
