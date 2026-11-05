// crt_screen.gdshader — the terminal's picture tube.
// The desktop (a SubViewport) glows through slightly curved glass: faint scanlines and an RGB
// mask up close, a little bloom-like softness, darker corners, and the glass itself reflects the
// room. `power` fades the picture in and out (0 = off, a dark grey-green tube).
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D screen_tex : source_color, filter_linear_mipmap;
uniform float power : hint_range(0.0, 1.0) = 1.0;
uniform float brightness = 0.62;
uniform float curvature = 0.035;

void fragment() {
	vec2 uv = UV;
	// Barrel distortion: the picture bows outward a touch toward the edges.
	vec2 c = uv - 0.5;
	uv = 0.5 + c * (1.0 + curvature * dot(c, c) * 4.0);
	float inside = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
	vec3 pic = texture(screen_tex, uv).rgb;
	// Neighbour blur for the soft phosphor glow.
	vec2 px = vec2(1.0 / 1024.0, 1.0 / 768.0);
	vec3 glow = (texture(screen_tex, uv + vec2(px.x * 1.5, 0.0)).rgb + texture(screen_tex, uv - vec2(px.x * 1.5, 0.0)).rgb +
			texture(screen_tex, uv + vec2(0.0, px.y * 1.5)).rgb + texture(screen_tex, uv - vec2(0.0, px.y * 1.5)).rgb) * 0.25;
	pic = mix(pic, glow, 0.25);
	// Scanlines and aperture mask, faded with distance so they never moiré.
	float dist = length(VERTEX);
	float fine = 1.0 - smoothstep(0.35, 1.2, dist);
	float scan = 0.88 + 0.12 * sin(uv.y * 768.0 * 3.14159);
	vec3 mask = vec3(1.0);
	float m = mod(FRAGCOORD.x, 3.0);
	mask = m < 1.0 ? vec3(1.05, 0.95, 0.95) : (m < 2.0 ? vec3(0.95, 1.05, 0.95) : vec3(0.95, 0.95, 1.05));
	pic *= mix(vec3(1.0), mask * scan, fine * 0.6);
	// Vignette.
	float vig = 1.0 - smoothstep(0.25, 0.75, length(c * vec2(1.0, 0.85)));
	pic *= mix(0.75, 1.0, vig);
	ALBEDO = vec3(0.025, 0.03, 0.028);
	EMISSION = pic * brightness * power * inside;
	ROUGHNESS = 0.22;
	SPECULAR = 0.15;
	METALLIC = 0.0;
}
