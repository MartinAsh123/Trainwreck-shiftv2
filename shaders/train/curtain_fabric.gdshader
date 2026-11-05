// curtain_fabric.gdshader
// Heavy damask curtain cloth. UV = (across the flat cloth, down from the heading) in metres,
// UV2.y = distance up from the hem in metres (UV2.x = 0..1 across, for the valance scallops).
//   - fine twill weave (diagonal ribs) that fades out with distance
//   - damask: a satin-woven medallion and leaf motif in the same colour, told apart only by sheen
//   - heading tape at the top with a row of pleat stitches
//   - gold bullion fringe along the hem (or along the scalloped edge of a valance)
//   - velvety rim light and a little translucency against the window
shader_type spatial;
render_mode cull_disabled;

uniform vec3 cloth : source_color = vec3(0.06, 0.17, 0.09);
uniform vec3 cloth_shade : source_color = vec3(0.025, 0.09, 0.045);
uniform vec3 gold : source_color = vec3(0.74, 0.56, 0.24);
uniform float motif_size = 0.16;        // damask repeat (m)
uniform float heading = 0.035;          // heading tape height (m)
uniform float fringe = 0.03;            // fringe length (m)
uniform int scallops = 0;               // valance: number of swags across (0 = straight hem)
uniform float scallop_depth = 0.035;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
			mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

// Damask motif (0..1 = satin): an ogee lattice with a four-lobed medallion in each cell and small
// leaf sprigs between, rows offset by half a repeat.
float damask(vec2 q) {
	q.x += 0.5 * mod(floor(q.y), 2.0);
	vec2 f = fract(q) - 0.5;
	vec2 a = abs(f);
	// Ogee lattice: wavy diamond outline.
	float ogee = abs(a.x + a.y + 0.06 * sin(atan(f.y, f.x) * 4.0) - 0.47);
	float lattice = 1.0 - smoothstep(0.012, 0.03, ogee);
	// Medallion: four lobes with a small centre.
	float r = length(f);
	float ang = atan(f.y, f.x);
	float lobes = 0.17 + 0.07 * cos(ang * 4.0);
	float med = 1.0 - smoothstep(-0.01, 0.01, r - lobes);
	med *= smoothstep(0.035, 0.055, abs(r - lobes * 0.55));     // engraved inner ring
	med = max(med, 1.0 - smoothstep(0.03, 0.045, r));
	// Leaf sprigs on the lattice corners.
	vec2 g = vec2(a.x, abs(a.y - 0.5));
	float leaf = 1.0 - smoothstep(0.0, 0.015, length(vec2(g.x * 2.2, g.y)) - 0.07);
	return max(max(lattice * 0.85, med), leaf);
}

void fragment() {
	vec2 uv = UV;
	float from_hem = UV2.y;
	vec3 col = cloth;
	float rough = 0.88;
	float satin = 0.0;

	// Hem line: straight, or scalloped swags on a valance.
	float edge = 0.0;
	if (scallops > 0) {
		float s = fract(UV2.x * float(scallops));
		edge = scallop_depth * (1.0 - sin(PI * s));
	}
	float below = from_hem - edge;          // < 0 = past the cloth edge
	if (below < -fringe) {
		discard;
	}

	if (below < 0.0) {
		// Bullion fringe: twisted gold threads hanging from the edge, uneven lengths.
		float thread_u = uv.x * 260.0;
		float id = floor(thread_u);
		float len = fringe * (0.8 + 0.2 * hash12(vec2(id, 3.0)));
		if (-below > len) {
			discard;
		}
		float across = abs(fract(thread_u) - 0.5);
		if (across > 0.38) {
			discard;
		}
		float twist = 0.5 + 0.5 * sin(-below * 600.0 + id * 2.0 + uv.x * 40.0);
		ALBEDO = gold * (0.55 + 0.45 * twist) * (1.0 - 0.6 * across);
		ROUGHNESS = 0.45;
		METALLIC = 0.3;
	} else {

	// Damask: satin motif on a twill ground.
	float d = damask(uv / motif_size);
	satin = d;
	// Twill weave: fine diagonal ribs, faded out where they would alias.
	float w = uv.x * 900.0 + uv.y * 900.0;
	float weave_fade = 1.0 - smoothstep(0.15, 0.6, fwidth(w));
	float rib = 0.5 + 0.5 * sin(w * 6.2832);
	float slub = vnoise(vec2(uv.x * 40.0, uv.y * 400.0));
	col = mix(cloth_shade, cloth, 0.8 + 0.08 * satin);
	col *= 1.0 + (rib - 0.5) * 0.12 * weave_fade * (1.0 - satin * 0.7);
	col *= 0.95 + 0.1 * slub;
	rough = mix(0.9, 0.5, satin);

	// Heading tape: slightly paler band at the top with pleat stitching.
	if (uv.y < heading) {
		col = mix(col, cloth * 1.25, 0.6);
		float stitch = (1.0 - smoothstep(0.0006, 0.0012, abs(uv.y - heading * 0.5))) *
				step(0.5, fract(uv.x * 160.0));
		col = mix(col, gold * 0.8, stitch);
		rough = 0.8;
	}
	// A narrow gold braid just above the fringe.
	float braid = 1.0 - smoothstep(0.0, 0.004, abs(below - 0.008));
	if (below < 0.014 && braid > 0.0) {
		float chev = 0.5 + 0.5 * sin((uv.x * 300.0) + abs(below - 0.008) * 900.0);
		col = mix(col, gold * (0.7 + 0.3 * chev), braid);
		rough = mix(rough, 0.45, braid);
	}

	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = mix(0.3, 0.55, satin);
	// Velvety rim light and light glowing through the cloth from the window side.
	RIM = 0.35;
	RIM_TINT = 0.6;
	BACKLIGHT = cloth * 0.35;
	}
}
