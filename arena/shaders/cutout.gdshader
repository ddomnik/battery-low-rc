shader_type spatial;
// Arena material with an occlusion cutout (§10.1): fragments between the camera and the local car, within
// cutout_radius of the camera→car line, are thinned out with a 4×4 Bayer dither (screen-door transparency).
// cutout_strength = share of fragments removed in the center (0.7 → 70 % transparent); it fades toward the edge.
// CameraRig only raises cutout_strength while the car is actually hidden.
// Only geometry above the bottom of the car is cut, so the ground the car drives on never gets a hole.
// focus_car_pos / cutout_radius are global shader parameters, set every frame by CameraRig.

uniform vec3 albedo : source_color = vec3(1.0);
uniform float roughness = 0.8;
global uniform vec3 focus_car_pos;
global uniform float cutout_radius;
global uniform float cutout_strength;
const float CAR_BOTTOM = 0.3;   // below the car origin (body bottom at rest ≈ 0.25)

float bayer4(vec2 p) {
	int x = int(mod(p.x, 4.0));
	int y = int(mod(p.y, 4.0));
	float m[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (m[y * 4 + x] + 0.5) / 16.0;
}

void fragment() {
	if (cutout_radius > 0.0 && cutout_strength > 0.0) {
		vec3 world_frag = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
		vec3 cam = INV_VIEW_MATRIX[3].xyz;
		vec3 to_car = focus_car_pos - cam;
		float t = dot(world_frag - cam, to_car) / dot(to_car, to_car);   // 0 = camera, 1 = car
		float d = distance(world_frag, cam + to_car * clamp(t, 0.0, 1.0));
		if (t < 0.97 && d < cutout_radius && world_frag.y > focus_car_pos.y - CAR_BOTTOM) {
			float removed = cutout_strength * (1.0 - smoothstep(cutout_radius * 0.7, cutout_radius, d));
			if (bayer4(FRAGCOORD.xy) < removed) {
				discard;
			}
		}
	}
	ALBEDO = albedo;
	ROUGHNESS = roughness;
}
