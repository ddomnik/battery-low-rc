shader_type spatial;
// Oil / glue track left by a tire (TireTrail). UV.x = the point's birth time, UV.y = 0 / 1 across the strip,
// COLOR = linear color with the tire's coating strength as alpha. Fades out at the end of its lifetime.
render_mode blend_mix, depth_draw_never, cull_disabled;

global uniform float trail_time;
uniform float lifetime = 10.0;
uniform float fade_time = 3.0;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.3;
uniform float metallic_value : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float age = trail_time - UV.x;
	float fade = clamp((lifetime - age) / fade_time, 0.0, 1.0);
	float edge = 1.0 - smoothstep(0.55, 1.0, abs(UV.y * 2.0 - 1.0));   // soft sides
	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a * fade * edge;
	ROUGHNESS = roughness_value;
	METALLIC = metallic_value;
}
