// field.gdshader — ploughed fields under snow, laid on the ground.
// UV = field coordinates in metres (U along the furrows, V across them). The snow drifts into the
// furrows; the wind scours the ridge tops so dark soil and stubble show through in lines; headlands
// (a strip round the edge, VAR `edge` in UV2.x = metres from the border) are untouched snow.
shader_type spatial;
render_mode diffuse_lambert_wrap, depth_draw_opaque, cull_back;

uniform float furrow = 0.8;                 // ridge spacing (m)
uniform float stubble : hint_range(0.0, 1.0) = 0.0;   // 1 = cereal stubble instead of plough
uniform vec3 snow_col : source_color = vec3(0.88, 0.9, 0.95);
uniform vec3 soil_col : source_color = vec3(0.16, 0.12, 0.09);
uniform vec3 straw_col : source_color = vec3(0.45, 0.38, 0.24);

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

// Laid exactly on the drawn ground's triangles (2-3 cm above); pulled a touch toward the camera
// in depth only, so it never flickers through the snow at any distance.
void vertex() {
	vec4 vp = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vp.xyz *= 0.9975;
	POSITION = PROJECTION_MATRIX * vp;
}

void fragment() {
	vec2 p = UV;
	float dist = length(VERTEX);
	float head = smoothstep(2.0, 6.0, UV2.x);             // 0 at the field edge (headland)
	float phase = p.y / furrow + (vnoise(vec2(p.x * 0.02, 0.0)) - 0.5) * 0.6;
	float ridge = 0.5 + 0.5 * cos(phase * 6.2832);
	float wind = vnoise(p * vec2(0.02, 0.06));               // scoured patches
	float bare_k = smoothstep(0.25, 0.6, wind + 0.15 * vnoise(p * 0.7)) * head;
	// Broken up: soil (or stubble) pokes through in dashes and patches, never as clean lines.
	float brk = smoothstep(0.35, 0.75, vnoise(vec2(p.x * 0.7, p.y * 1.8)));
	float stalks = mix(1.0, smoothstep(0.45, 0.8, vnoise(p * vec2(4.0, 9.0))), stubble);
	float show = smoothstep(0.66, 0.94, ridge) * bare_k * mix(1.0, brk, 0.75) * stalks;
	// Furrows finer than a pixel or two fade to their average stripe-free tone (no moire).
	float aa = 1.0 - smoothstep(0.2, 0.6, fwidth(phase));
	float far = 1.0 - aa;
	show = mix(0.16 * bare_k, show, aa);
	vec3 bare = mix(soil_col, straw_col, stubble) * (0.8 + 0.4 * vnoise(p * 3.0));
	vec3 snow = snow_col * (0.95 + 0.05 * mix(0.5, ridge, aa));
	ALBEDO = mix(snow, bare, show);
	ROUGHNESS = mix(0.75, 0.95, show);
	// Ridges shade a little on their lee side (not in the distance).
	ALBEDO *= 1.0 - 0.07 * max(sin(p.y / furrow * 6.2832), 0.0) * (1.0 - far) * head;
	BACKLIGHT = vec3(0.08, 0.1, 0.15) * (1.0 - show);
	ALPHA = smoothstep(0.0, 3.0, UV2.x);
}
