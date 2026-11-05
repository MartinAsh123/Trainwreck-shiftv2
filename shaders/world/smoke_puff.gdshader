// smoke_puff.gdshader — draw pass for smoke.gdshader: a soft, billowing camera-facing puff,
// lit (moonlight, lamps) with a little self-shadowing toward its lower side, thinning with age.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_lambert_wrap, specular_disabled, shadows_disabled;

uniform vec3 smoke_col : source_color = vec3(0.62, 0.62, 0.64);
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;

varying float v_age;
varying float v_alpha;
varying float v_seed;

void vertex() {
	// Billboard keeping the particle's scale.
	float sz = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * sz, INV_VIEW_MATRIX[1] * sz, INV_VIEW_MATRIX[2] * sz, MODEL_MATRIX[3]);
	v_age = INSTANCE_CUSTOM.x;
	v_seed = INSTANCE_CUSTOM.z;
	v_alpha = COLOR.a;
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float r = length(q);
	float n = texture(noise_tex, UV * 0.7 + vec2(v_seed * 5.0, v_age * 0.6)).r;
	float n2 = texture(noise_tex, UV * 1.6 - vec2(v_age * 0.4, v_seed * 3.0)).r;
	float shape = 1.0 - smoothstep(0.25 + 0.35 * n, 1.0, r + (n2 - 0.5) * 0.35);
	float dens = shape * v_alpha * (1.0 - smoothstep(0.55, 1.0, v_age));
	// Darker, sootier when fresh; paler steam as it thins.
	vec3 col = mix(smoke_col * 0.55, smoke_col, smoothstep(0.0, 0.5, v_age));
	col *= 0.8 + 0.35 * n + 0.15 * (-q.y);
	ALBEDO = col;
	ALPHA = clamp(dens, 0.0, 1.0);
	// Normal bulging toward the camera for soft round lighting.
	NORMAL = normalize(vec3(q.x, -q.y, 1.2));
	BACKLIGHT = vec3(0.25);
}
