// road.gdshader — a snowbound country road or cobbled town street.
// UV.x = across the road in metres (0 = centre line), UV.y = along it in metres.
//   - packed, dirty snow on the carriageway; two pairs of darker, glazed wheel tracks (left-hand
//     traffic: one pair each side of the crown); the crown and verges lighter and fluffier
//   - cobbles (town streets, `cobbles`) showing through where the tracks have worn the snow
//   - snow banks at the edges (fading out into the surrounding snow by alpha-free colour match)
shader_type spatial;
render_mode diffuse_lambert_wrap, depth_draw_opaque, cull_back;

uniform float half_width = 3.0;
uniform float cobbles : hint_range(0.0, 1.0) = 0.0;
uniform vec3 snow_col : source_color = vec3(0.86, 0.88, 0.93);
uniform vec3 packed_col : source_color = vec3(0.7, 0.71, 0.74);
uniform vec3 track_col : source_color = vec3(0.42, 0.4, 0.38);
uniform vec3 stone_col : source_color = vec3(0.36, 0.35, 0.34);

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
	float x = UV.x;
	float y = UV.y;
	float ax = abs(x);
	float dist = length(VERTEX);
	float n1 = vnoise(vec2(x * 0.9, y * 0.11));
	float n2 = vnoise(vec2(x * 5.0, y * 1.3));
	float n3 = vnoise(vec2(x * 0.4, y * 0.035));             // long patches of thin / thick snow
	// Wheel ruts: lanes at ±1.5 m, wheels ±0.65 m from each lane centre, wandering along the road.
	// Soft, broken, packed rather than dark: compacted snow polished by tyres, a little dirt.
	float wob = (vnoise(vec2(0.0, y * 0.05)) - 0.5) * 0.4;
	float lane = abs(ax - 1.5 + wob);
	float rut = 1.0 - smoothstep(0.08, 0.42, abs(lane - 0.65) + (n2 - 0.5) * 0.18);
	rut *= smoothstep(0.15, 0.55, n3 + 0.25 * n2);            // fresh snow drifted over some stretches
	float far = smoothstep(40.0, 160.0, dist);
	rut *= mix(1.0, 0.55, far);                                 // no stripes in the distance
	float edge = smoothstep(half_width - 1.0, half_width, ax);
	float crown = 1.0 - smoothstep(0.0, 0.6, ax);
	float fresh = clamp(edge + crown * 0.35 + (n1 - 0.5) * 0.5, 0.0, 1.0);
	vec3 col = mix(packed_col, snow_col, fresh);
	col = mix(col, track_col * (0.9 + 0.25 * n2), rut * (1.0 - edge) * 0.5);
	float rough = mix(0.78, 0.42, rut * (1.0 - edge));          // polished ruts catch the lamps
	// Cobbles (town streets): small granite setts in rows, rounded, each its own shade; they show
	// in patches where traffic and wind have thinned the snow, which stays in the joints.
	if (cobbles > 0.0) {
		vec2 c = vec2(x / 0.13, y / 0.12);
		c.x += hash12(vec2(floor(c.y), 7.0));
		vec2 id = floor(c);
		vec2 f = fract(c) - 0.5;
		float joint = smoothstep(0.36, 0.49, max(abs(f.x), abs(f.y)) + 0.04 * hash12(id + 3.1));
		vec3 stone = stone_col * (0.6 + 0.8 * hash12(id)) * (0.85 + 0.3 * (1.0 - dot(f, f) * 2.0));
		// Too small to resolve on screen: their average instead of shimmering.
		float aa = 1.0 - smoothstep(0.2, 0.55, max(fwidth(c.x), fwidth(c.y)));
		vec3 sett = mix(mix(stone_col * 1.1, snow_col, 0.35), mix(stone, mix(stone_col * 0.8, snow_col, 0.3), joint), aa);
		float n4 = vnoise(vec2(x * 1.6, y * 0.5));
		float thin = smoothstep(0.42, 0.78, (1.0 - n3) * 0.55 + rut * 0.3 + (n4 - 0.5) * 0.6 + (n2 - 0.5) * 0.25 + 0.2);
		float show = cobbles * thin * (1.0 - edge) * 0.85;
		col = mix(col, sett, show);
		rough = mix(rough, 0.6, show);
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.4;
	BACKLIGHT = vec3(0.06, 0.08, 0.12) * fresh;
	ALPHA = 1.0 - smoothstep(half_width - 0.1, half_width + 1.1, ax);
}
