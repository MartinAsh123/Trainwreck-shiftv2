// snowflake.gdshader — draw pass for snowfall.gdshader.
// A soft round flake facing the camera, stretched along its screen-space motion (as a camera
// shutter would smear it). Brightness follows `tint` (Weather dims it at night and brightens it
// near the train's lit windows via `glow`).
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, skip_vertex_transform, shadows_disabled;

uniform vec3 tint : source_color = vec3(0.8, 0.85, 0.95);
uniform float shutter = 0.012;     // seconds of smear
uniform float opacity = 0.85;

varying float v_fade;

void vertex() {
	vec3 c = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float sz = length(MODEL_MATRIX[0].xyz);
	vec3 vel = (VIEW_MATRIX * vec4(INSTANCE_CUSTOM.xyz, 0.0)).xyz;
	vec2 m = vel.xy * shutter;
	float ml = length(m);
	vec2 dir = ml > 1e-5 ? m / ml : vec2(0.0, 1.0);
	vec2 perp = vec2(-dir.y, dir.x);
	// Quad corners: VERTEX.xy in [-0.5, 0.5].
	vec2 off = perp * VERTEX.x * sz * 2.0 + dir * VERTEX.y * (sz * 2.0 + ml);
	VERTEX = c + vec3(off, 0.0);
	// Thin out flakes right in front of the lens and far away.
	v_fade = smoothstep(0.25, 0.9, -c.z) * (1.0 - smoothstep(25.0, 40.0, -c.z)) * (sz > 0.0 ? 1.0 : 0.0);
	v_fade /= 1.0 + ml / max(sz * 2.0, 0.001) * 0.6;
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float a = 1.0 - smoothstep(0.35, 1.0, length(q));
	ALBEDO = tint;
	ALPHA = a * opacity * v_fade;
}
