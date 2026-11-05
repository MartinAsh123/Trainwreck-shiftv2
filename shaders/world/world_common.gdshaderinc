// world_common.gdshaderinc — shared helpers for the HD landscape shaders (trees, snow, ground,
// buildings): hashes and value noise, triplanar sampling, tangent-space normal decoding, wind
// sway, and the common winter snow look (scanned CC0 snow from art_source/world_hd).

float wc_hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float wc_vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(wc_hash12(i), wc_hash12(i + vec2(1.0, 0.0)), u.x),
			mix(wc_hash12(i + vec2(0.0, 1.0)), wc_hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

float wc_vnoise3(vec3 p) {
	return (wc_vnoise(p.xy) + wc_vnoise(p.yz + 7.1) + wc_vnoise(p.zx + 3.3)) / 3.0;
}

float wc_fbm(vec2 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += a * wc_vnoise(p);
		p = p * 2.03 + vec2(17.1, 5.3);
		a *= 0.5;
	}
	return s;
}

vec3 wc_tri_weights(vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	return w / max(w.x + w.y + w.z, 1e-4);
}

vec4 wc_tri(sampler2D tex, vec3 p, vec3 n) {
	vec3 w = wc_tri_weights(n);
	return texture(tex, p.zy) * w.x + texture(tex, p.xz) * w.y + texture(tex, p.xy) * w.z;
}

// Triplanar tangent-space normal map -> world-space normal (UDN blend), strength k.
vec3 wc_tri_normal(sampler2D tex, vec3 p, vec3 n, float k) {
	vec3 w = wc_tri_weights(n);
	vec2 tx = (texture(tex, p.zy).xy * 2.0 - 1.0) * k;
	vec2 ty = (texture(tex, p.xz).xy * 2.0 - 1.0) * k;
	vec2 tz = (texture(tex, p.xy).xy * 2.0 - 1.0) * k;
	vec3 nx = vec3(0.0, tx.y, tx.x * sign(n.x));
	vec3 ny = vec3(ty.x, 0.0, ty.y * sign(n.y));
	vec3 nz = vec3(tz.x * sign(n.z), tz.y, 0.0);
	return normalize(n + nx * w.x + ny * w.y + nz * w.z);
}

// Tangent-space normal (OpenGL) from a texture sample, strength k.
vec3 wc_ts_normal(vec4 s, float k) {
	vec2 xy = (s.xy * 2.0 - 1.0) * k;
	return normalize(vec3(xy, 1.0));
}

// Planar projection of a surface along its own normal: u horizontal along the face, v down the
// slope. Lines tiles and plaster up on walls and roofs without triplanar blending.
void wc_face_frame(vec3 n, out vec3 t, out vec3 b) {
	vec3 h = cross(n, vec3(0.0, 1.0, 0.0));
	if (length(h) < 0.05) {
		h = vec3(1.0, 0.0, 0.0);
	}
	t = normalize(h);
	b = normalize(cross(t, n));
}

// Sway: tree tops lean with the wind and flutter a little; `h` = height factor (0 at the foot).
vec3 wc_wind(vec3 world_pos, float h, vec3 wind, float strength, float t) {
	float ph = dot(world_pos.xz, vec2(0.11, 0.07));
	float sway = sin(t * 0.9 + ph) * 0.6 + sin(t * 2.3 + ph * 1.7) * 0.25;
	float gust = 0.5 + 0.5 * sin(t * 0.31 + ph * 0.3);
	vec3 dir = length(wind) > 0.01 ? normalize(vec3(wind.x, 0.0, wind.z)) : vec3(1.0, 0.0, 0.0);
	return dir * (h * h) * strength * (0.25 + 0.75 * gust) * (0.6 + 0.4 * sway);
}
