// monster_skin.gdshader — what a passenger's skin turns into when it stops pretending (MonsterFace): it
// takes the place of the skin's own material. Drained, mottled, hide-creased (triplanar detail in the
// head's rest space, so it stays on the head wherever it turns), grown veins that stand up from the skin
// and beat, wet round the mouth and the eyes; the sockets, cheeks and temples sink in, and the mouth is
// cut open wider than a mouth goes, a torn edge with raw flesh along it. The hands go the same way.
// Works on the skinned vertices: head_inv takes the world to the head's rest space (the model's, facing +Z).
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D base_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 base_col : source_color = vec4(1.0);
uniform sampler2D skin_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D skin_mask : filter_linear_mipmap_anisotropic, repeat_enable;     // rough, height, cracks
uniform sampler2D face_map : filter_linear_mipmap_anisotropic, repeat_disable;     // veins, thick veins, blotches

uniform float amount = 0.0;
uniform float grin = 0.0;           // the hole of the mouth, 0 shut .. 1 wide
uniform float beat = 0.0;           // 0..1, the veins' pulse
uniform mat4 head_inv;              // world -> the head's rest space
uniform mat4 head_now;              // the head's rest space -> world
uniform mat4 hand_l_inv;            // world -> each hand's rest space
uniform mat4 hand_r_inv;
uniform vec3 hand_l;                // the wrists, in rest space
uniform vec3 hand_r;
uniform vec3 eye_l;
uniform vec3 eye_r;
uniform vec3 mouth;
uniform vec3 centre;
uniform float half_w = 0.03;        // half the mouth's width
uniform float drop = 0.05;          // how far the jaw hangs below the mouth at full open
uniform float eyes = 1.0;           // 0: no sockets (a face with its eyes skinned over)
uniform float neck = 0.1;           // how far down the neck it reaches

const float TILE = 13.0;            // tiles of skin detail per metre: 7.7 cm each
const float FACE = 0.085;           // half the width of face_map, m

varying vec3 hp;                    // rest-space position
varying vec3 hn;                    // rest-space normal
varying vec3 lp;                    // the same, for the nearer hand
varying vec3 ln;
varying float hand;                 // 1 on a hand or wrist
varying float right;                // which hand lp is in

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float gauss(vec2 d, float s) {
	return exp(-dot(d, d) / (2.0 * s * s));
}

float head_mask(vec3 p) {
	vec3 q = vec3(p.x, p.y < centre.y ? min(p.y + neck, centre.y) : p.y, p.z);
	return 1.0 - smoothstep(0.1, 0.15, distance(q, centre));
}

// How far the face sinks in at (x, y): sockets, the hollows under the cheekbones, the temples, the bridge.
float hollow(vec2 p) {
	vec2 cheek = vec2(abs(p.x) - max(abs(eye_l.x), abs(eye_r.x)) * 1.08, p.y - (mouth.y + 0.01));
	vec2 temple = vec2(abs(p.x) - max(abs(eye_l.x), abs(eye_r.x)) * 2.05, p.y - eye_l.y - 0.012);
	vec2 tip = vec2(p.x, p.y - (mouth.y + (eye_l.y - mouth.y) * 0.42));
	float h = 0.0105 * eyes * max(gauss(p - eye_l.xy, 0.0135), gauss(p - eye_r.xy, 0.0135));
	h += 0.0095 * gauss(cheek, 0.0145);
	h += 0.0055 * gauss(temple, 0.012);
	h += 0.013 * gauss(tip, 0.0105);                // the nose gone in, as a skull's has
	return h;
}

void vertex() {
	vec4 w = MODEL_MATRIX * vec4(VERTEX, 1.0);
	vec3 wn = mat3(MODEL_MATRIX) * NORMAL;
	hp = (head_inv * w).xyz;
	hn = mat3(head_inv) * wn;
	vec3 al = (hand_l_inv * w).xyz;
	vec3 ar = (hand_r_inv * w).xyz;
	float dl = distance(al, hand_l);
	float dr = distance(ar, hand_r);
	if (dl < dr) {
		lp = al;
		ln = mat3(hand_l_inv) * wn;
		right = 0.0;
	} else {
		lp = ar;
		ln = mat3(hand_r_inv) * wn;
		right = 1.0;
	}
	hand = 1.0 - smoothstep(0.03, 0.09, length(max(vec2(min(dl, dr)), vec2(0.0))) - 0.09 * step(0.0, 1.0));
	float a = clamp(amount, 0.0, 1.0) * head_mask(hp) * smoothstep(0.0, 0.03, hp.z - centre.z + 0.035);
	if (a > 0.001) {
		const float STEP = 0.002;
		float h = hollow(hp.xy);
		vec2 g = vec2(hollow(hp.xy + vec2(STEP, 0.0)) - hollow(hp.xy - vec2(STEP, 0.0)),
				hollow(hp.xy + vec2(0.0, STEP)) - hollow(hp.xy - vec2(0.0, STEP))) / (2.0 * STEP);
		mat3 to_model = inverse(mat3(MODEL_MATRIX)) * mat3(head_now);
		VERTEX += to_model * vec3(0.0, 0.0, -h) * a;
		NORMAL = normalize(NORMAL + to_model * vec3(g, 0.0) * a);
	}
}

// Triplanar detail: rest-space normal `n` with the hide laid over it (whiteout blend), and the mask's channels.
vec3 tan_n(vec2 uv, float bump) {
	vec2 t = (texture(skin_n, uv).xy * 2.0 - 1.0) * bump;
	return vec3(t, sqrt(max(1.0 - dot(t, t), 0.04)));
}

vec3 detail(vec3 p, vec3 n, float bump, out vec4 m) {
	vec3 b = pow(abs(n), vec3(4.0));
	b /= b.x + b.y + b.z;
	vec2 ux = p.zy * TILE, uy = p.xz * TILE, uz = p.xy * TILE;
	m = texture(skin_mask, ux) * b.x + texture(skin_mask, uy) * b.y + texture(skin_mask, uz) * b.z;
	vec3 tx = tan_n(ux, bump), ty = tan_n(uy, bump), tz = tan_n(uz, bump);
	tx = vec3(tx.xy + n.zy, abs(tx.z) * n.x);
	ty = vec3(ty.xy + n.xz, abs(ty.z) * n.y);
	tz = vec3(tz.xy + n.xy, abs(tz.z) * n.z);
	return normalize(tx.zyx * b.x + ty.xzy * b.y + tz * b.z);
}

void fragment() {
	vec4 tex = texture(base_tex, UV) * base_col;
	vec3 c = tex.rgb;
	float a = clamp(amount, 0.0, 1.0);
	float on_head = head_mask(hp);
	float luma = dot(c, vec3(0.3, 0.55, 0.15));
	// Skin, not hair or hat: warm and light enough.
	float flesh = smoothstep(0.012, 0.07, c.r - c.b) * smoothstep(0.1, 0.3, c.r);
	float head = on_head * flesh * a;
	float limb = hand * a * (1.0 - on_head);
	float m_skin = clamp(head + limb, 0.0, 1.0);

	vec3 p = on_head > 0.5 ? hp : lp;
	vec3 n0 = normalize(on_head > 0.5 ? hn : ln);
	vec4 mk;
	vec3 n = detail(p, n0, 1.15 * m_skin, mk);

	float de = min(distance(hp, eye_l), distance(hp, eye_r));
	float dm = distance(hp.xy, mouth.xy + vec2(0.0, -drop * 0.5 * grin));

	// Face space and the grown things in it.
	vec2 fuv = (hp.xy - vec2(0.0, (eye_l.y + mouth.y) * 0.5)) / (FACE * 2.0) + 0.5;
	vec2 f2 = vec2(fuv.x, 1.0 - fuv.y);
	vec3 fm = textureLod(face_map, f2, 0.0).rgb;
	const float D = 0.0014;
	float vx = texture(face_map, f2 + vec2(D, 0.0)).r - texture(face_map, f2 - vec2(D, 0.0)).r;
	float vy = texture(face_map, f2 + vec2(0.0, D)).r - texture(face_map, f2 - vec2(0.0, D)).r;
	float front = smoothstep(0.1, 0.45, n0.z) * on_head;
	float reach = mix(0.0, 1.0, smoothstep(0.0, 1.0, a * 1.15));
	float vein = fm.r * front * reach;
	float thick = fm.g * front * reach;
	n = normalize(n + vec3(-vx, vy, 0.0) * 1.6 * front * head);

	// The colour: drained blue-grey over its own shading, bruised where the blood has pooled.
	vec3 dead = mix(vec3(0.17, 0.155, 0.18), vec3(0.42, 0.39, 0.385), smoothstep(0.1, 0.8, luma * 1.25));
	dead *= 0.82 + 0.34 * mk.g;
	dead *= 1.0 - 0.5 * (1.0 - on_head);                  // the hands darker: they are nearest the eye
	float bruise = fm.b * front * 0.5 + (1.0 - smoothstep(0.018, 0.058, de)) * eyes * front;
	dead = mix(dead, vec3(0.1, 0.055, 0.085), clamp(bruise, 0.0, 1.0) * 0.8);
	dead = mix(dead, dead * vec3(0.5, 0.43, 0.4), mk.b * 0.55 * front);          // the cracks
	dead = mix(dead, vec3(0.1, 0.022, 0.05), vein * (0.62 + 0.3 * beat));
	dead = mix(dead, vec3(0.03, 0.0, 0.012), thick * 0.85);
	// Soot in the sockets.
	float socket = (1.0 - smoothstep(0.012, 0.036, de)) * eyes * on_head;
	dead = mix(dead, vec3(0.006, 0.002, 0.003), socket);

	// The mouth cut wider than a mouth: everything inside a torn edge is gone (the maw is behind it).
	float g = clamp(grin, 0.0, 1.0);
	vec2 hole_c = vec2(0.0, mouth.y - drop * 0.42 * g);
	vec2 hole_r = vec2(half_w * mix(1.0, 1.9, g), max(drop * 0.62 * g, 0.0005));
	vec2 e = (hp.xy - hole_c) / hole_r;
	float rr = pow(pow(abs(e.x), 2.5) + pow(abs(e.y), 2.5), 0.4);
	float jag = (noise(hp * vec3(95.0, 120.0, 60.0)) - 0.5) * 0.3 + (noise(hp * 330.0) - 0.5) * 0.13;
	float edge = 1.0 - (rr + jag);
	if (g > 0.02 && on_head > 0.5 && hp.z > centre.z - 0.01 && edge > 0.0) {
		discard;
	}
	float raw_ = g * on_head * (1.0 - smoothstep(0.0, 0.34, -edge)) * step(centre.z - 0.01, hp.z);
	dead = mix(dead, vec3(0.2, 0.012, 0.018), clamp(raw_ * (0.75 + 0.5 * mk.g), 0.0, 1.0));
	dead = mix(dead, vec3(0.03, 0.0, 0.004), raw_ * raw_ * raw_);

	ALBEDO = mix(c, dead, m_skin);

	float wet = max(1.0 - smoothstep(0.025, 0.075, dm), (1.0 - smoothstep(0.01, 0.04, de)) * 0.7) * head;
	wet = max(wet, raw_);
	ROUGHNESS = mix(0.9, mix(0.46 + 0.2 * mk.r, 0.14, wet), m_skin);
	SPECULAR = mix(0.5, 0.62, m_skin);
	RIM = 0.22 * m_skin;
	RIM_TINT = 0.5;
	mat3 to_world = on_head > 0.5 ? mat3(head_now) : transpose(mat3(right > 0.5 ? hand_r_inv : hand_l_inv));
	NORMAL = normalize(mat3(VIEW_MATRIX) * to_world * n);
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	EMISSION = vec3(0.09, 0.0, 0.006) * thick * (0.3 + 1.2 * beat);
}
