// cab_steel.gdshader — the inside of the locomotive cab as it really was: painted steel sheet.
// Walls a dark green-grey, the roof underside a light grey (which throws the lamp's light back);
// on the walls, riveted seams: rows of round rivet heads along the waist and the floor and up the
// joints between the sheets every 0.65 m, with the cover strip's edge as a fine line. All in the
// locomotive's own frame (no UVs needed), faded out where too small to resolve.
shader_type spatial;
render_mode diffuse_lambert_wrap;

uniform sampler2D detail_tex : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec3 wall_col : source_color = vec3(0.085, 0.1, 0.09);
uniform vec3 roof_col : source_color = vec3(0.52, 0.53, 0.5);
uniform float rivet_r = 0.0075;
uniform float rivet_pitch = 0.075;
uniform float seam_pitch = 0.65;
uniform vec3 rows = vec3(0.07, 1.18, 2.06);          // heights of the horizontal riveted seams
uniform vec3 origin = vec3(0.0);                       // the locomotive's origin (cab floor level), world

varying vec3 lp;
varying vec3 ln;

void vertex() {
	// The engine never moves or turns in the world (the land does), so world space is its own frame.
	lp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz - origin;
	ln = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

// Distance to the nearest rivet centre along a line at offset `d` from it, rivets every `pitch` along `u`.
float rivet_d(float u, float d, float pitch) {
	float a = abs(fract(u / pitch) - 0.5) * pitch;
	return length(vec2(a, d));
}

void fragment() {
	vec3 n = normalize(ln);
	float roof = smoothstep(0.3, 0.7, -n.y);
	vec3 detail = texture(detail_tex, UV).rgb;
	float lum = dot(detail, vec3(0.333));
	vec3 col = mix(wall_col, roof_col, roof) * (0.82 + 0.36 * lum);
	float rough = mix(0.55, 0.7, roof);
	if (roof < 0.5 && abs(n.y) < 0.5) {
		// Wall plane coordinates: along the wall (u) and up (v).
		float u = abs(n.z) > abs(n.x) ? lp.x : lp.z;
		float v = lp.y;
		float r = 10.0;
		r = min(r, rivet_d(u, v - rows.x, rivet_pitch));
		r = min(r, rivet_d(u, v - rows.y, rivet_pitch));
		r = min(r, rivet_d(u, v - rows.z, rivet_pitch));
		float seam = abs(fract(u / seam_pitch + 0.5) - 0.5) * seam_pitch;
		r = min(r, rivet_d(v, seam, rivet_pitch));
		float px = fwidth(u) + fwidth(v);
		float aa = 1.0 - smoothstep(rivet_r * 0.5, rivet_r * 1.5, px);
		// Dome: bright crown, dark rim (where paint and grime gather).
		float dome = 1.0 - smoothstep(rivet_r * 0.4, rivet_r, r);
		float rim = smoothstep(rivet_r * 0.7, rivet_r, r) * (1.0 - smoothstep(rivet_r, rivet_r * 1.5, r));
		col = mix(col, col * 1.6 + 0.02, dome * aa * 0.6);
		col *= 1.0 - rim * aa * 0.45;
		// The cover strip's edge beside each vertical seam and over each horizontal one.
		float edge = 1.0 - smoothstep(0.0, 0.0025 + px, abs(seam - 0.022));
		float hrow = min(min(abs(v - rows.x), abs(v - rows.y)), abs(v - rows.z));
		edge = max(edge, 1.0 - smoothstep(0.0, 0.0025 + px, abs(hrow - 0.022)));
		col *= 1.0 - edge * 0.3 * (1.0 - smoothstep(0.004, 0.02, px));
		rough = mix(rough, 0.4, dome * aa);
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = 0.15;
}
