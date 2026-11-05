// wire_mesh.gdshader
// Welded steel mesh panel on a QuadMesh: square wires at `pitch`, everything between them cut out.
// `size` is the quad's size in metres (so the pitch stays the same on any panel). Painted dark
// grey-green with worn bright edges where hands grab it.
shader_type spatial;
render_mode cull_disabled;

uniform vec2 size = vec2(1.0, 1.0);
uniform float pitch = 0.05;
uniform float wire = 0.005;
uniform vec3 paint : source_color = vec3(0.16, 0.18, 0.16);

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 q = UV * size / pitch;
	vec2 f = abs(fract(q) - 0.5) * pitch;          // distance to the cell centre (m)
	float half_open = pitch * 0.5 - wire * 0.5;
	float on_wire = max(step(half_open, f.x), step(half_open, f.y));
	// Anti-alias at distance: keep wires solid instead of letting them shimmer away.
	float fw = fwidth(q.x) * pitch;
	if (on_wire < 0.5 && fw < pitch * 0.35) {
		discard;
	}
	if (fw >= pitch * 0.35 && hash12(floor(SCREEN_UV * VIEWPORT_SIZE)) > clamp(wire * 2.0 / pitch + 0.25, 0.0, 1.0)) {
		discard;
	}
	float wear = hash12(floor(q)) * smoothstep(0.35, 0.6, UV.y) * (1.0 - smoothstep(0.6, 0.85, UV.y));
	ALBEDO = mix(paint, vec3(0.42, 0.42, 0.4), wear * 0.5);
	METALLIC = 0.6;
	ROUGHNESS = mix(0.6, 0.35, wear);
}
