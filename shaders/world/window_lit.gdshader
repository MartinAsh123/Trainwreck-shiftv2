// window_lit.gdshader — a lit window at night. Behind the glass is a room seen in depth (interior
// mapping: the view ray is followed into a box room_size big, the window a part of its front
// wall): papered walls in the room's own colour, a darker boarded floor, a ceiling lit by the
// lamp, a picture or a dresser against the back wall; curtains drawn part way, lace on some.
// UV = 0..1 across the pane (x along the face frame's t, y down); COLOR.r = this window's random,
// COLOR.g = how bright its lamp is.
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;

#include "res://shaders/world/world_common.gdshaderinc"

uniform vec3 room_size = vec3(3.4, 2.8, 3.6);
uniform vec2 win_size = vec2(0.85, 1.25);
uniform float energy = 1.0;
uniform float curtain_k = 1.0;         // how far the curtains are drawn (shop windows: barely)
uniform vec3 lamp : source_color = vec3(1.0, 0.76, 0.46);

varying vec3 lp;
varying vec3 ln;
varying vec3 l_cam;

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
	l_cam = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
}

void fragment() {
	vec3 n = normalize(ln);
	vec3 t;
	vec3 b;
	wc_face_frame(n, t, b);
	float h = COLOR.r;
	// View ray in room units: x along the wall, y up, z into the house.
	vec3 rd_o = normalize(lp - l_cam);
	vec3 rd = vec3(dot(rd_o, t), -dot(rd_o, b), max(-dot(rd_o, n), 0.02)) / room_size;
	vec2 w = vec2(UV.x, 1.0 - UV.y);
	vec3 f = vec3(0.5 + (w.x - 0.5) * win_size.x / room_size.x + (h - 0.5) * 0.3,
			0.3 + w.y * win_size.y / room_size.y, 0.0);
	float tx = ((rd.x > 0.0 ? 1.0 : 0.0) - f.x) / (abs(rd.x) > 1e-5 ? rd.x : 1e-5);
	float ty = ((rd.y > 0.0 ? 1.0 : 0.0) - f.y) / (abs(rd.y) > 1e-5 ? rd.y : 1e-5);
	float tz = 1.0 / rd.z;
	float tm = min(min(tx, ty), tz);
	vec3 hit = f + rd * tm;
	vec3 paper = mix(vec3(0.62, 0.42, 0.24), vec3(0.4, 0.46, 0.32), h);
	paper = mix(paper, vec3(0.62, 0.52, 0.4), step(0.72, fract(h * 13.0)));
	paper = mix(paper, vec3(0.5, 0.22, 0.16), step(0.86, fract(h * 29.0)));
	vec3 col;
	// Corners and edges of the room fall into shadow.
	vec3 e3 = min(hit, 1.0 - hit);
	float occ;
	if (tm == tz) {
		occ = smoothstep(0.0, 0.18, min(e3.x, e3.y));
		col = paper * 0.75 * (0.9 + 0.1 * step(0.5, fract(hit.x * 16.0)));
		float pic = step(abs(hit.x - 0.25 - h * 0.5), 0.07) * step(abs(hit.y - 0.6), 0.07);
		col = mix(col, vec3(0.22, 0.15, 0.08), pic * step(0.35, h));
		float dresser = step(abs(hit.x - 0.7 + h * 0.4), 0.15) * step(hit.y, 0.32) * step(0.5, fract(h * 7.0));
		col = mix(col, vec3(0.14, 0.08, 0.04), dresser);
	} else if (tm == ty) {
		occ = smoothstep(0.0, 0.18, min(e3.x, e3.z));
		col = rd.y > 0.0 ? vec3(0.78, 0.7, 0.56) : vec3(0.22, 0.12, 0.06) * (0.85 + 0.15 * step(0.5, fract(hit.x * 7.0)));
	} else {
		occ = smoothstep(0.0, 0.18, min(e3.y, e3.z));
		col = paper * 0.9;
	}
	col *= mix(0.45, 1.0, occ);
	// Lamp hanging in the middle of the room, near the ceiling.
	vec3 lamp_p = vec3(0.5, 0.85, 0.5);
	float d = length((hit - lamp_p) * room_size);
	float light = (0.2 + 1.5 / (1.0 + d * d * 0.5)) * mix(0.55, 1.1, COLOR.g);
	vec3 room_col = col * lamp * light;
	// Curtains at the sides, folded; a valance across the top.
	float draw = mix(0.1, 0.3, fract(h * 5.3)) * curtain_k;
	float edge = min(w.x, 1.0 - w.x);
	float curtain = 1.0 - smoothstep(draw - 0.015, draw + 0.015, edge);
	curtain = max(curtain, step(0.9, w.y) * step(0.5, fract(h * 2.1)));
	vec3 cc = mix(vec3(0.42, 0.08, 0.05), vec3(0.5, 0.4, 0.22), step(0.5, fract(h * 3.7)));
	float folds = 0.7 + 0.3 * sin(w.x * 120.0 + h * 10.0);
	room_col = mix(room_col, cc * lamp * (0.65 + 0.35 * COLOR.g) * folds, curtain * 0.95);
	float lace = step(0.75, fract(h * 9.1)) * (1.0 - curtain) * step(0.5, curtain_k);
	float lace_pat = 0.75 + 0.25 * sin(w.x * 260.0) * sin(w.y * 220.0);
	room_col = mix(room_col, lamp * 0.7 * lace_pat, lace * 0.3);
	// Glazing: a faint cold reflection at grazing angles.
	float fres = pow(1.0 - clamp(abs(dot(normalize(VIEW), NORMAL)), 0.0, 1.0), 4.0);
	ALBEDO = mix(room_col * energy, vec3(0.1, 0.13, 0.2), fres * 0.6);
}
