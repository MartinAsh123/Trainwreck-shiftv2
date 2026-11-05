// texture_key.gdshader
// For Tripo models whose glass is only painted into the texture (bright, colorless texels).
// Those texels become: 0 = clear glass, 1 = frosted glass, 2 = glowing (lamp glass), 3 = mirror.
// Everything else renders as the plain texture.
shader_type spatial;
render_mode blend_premul_alpha, depth_prepass_alpha, cull_back;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform int mode : hint_range(0, 3) = 0;
uniform float key_min_value : hint_range(0.0, 1.0) = 0.8;       // brightness the glass starts at (sRGB)
uniform float key_max_saturation : hint_range(0.0, 1.0) = 0.12; // above this it's a colored surface
uniform float key_softness : hint_range(0.001, 0.2) = 0.05;
uniform vec3 glass_tint : source_color = vec3(0.86, 0.9, 0.92);
uniform float clear_alpha : hint_range(0.0, 1.0) = 0.04;
uniform float frosted_alpha : hint_range(0.0, 1.0) = 0.9;
uniform float glow_energy : hint_range(0.0, 16.0) = 3.0;
uniform float surface_roughness : hint_range(0.0, 1.0) = 0.5;
// Faint fake reflections and smudges on clear glass (mode 0), so it reads as glass head-on.
uniform float sheen : hint_range(0.0, 1.0) = 0.5;

varying vec3 v_pos;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x), mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	v_pos = VERTEX;
}

float key_mask(vec3 srgb) {
	float mx = max(srgb.r, max(srgb.g, srgb.b));
	float mn = min(srgb.r, min(srgb.g, srgb.b));
	float sat = mx > 0.0 ? (mx - mn) / mx : 0.0;
	float bright = smoothstep(key_min_value - key_softness, key_min_value + key_softness, mx);
	float neutral = 1.0 - smoothstep(key_max_saturation - key_softness, key_max_saturation + key_softness, sat);
	return bright * neutral;
}

void fragment() {
	vec3 col = texture(albedo_tex, UV).rgb;
	// Thresholds are in sRGB terms; the sampler returns linear color.
	float m = key_mask(pow(col, vec3(1.0 / 2.2)));

	ALBEDO = col;
	ROUGHNESS = surface_roughness;
	if (mode == 0) {
		// Clear glass scatters almost no light of its own (premultiplied: it stays see-through
		// while its reflections are added); it turns mirror-like at grazing angles.
		float c = clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
		float fres = 0.04 + 0.96 * pow(1.0 - c, 5.0);
		// Model-space position on the glass plane (doors stand in their local XY plane).
		vec2 gp = v_pos.xy;
		float diag = gp.x * 0.8 + gp.y;
		float bands = 0.6 * exp(-pow((fract(diag * 1.6 + 0.15) - 0.5) / 0.09, 2.0))
				+ 0.35 * exp(-pow((fract(diag * 1.6 + 0.42) - 0.5) / 0.035, 2.0));
		float glow = (0.25 + 0.75 * bands) * (0.75 + 0.25 * vnoise(gp * 6.0));
		ALBEDO = mix(col, glass_tint * 0.02, m);
		EMISSION = vec3(0.8, 0.86, 0.9) * glow * sheen * 0.08 * m;
		ALPHA = mix(1.0, clamp(clear_alpha + fres * 0.6 + glow * sheen * 0.06, 0.0, 1.0), m);
		ROUGHNESS = mix(surface_roughness, 0.03, m);
		SPECULAR = 0.5;
	} else if (mode == 1) {
		ALBEDO = mix(col, glass_tint, m);
		ALPHA = mix(1.0, frosted_alpha, m);
		ROUGHNESS = mix(surface_roughness, 0.6, m);
	} else if (mode == 2) {
		EMISSION = col * glow_energy * m;
	} else {
		ALBEDO = mix(col, vec3(0.78, 0.8, 0.8), m);
		METALLIC = m;
		ROUGHNESS = mix(surface_roughness, 0.02, m);
		SPECULAR = mix(0.5, 1.0, m);
	}
}
