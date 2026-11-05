// chainlink.gdshader - galvanised chain-link fence mesh drawn on a flat panel.
// UV is in metres across the panel (the HD fence models lay them out so). The diamond wire is
// computed per pixel and antialiased with its screen-space footprint; the coverage drives hashed
// alpha, so near by the wires are crisp and see-through, far off the fence thins into a grey veil
// without shimmering or sorting problems.
shader_type spatial;
render_mode cull_disabled, depth_draw_never;

uniform vec3 wire_color : source_color = vec3(0.56, 0.57, 0.58);
uniform float cell = 0.055;          // diamond size (m)
uniform float wire = 0.0035;         // wire thickness (m)
uniform float roughness_v : hint_range(0.0, 1.0) = 0.45;

float lines(vec2 p, float w) {
	// Distance to the nearest wire of the two diagonal families, in cell units.
	vec2 d = vec2(p.x + p.y, p.x - p.y);
	vec2 f = abs(fract(d + 0.5) - 0.5);
	vec2 fw = fwidth(d) + 1e-4;
	vec2 m = 1.0 - smoothstep(vec2(w) - fw, vec2(w) + fw, f);
	return max(m.x, m.y);
}

void fragment() {
	vec2 p = UV / cell;
	float half_w = wire / cell * 0.7;
	float cov = lines(p, half_w);
	// Far away the wire's footprint exceeds a pixel: keep the mean coverage instead of aliasing.
	float footprint = length(fwidth(p));
	float mean_cov = clamp(2.0 * (2.0 * half_w), 0.0, 1.0);
	cov = mix(cov, mean_cov, smoothstep(0.35, 1.2, footprint));
	vec3 col = wire_color;
	ALBEDO = col;
	METALLIC = 0.6;
	ROUGHNESS = roughness_v;
	ALPHA = cov;
}
