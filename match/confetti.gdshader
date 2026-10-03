shader_type spatial;
// Confetti flake (CPUParticles3D draw mesh): each flake tumbles around its own random axis, so it turns in all
// directions while it flies. INSTANCE_ID picks the axis / speed, INSTANCE_CUSTOM.y is the particle's age (0..1).
render_mode unshaded, cull_disabled;

uniform float min_turns = 2.0;   // full turns over the flake's life …
uniform float max_turns = 6.0;   // … a random amount in between

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

mat3 axis_rotation(vec3 axis, float angle) {
	float s = sin(angle);
	float c = cos(angle);
	float t = 1.0 - c;
	return mat3(
		vec3(t * axis.x * axis.x + c, t * axis.x * axis.y + s * axis.z, t * axis.x * axis.z - s * axis.y),
		vec3(t * axis.x * axis.y - s * axis.z, t * axis.y * axis.y + c, t * axis.y * axis.z + s * axis.x),
		vec3(t * axis.x * axis.z + s * axis.y, t * axis.y * axis.z - s * axis.x, t * axis.z * axis.z + c));
}

void vertex() {
	float id = float(INSTANCE_ID);
	vec3 axis = normalize(vec3(hash(id * 1.7 + 0.3), hash(id * 3.1 + 1.1), hash(id * 5.3 + 2.7)) - 0.5 + 0.0001);
	float turns = mix(min_turns, max_turns, hash(id * 7.9 + 4.2));
	float angle = (INSTANCE_CUSTOM.y * turns + hash(id * 11.3 + 0.7)) * TAU;
	mat3 r = axis_rotation(axis, angle);
	VERTEX = r * VERTEX;
	NORMAL = r * NORMAL;
}

// Particle colors are sRGB; ALBEDO wants linear (otherwise flakes look pale and see-through).
vec3 srgb_to_linear(vec3 c) {
	return mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
}

void fragment() {
	ALBEDO = srgb_to_linear(COLOR.rgb);
}
