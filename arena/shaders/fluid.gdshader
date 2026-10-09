shader_type spatial;
// Fluid surface (FluidZone): moving noise tint, small waves, optional texture scrolled by the current,
// glow for lava. World-space so neighbouring fluids line up.
render_mode blend_mix, cull_disabled, depth_draw_always;

uniform vec4 base_color : source_color = vec4(0.25, 0.56, 0.84, 1.0);
uniform float opacity : hint_range(0.0, 1.0) = 0.72;
uniform float glow = 0.0;
uniform float crust = 0.0;                            // lava: dark crust, glowing only in the veins
uniform float wave_height = 0.05;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.1;
uniform vec2 flow = vec2(0.0);                       // m/s, world X / Z
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D pattern_tex : source_color, repeat_enable, filter_linear_mipmap, hint_default_white;
uniform bool use_pattern = false;
uniform float pattern_scale = 4.0;                    // m per texture repeat

varying vec3 world_pos;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += (sin(w.x * 0.9 + TIME * 1.4) + cos(w.z * 0.7 + TIME * 1.1)) * 0.5 * wave_height;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = world_pos.xz * 0.08 - flow * TIME * 0.08;
	float n1 = texture(noise_tex, uv + vec2(TIME * 0.01, 0.0)).r;
	float n2 = texture(noise_tex, uv * 2.3 - vec2(0.0, TIME * 0.015)).r;
	float n = n1 * 0.6 + n2 * 0.4;
	vec3 c = base_color.rgb * (0.75 + 0.5 * n);
	if (use_pattern) {
		c *= texture(pattern_tex, world_pos.xz / pattern_scale - flow * TIME / pattern_scale).rgb;
	}
	float veins = smoothstep(0.42, 0.68, n);
	ALBEDO = c * mix(1.0, 0.18 + 0.5 * veins, crust);
	ALPHA = opacity;
	ROUGHNESS = roughness_value;
	EMISSION = c * glow * mix(0.5 + n, veins * 1.6, crust);
}
