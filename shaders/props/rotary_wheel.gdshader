// rotary_wheel.gdshader
// Rotary telephone finger wheel on a QuadMesh: a glossy black ring with ten finger holes (holes
// are cut out, so the number plate behind shows through). Hole angles are counter-clockwise from
// 3 o'clock: digit 1 at 30 degrees, then every 30 degrees to 0 at 300 degrees.
shader_type spatial;

uniform vec3 wheel_color : source_color = vec3(0.025, 0.025, 0.028);
uniform float inner_radius = 0.42;     // centre card opening (fraction of the wheel radius)
uniform float hole_ring = 0.757;
uniform float hole_radius = 0.142;

void fragment() {
	vec2 p = (UV - 0.5) * vec2(2.0, -2.0);
	float r = length(p);
	if (r > 1.0 || r < inner_radius) {
		discard;
	}
	for (int i = 0; i < 10; i++) {
		float ang = radians(30.0 + 30.0 * float(i));
		vec2 c = vec2(cos(ang), sin(ang)) * hole_ring;
		if (length(p - c) < hole_radius) {
			discard;
		}
	}
	// Chamfered edges catch light: brighter near the rim and around each hole.
	float edge = smoothstep(0.94, 1.0, r);
	float near_hole = 0.0;
	for (int i = 0; i < 10; i++) {
		float ang = radians(30.0 + 30.0 * float(i));
		vec2 c = vec2(cos(ang), sin(ang)) * hole_ring;
		near_hole = max(near_hole, 1.0 - smoothstep(hole_radius, hole_radius + 0.03, length(p - c)));
	}
	ALBEDO = wheel_color + vec3(0.06) * max(edge, near_hole);
	ROUGHNESS = 0.18;
	METALLIC = 0.2;
	SPECULAR = 0.6;
}
