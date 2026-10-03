shader_type spatial;
// World-space checker so speed is readable from above.
uniform vec3 color_a : source_color = vec3(0.93, 0.87, 0.75);
uniform vec3 color_b : source_color = vec3(0.86, 0.79, 0.66);
uniform float cell = 2.0;
varying vec3 world_pos;
void vertex() { world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 c = floor(world_pos.xz / cell);
	ALBEDO = mix(color_a, color_b, mod(c.x + c.y, 2.0));
	ROUGHNESS = 0.9;
}
