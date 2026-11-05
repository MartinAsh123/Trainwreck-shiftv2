// rail.gdshader — the running rails. The rail mesh stays under the train (it looks the same
// everywhere), so its rust, dirt and the odd snow lying on the foot scroll with the journey
// (`scroll` = metres travelled, set by the scenery). UV.x = metres along the rail, UV.y = position
// round the profile (0 at the foot, 1 at the head). The running surface on top is bright,
// wheel-polished steel; the sides and foot are rusty brown.
shader_type spatial;

#include "res://shaders/world/world_common.gdshaderinc"

uniform sampler2D rust_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rust_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rust_orm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float scroll = 0.0;
uniform vec3 polished : source_color = vec3(0.62, 0.62, 0.64);
uniform vec3 snow_col : source_color = vec3(0.9, 0.93, 1.0);

void fragment() {
	// Route position of this fragment along the rail (world X runs opposite to s).
	float s = scroll - UV.x;
	vec2 tuv = vec2(s * 0.8, UV.y * 0.35);
	vec3 rust = texture(rust_albedo, tuv).rgb * vec3(0.8, 0.68, 0.6);
	vec3 orm = texture(rust_orm, tuv).rgb;
	float head = smoothstep(0.93, 0.97, UV.y);        // top of the head: polished by the wheels
	float grime = wc_vnoise(vec2(s * 0.13, 0.0)) * 0.5 + wc_vnoise(vec2(s * 1.7, 3.0)) * 0.5;
	vec3 col = mix(rust * (0.7 + 0.5 * grime), polished * (0.85 + 0.15 * grime), head);
	// Snow caught on the foot, in patches along the line.
	float foot = 1.0 - smoothstep(0.08, 0.16, UV.y);
	float sn = smoothstep(0.55, 0.75, wc_vnoise(vec2(s * 0.35, 7.0))) * foot;
	ALBEDO = mix(col, snow_col, sn);
	METALLIC = mix(0.35, 0.95, head) * (1.0 - sn);
	ROUGHNESS = mix(orm.g, 0.22, head);
	NORMAL_MAP = texture(rust_normal, tuv).rgb;
	NORMAL_MAP_DEPTH = 1.0 - head;
}
